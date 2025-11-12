import WebKit
import DeviceCheck
import SwiftUI
import CryptoKit

// Define the environment enum used to configure the SDK
public enum VerisoulEnvironment: String {
    case dev = "dev", staging = "staging",
         sandbox = "sandbox",
         prod = "prod"
}

public final class Verisoul: NSObject {

    public let version = "0.4.63-beta.2"

    // Singleton instance of the SDK
    public static let shared = Verisoul()

    // Private properties for SDK configuration and dependencies
    private var env: VerisoulEnvironment = .dev
    private var projectId: String = ""
    private var webView: VerisoulWebView?
    private var networking: VerisoulNetworkingClientInterface!
    private let deviceInfo = SystemInfoCollector()
    private var deviceCheck: DeviceCheckInterface!
    private var deviceAttest: DeviceAttestInterface!
    private var fraudDetection: FraudDetection!
    private var eventLogger: WebSocketLogger!
    private var sessionHelper = SessionHelper.shared
    private let webViewTimeout: TimeInterval = 20.0
    
    private var dataCollectionTask: Task<Void, Never>?
    private let sessionLock = NSLock()

    // MARK: - VerisoulSDKInterface Method Implementations

    fileprivate func syncDeviceData() -> Task<(), Never> {
        return Task {
            do {
                try Task.checkCancellation()
                
                if DCDevice.current.isSupported, DCAppAttestService.shared.isSupported {
                    try await performDeviceChecks()
                } else {
                    try await handleUnsupportedDevice()
                }
                
                try Task.checkCancellation()
                
                UnifiedLogger.shared.info("Device data posted successfully.", className: String(describing: Verisoul.self))
            } catch is CancellationError {
                UnifiedLogger.shared.info("Data collection cancelled.", className: String(describing: Verisoul.self))
            } catch {
                UnifiedLogger.shared.error("Error syncing device data: \(error.localizedDescription)", className: String(describing: Verisoul.self))
            }
        }
    }

