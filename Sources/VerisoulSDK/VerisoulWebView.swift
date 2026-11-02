import Foundation
import WebKit

public class VerisoulWebView: WKWebView, WKNavigationDelegate {

    private let nativeToWebHandler = "verisoulHandler"
    private var completion: ((Result<Void, Error>) -> Void)?
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var env: VerisoulEnvironment?
    private var projectId: String?
    private var sessionId: String?
    private var sessionHelper: SessionHelper?
    private var webViewLoaded = false
    private var didComplete = false
    private var request: URLRequest?
    private var attemptsMade = 0
    // Bumped on every attempt and retry, so a watchdog from an earlier attempt does nothing
    private var attemptId = 0

    // How long one attempt may take before it is reloaded. Slow networks used to fail here:
    // a 3-second watchdog reloaded the page, the reload cancelled the load still in flight
    // (NSURLError -999), and the cancel was counted as one more retry.
    var loadTimeout: TimeInterval = 8
    var retryDelay: TimeInterval = 1
    var maxAttempts = 3
    // Stop retrying past this point so the failure surfaces inside session()'s 20-second timeout
    var totalBudget: TimeInterval = 18
    // Tests replace this to drive navigation callbacks without the network
    var loadRequest: (WKWebView, URLRequest) -> Void = { webView, request in
        webView.load(request)
    }

    private let userContentController: WKUserContentController = {
        let controller = WKUserContentController()
        return controller
    }()

    // MARK: - Initialization

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        self.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    // MARK: - WebView Setup

    public func setup() {
        // Note: WKWebView is part of the WebKit framework and is always available on iOS
        self.configuration.userContentController = userContentController
        self.configuration.userContentController.add(self, name: nativeToWebHandler)
        self.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.frame = .zero
        UnifiedLogger.shared.info("Webview init started", className: String(describing: VerisoulWebView.self))
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        UnifiedLogger.shared.info("WebView finished loading successfully.", className: String(describing: VerisoulWebView.self))
        webViewLoaded = true
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if Self.isCancellation(error) { return }
        UnifiedLogger.shared.error("WebView failed: \(error.localizedDescription)", className: String(describing: VerisoulWebView.self))
        retryOrFail()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if Self.isCancellation(error) { return }
        UnifiedLogger.shared.error("WebView failed during provisional navigation: \(error.localizedDescription)", className: String(describing: VerisoulWebView.self))
        retryOrFail()
    }

    /// Our own reload or stopLoading() cancels the navigation in flight. That's not a load failure.
    static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    // MARK: - Session Handling

    /// Starts a session by loading the specified URL in the WebView.
    /// - Parameters:
    ///   - env: The environment (dev, staging, prod) to be used.
    ///   - projectId: The project ID for the session.
    ///   - completion: A completion handler that returns the session ID once the WebView finishes loading.

    public func startSession(env: VerisoulEnvironment, projectId: String, sessionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.webViewHost(for: env)
        components.path = "/webview.html"
        components.queryItems = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "session_id", value: sessionId)
        ]

        DispatchQueue.main.async {
            self.env = env
            self.projectId = projectId
            self.sessionId = sessionId
            self.completion = completion
            self.startTime = CFAbsoluteTimeGetCurrent()
            self.didComplete = false
            self.attemptsMade = 0

            guard let url = components.url else {
                UnifiedLogger.shared.error("Invalid URL constructed for Verisoul webview.",
                                           className: String(describing: VerisoulWebView.self))
                self.safeComplete(with: .failure(VerisoulException(
                    code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                    message: "Invalid URL constructed for Verisoul webview"
                )))
                return
            }
            self.request = URLRequest(url: url)
            self.navigationDelegate = self
            self.beginAttempt()
        }
    }

    /// Loads the page and starts this attempt's watchdog. Runs on the main thread.
    private func beginAttempt() {
        guard !didComplete, let request else { return }
        attemptsMade += 1
        attemptId += 1
        let thisAttempt = attemptId
        webViewLoaded = false
        if isLoading {
            stopLoading()
        }
        loadRequest(self, request)

        // The last attempt gets only what's left of the budget, so the whole load stays inside it
        let remaining = totalBudget - (CFAbsoluteTimeGetCurrent() - startTime)
        let timeout = max(0, min(loadTimeout, remaining))
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.attemptId == thisAttempt, !self.webViewLoaded, !self.didComplete else { return }
            UnifiedLogger.shared.error("WebView load timed out after \(String(format: "%.1f", timeout)) seconds. Triggering retry.",
                                       className: String(describing: VerisoulWebView.self))
            self.retryOrFail()
        }
    }
    
    /// Maps the SDK environment to the WebView host.
    /// dev -> dev.js.verisoul.ai, sandbox -> sandbox.js.verisoul.ai,
    /// staging -> staging.js.verisoul.ai, prod -> js.verisoul.ai
    static func webViewHost(for env: VerisoulEnvironment) -> String {
        switch env {
        case .prod: return "js.verisoul.ai"
        case .sandbox: return "sandbox.js.verisoul.ai"
        case .dev: return "dev.js.verisoul.ai"
        case .staging: return "staging.js.verisoul.ai"
        }
    }

    /// Thread-safe completion to ensure we only call completion once
    private func safeComplete(with result: Result<Void, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completion?(result)
        completion = nil
    }

    /// Retries the load after `retryDelay`, or fails the session once the attempts or the time
    /// budget run out. Runs on the main thread.
    private func retryOrFail() {
        guard !didComplete, request != nil else { return }
        // Any watchdog still pending for the attempt that just ended is now stale
        attemptId += 1

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if attemptsMade >= maxAttempts || elapsed + retryDelay >= totalBudget {
            UnifiedLogger.shared.error("Error retrying webview - max retries reached",
                                       className: String(describing: VerisoulWebView.self))
            if isLoading {
                stopLoading()
            }
            safeComplete(with: .failure(VerisoulException(
                code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                message: "WebView failed to load after \(attemptsMade - 1) retries"
            )))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            self?.beginAttempt()
        }
    }
}

// MARK: - WKScriptMessageHandler

extension VerisoulWebView: WKScriptMessageHandler {

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String],
              message.name.lowercased() == nativeToWebHandler.lowercased(),
              let _ = body["session_id"] else {
            UnifiedLogger.shared.error("Webview sessionId extraction failed",
                                       className: String(describing: VerisoulWebView.self))
            UnifiedLogger.shared.error("Invalid Project ID",
                                       className: String(describing: VerisoulWebView.self))
            // Don't call completion here - let the retry/timeout logic handle it
            return
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        UnifiedLogger.shared.metric(value: (endTime - startTime),
                                    name: "web_view_session_duration",
                                    className: String(describing: VerisoulWebView.self))

        safeComplete(with: .success(()))
    }
}
