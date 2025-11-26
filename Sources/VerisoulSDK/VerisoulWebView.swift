import Foundation
import WebKit

public class VerisoulWebView: WKWebView, WKNavigationDelegate {

    private let nativeToWebHandler = "verisoulHandler"
    private var completion: ((Result<Void, Error>) -> Void)?
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var retryNumber = 0
    private var env: VerisoulEnvironment?
    private var projectId: String?
    private var sessionId: String?
    private var sessionHelper: SessionHelper?
    private var webViewLoaded = false
    private var didComplete = false

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
        self.retryNumber = 0
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
        UnifiedLogger.shared.error("WebView failed: \(error.localizedDescription)", className: String(describing: VerisoulWebView.self))
        triggerRetry()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        UnifiedLogger.shared.error("WebView failed during provisional navigation: \(error.localizedDescription)", className: String(describing: VerisoulWebView.self))
        triggerRetry()
    }

    // MARK: - Session Handling

    /// Starts a session by loading the specified URL in the WebView.
    /// - Parameters:
    ///   - env: The environment (dev, staging, prod) to be used.
    ///   - projectId: The project ID for the session.
    ///   - completion: A completion handler that returns the session ID once the WebView finishes loading.

    public func startSession(env: VerisoulEnvironment, projectId: String, sessionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        self.env = env
        self.projectId = projectId
        self.sessionId = sessionId
        self.completion = completion
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.webViewLoaded = false
        self.didComplete = false

        var components = URLComponents()
        components.scheme = "https"
        components.host = "js.verisoul.ai"
        components.path = "/\(env.rawValue)/webview.html"
        components.queryItems = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "session_id", value: sessionId)
        ]

        guard let url = components.url else {
            UnifiedLogger.shared.error("Invalid URL constructed for Verisoul webview.",
                                       className: String(describing: VerisoulWebView.self))
            safeComplete(with: .failure(VerisoulException(
                code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                message: "Invalid URL constructed for Verisoul webview"
            )))
            return
        }

        DispatchQueue.main.async {
            let request = URLRequest(url: url)
            self.navigationDelegate = self
            self.load(request)

            // Start manual timeout watchdog (e.g. 10 seconds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !self.webViewLoaded {
                    UnifiedLogger.shared.error("WebView load timed out. Triggering retry.",
                                               className: String(describing: VerisoulWebView.self))
                    self.triggerRetry()
                }
            }
        }
    }
    
    /// Thread-safe completion to ensure we only call completion once
    private func safeComplete(with result: Result<Void, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completion?(result)
        completion = nil
    }

    @objc private func triggerRetry() {
        guard let env = self.env,
              let projectId = self.projectId,
              let sessionId = self.sessionId,
              let completion = self.completion else {
            return
        }

        if retryNumber >= 3 {
            UnifiedLogger.shared.error("Error retrying webview - max retries reached",
                                       className: String(describing: VerisoulWebView.self))
            // Signal failure instead of silently returning
            safeComplete(with: .failure(VerisoulException(
                code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                message: "WebView failed to load after \(retryNumber) retries"
            )))
            return
        }

        retryNumber += 1
        startSession(env: env, projectId: projectId, sessionId: sessionId, completion: completion)
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