    public func configure(env: VerisoulEnvironment, projectId: String, reinitialize: Bool = false) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        do {
            UnifiedLogger.shared.info("Initializing Verisoul SDK...", className: String(describing: Verisoul.self))

            self.env = env
            self.projectId = projectId

            let sessionId = self.sessionHelper.initSessionId(projectId: projectId, env: env, reinitialize: reinitialize)

            UIDevice.current.isBatteryMonitoringEnabled = true

            self.networking = VerisoulNetworkingClient(env: env, projectId: projectId)
            self.deviceAttest = DeviceAttest(networkManager: networking, projectId: projectId)
            self.deviceCheck = DeviceCheck()
            self.eventLogger = WebSocketLogger(env: env)
            self.fraudDetection = FraudDetection(networkManager: networking, projectId: projectId)
            self.fraudDetection.setSessionId(sessionId: sessionId)
            self.fraudDetection.startGlobalCapture()

            UnifiedLogger.shared.setEventLogger(eventLogger: eventLogger)

            dataCollectionTask = syncDeviceData()
        } catch {
            UnifiedLogger.shared.error("Error during SDK configure: \(error.localizedDescription)", className: String(describing: Verisoul.self))
        }
    }

    public func reinitialize() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        do {
            // Cancel any in-flight data collection
            dataCollectionTask?.cancel()
            dataCollectionTask = nil
            
            sessionHelper.reinitializeSession(projectId: projectId, env: env)
            guard let sessionId = sessionHelper.getSessionId() else { return  }
            self.fraudDetection.reset()
            self.fraudDetection.setSessionId(sessionId: sessionId)
            self.fraudDetection.startGlobalCapture()
            
            dataCollectionTask = syncDeviceData()
        } catch {
            UnifiedLogger.shared.error("Error during reinitialization: \(error.localizedDescription)", className: String(describing: Verisoul.self))
        }
    }


    private func setSDKInfo(data: inout [String: Any]) {
        let sdkInfo = SDKInfo.init(sdkVersion: version,sdkType: InternalVerisoulCore.shared.sdkType.rawValue)
        if let sdkInfoDict = sdkInfo.toDictionary() {
                data["sdk_info"] = sdkInfoDict
            }
    }

    private func performDeviceChecks() async throws {
        guard sessionHelper.isNeedToSubmitDeviceData() else {

            guard let sessionId = sessionHelper.getSessionId() else { return }
            fraudDetection.setSessionId(sessionId: sessionId)
            try await deviceAttest.setSessionId(sessionId: sessionId)
            try Task.checkCancellation()
            try await performDeviceAttestation()
            return }

        try Task.checkCancellation()

        async let sessionIdTask = createSession()
        async let deviceDataTask = deviceInfo.collectAll()
        async let tokenTask = try? deviceCheck.generateDeviceToken()

        guard let sessionId = sessionHelper.getSessionId() else { return }

        var (_, deviceData, token) = try await (sessionIdTask, deviceDataTask, tokenTask)
        
        try Task.checkCancellation()

        fraudDetection.setSessionId(sessionId: sessionId)
        try await deviceAttest.setSessionId(sessionId: sessionId)
        UnifiedLogger.shared.initLoggerData(projectId: projectId, sessionId: sessionId)

        do {

            setSDKInfo(data: &deviceData)
            guard let isPostDeviceDataSuccess = try await networking.postDeviceData(
                sessionId: sessionId,
                data: deviceData,
                deviceCheck: token?.base64EncodedString() ?? "",
                projectId: projectId
            ) else { return  }

            try Task.checkCancellation()

            if isPostDeviceDataSuccess {
                sessionHelper.setDeviceDataCollectionIsDone()
            }

            try await performDeviceAttestation()
        } catch let error as CancellationError {
            throw error
        } catch {
            UnifiedLogger.shared.error("Error posting device data: \(error.localizedDescription)", className: String(describing: Verisoul.self))
        }
    }

    private func performDeviceAttestation() async throws {
        guard sessionHelper.isNeedToSubmitDeviceCheckData() else { return }

        do {
            guard let isAttestAppSuccess = try await deviceAttest.attestApp(projectId: projectId) else { return }
            if isAttestAppSuccess {
                sessionHelper.setDeviceCheckIsDone()
            }
        } catch {
            UnifiedLogger.shared.error("Failed to attest app: \(error.localizedDescription)", className: String(describing: Verisoul.self))
        }
    }

    private func handleUnsupportedDevice() async throws {
        guard sessionHelper.isNeedToSubmitDeviceData() else { return }

        try Task.checkCancellation()

        async let sessionIdTask = createSession()
        async let deviceDataTask = deviceInfo.collectAll()

        guard let sessionId = sessionHelper.getSessionId() else { return }

        var (_, deviceData) = try await (sessionIdTask, deviceDataTask)
        
        try Task.checkCancellation()

        fraudDetection.setSessionId(sessionId: sessionId)
        UnifiedLogger.shared.initLoggerData(projectId: projectId, sessionId: sessionId)

        do {
            setSDKInfo(data: &deviceData)

            guard let isPostDeviceDataSuccess = try await networking.postDeviceData(
                sessionId: sessionId,
                data: deviceData,
                deviceCheck: "",
                projectId: projectId
            ) else { return }

            try Task.checkCancellation()

            if isPostDeviceDataSuccess {
                sessionHelper.setDeviceDataCollectionIsDone()
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            UnifiedLogger.shared.error("Error posting unsupported device data: \(error.localizedDescription)", className: String(describing: Verisoul.self))
        }
    }

    public func session() async throws -> String {
        UnifiedLogger.shared.info("Retrieving session ID...", className: String(describing: Verisoul.self))

        if let s = sessionHelper.getSession(), !s.isExpired(), s.status.nativeDataCollection == .done {
            UnifiedLogger.shared.info("Session ID retrieved from cache: \(s.sessionId)", className: String(describing: Verisoul.self))
            return s.sessionId
        }
        
        // Refresh expired/missing session
        sessionLock.lock()
        var currentTask = dataCollectionTask
        
        if currentTask == nil && sessionHelper.isNeedToSubmitDeviceData() {
            UnifiedLogger.shared.info("Session expired or missing, starting fresh data collection", className: String(describing: Verisoul.self))
            currentTask = syncDeviceData()
            dataCollectionTask = currentTask
        }
        sessionLock.unlock()
        
        if let task = currentTask {
            UnifiedLogger.shared.info("Awaiting data collection to complete...", className: String(describing: Verisoul.self))
            
            // Wait for data collection with timeout
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await task.value
                    }
                    
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(self.webViewTimeout * 1_000_000_000))
                        throw NSError(domain: "Timeout", code: -1)
                    }
                    
                    // Wait for first one to complete then cancel the rest
                    try await group.next()
                    group.cancelAll()
                }
            } catch {
                UnifiedLogger.shared.info("Data collection await completed or timed out", className: String(describing: Verisoul.self))
            }
            
            if let s = sessionHelper.getSession(), !s.isExpired(), s.status.nativeDataCollection == .done {
                UnifiedLogger.shared.info("Session ID retrieved after data collection: \(s.sessionId)", className: String(describing: Verisoul.self))
                return s.sessionId
            }
        }
        
        UnifiedLogger.shared.info("No active collection found, polling for session...", className: String(describing: Verisoul.self))
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < webViewTimeout {
            if !sessionHelper.isNeedToSubmitDeviceData(),
               let s = sessionHelper.getSession(),
               !s.isExpired() {
                UnifiedLogger.shared.info("Session ID retrieved after polling: \(s.sessionId)", className: String(describing: Verisoul.self))
                return s.sessionId
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        
        UnifiedLogger.shared.error("Failed to retrieve session ID in \(webViewTimeout) seconds.", className: String(describing: Verisoul.self))
        throw NSError(domain: "WebViewError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Session ID retrieval timed out."])
    }

    // MARK: - Private Helper Methods

    /// Creates a new session asynchronously.
    private func createSession() async throws {
        UnifiedLogger.shared.info("Creating a new session...", className: String(describing: Verisoul.self))

        webView = VerisoulWebView()

        DispatchQueue.global().asyncAfter(deadline: .now() + webViewTimeout) { [weak self] in
            self?.webView = nil
            UnifiedLogger.shared.info("WebView cleared after timeout.", className: String(describing: Verisoul.self))
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            func safeResume(_ block: () -> Void) {
                guard !didResume else { return }
                didResume = true
                block()
            }

            guard let sessionId = sessionHelper.getSessionId() else {
                safeResume {
                    continuation.resume(throwing: NSError(domain: "SessionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Session ID is nil."]))
                }
                return
            }

            guard let webView = webView else {
                safeResume {
                    continuation.resume(throwing: NSError(domain: "WebViewError", code: -2, userInfo: [NSLocalizedDescriptionKey: "WebView is nil."]))
                }
                return
            }

            webView.startSession(env: env, projectId: projectId, sessionId: sessionId) {
                UnifiedLogger.shared.info("WebView initialized successfully.", className: String(describing: Verisoul.self))
                safeResume {
                    continuation.resume()
                }
            }
        }
    }
}
