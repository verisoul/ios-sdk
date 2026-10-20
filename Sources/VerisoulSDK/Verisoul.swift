import Foundation
import WebKit
import DeviceCheck
import SwiftUI
import CryptoKit

// Define the environment enum used to configure the SDK
public enum VerisoulEnvironment: String {
    case dev = "dev", staging = "staging",
         sandbox = "sandbox",
         prod = "prod"
    
    public static func from(value: String) throws -> VerisoulEnvironment {
        guard let environment = VerisoulEnvironment(rawValue: value) else {
            throw VerisoulException(
                code: VerisoulErrorCodes.INVALID_ENVIRONMENT,
                message: "Unknown environment: \(value)"
            )
        }
        return environment
    }
}

public final class Verisoul: NSObject {

    public var version: String {
        let bundle = Bundle(for: Verisoul.self)
        return (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    // Singleton instance of the SDK
    public static let shared = Verisoul()

    // Private properties for SDK configuration and dependencies
    private var env: VerisoulEnvironment = .dev
    private var projectId: String = ""
    private var webView: VerisoulWebView?
    private var networking: VerisoulNetworkingClientInterface?
    private let deviceInfo = SystemInfoCollector()
    private var deviceCheck: DeviceCheckInterface?
    private var deviceAttest: DeviceAttestInterface?
    private var fraudDetection: FraudDetection?
    private var eventLogger: WebSocketLogger?
    private var sessionHelper = SessionHelper.shared
    private let webViewTimeout: TimeInterval = 20.0
    // How long session() waits for a pass, counted only while the app is in the foreground
    private var sessionTimeout: TimeInterval = 20.0

    private var dataCollectionTask: Task<Void, Never>?
    private var dataCollectionGeneration = 0
    // Background epoch when the current pass started; a change means the pass was interrupted
    private var dataCollectionEpoch = 0
    // A pass was held because the app was in the background; starts on the next foreground
    private var deferredPassPending = false
    private var lastReinitializeTime: TimeInterval = 0
    private var reinitializeDebounceInterval: TimeInterval = 1.0
    private var dataCollectionTaskOverride: (() -> Task<Void, Never>)?
    private var touchCaptureEnabled = true
    private let sessionLock = NSLock()
    private let foregroundMonitor = ForegroundMonitor.shared

    private override init() {
        super.init()
        foregroundMonitor.setOnForegroundEdge { [weak self] in
            self?.handleForegroundEdge()
        }
    }

    // MARK: - VerisoulSDKInterface Method Implementations

    internal func _setSessionTimeout(_ timeout: TimeInterval) {
        sessionLock.lock()
        sessionTimeout = timeout
        sessionLock.unlock()
    }

    /// Pins the foreground state for tests and runs the same edge handling as a real transition.
    /// Caller must not hold `sessionLock`.
    internal func _setForegroundStateForTesting(_ foreground: Bool) {
        foregroundMonitor.setForeground(foreground, fromTest: true)
    }

    internal var _foregroundWaiterCount: Int {
        foregroundMonitor._waiterCount
    }

    internal func _setDataCollectionTaskOverride(_ override: (() -> Task<Void, Never>)?) {
        sessionLock.lock()
        dataCollectionTaskOverride = override
        sessionLock.unlock()
    }

    internal func _setReinitializeDebounceInterval(_ interval: TimeInterval) {
        sessionLock.lock()
        reinitializeDebounceInterval = interval
        sessionLock.unlock()
    }

    internal func _resetReinitializeDebounce() {
        sessionLock.lock()
        lastReinitializeTime = 0
        sessionLock.unlock()
    }

    internal var _isTouchCaptureActive: Bool {
        fraudDetection?.isCaptureActiveForTesting ?? false
    }

    internal func _resetConfiguredState() {
        sessionLock.lock()
        dataCollectionTask?.cancel()
        dataCollectionTask = nil
        fraudDetection?.pause()
        fraudDetection = nil
        networking = nil
        deviceCheck = nil
        deviceAttest = nil
        eventLogger = nil
        lastReinitializeTime = 0
        dataCollectionTaskOverride = nil
        touchCaptureEnabled = true
        deferredPassPending = false
        sessionTimeout = 20.0
        sessionLock.unlock()
        foregroundMonitor._resetForTesting(foreground: true)
    }

    private func createDataCollectionTask() -> Task<Void, Never> {
        if let override = dataCollectionTaskOverride {
            return override()
        }
        return syncDeviceData()
    }

    /// Starts a new collection pass. Caller must hold `sessionLock`.
    /// The pass clears itself from `dataCollectionTask` when it ends, so a later
    /// `session()` starts a fresh pass instead of waiting on a finished one.
    @discardableResult
    private func startDataCollectionLocked() -> Task<Void, Never> {
        let task = createDataCollectionTask()
        dataCollectionGeneration += 1
        let generation = dataCollectionGeneration
        dataCollectionTask = task
        dataCollectionEpoch = foregroundMonitor.backgroundEpoch
        deferredPassPending = false
        Task { [weak self] in
            await task.value
            self?.clearDataCollectionTask(ifGeneration: generation)
        }
        return task
    }

    private func clearDataCollectionTask(ifGeneration generation: Int) {
        sessionLock.lock()
        if dataCollectionGeneration == generation {
            dataCollectionTask = nil
        }
        sessionLock.unlock()
    }

    /// Starts a pass if the app is in the foreground. Otherwise holds it until the app comes to
    /// the foreground, since iOS suspends background apps before collection can finish.
    /// Caller must hold `sessionLock`.
    private func startOrDeferPassLocked(_ reason: String) {
        if foregroundMonitor.isForeground {
            startDataCollectionLocked()
        } else {
            deferredPassPending = true
            UnifiedLogger.shared.info("App is in the background, deferring data collection until it is in the foreground (\(reason))", className: String(describing: Verisoul.self))
        }
    }

    /// Caller must hold `sessionLock`. Touch capture starts on the next foreground otherwise.
    private func startTouchCaptureIfForegroundLocked(_ fraudDetection: FraudDetection) {
        if touchCaptureEnabled && foregroundMonitor.isForeground {
            fraudDetection.startGlobalCapture()
        }
    }

    /// Runs when the app comes to the foreground: starts deferred touch capture and collection,
    /// and restarts a pass that died. Called without `sessionLock` held.
    private func handleForegroundEdge() {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        guard let fraudDetection = self.fraudDetection else { return }
        // An ID that expired while the app was in the background gets replaced (and its pass
        // started) before anything collects for the old one
        rotateExpiredSessionLocked()
        if touchCaptureEnabled {
            fraudDetection.startGlobalCapture()
        }

        let hasLivePass = dataCollectionTask.map { !$0.isCancelled } ?? false
        if deferredPassPending || (!hasLivePass && sessionHelper.isNeedToSubmitDeviceData()) {
            UnifiedLogger.shared.info("App is in the foreground, starting data collection", className: String(describing: Verisoul.self))
            startDataCollectionLocked()
        }
    }

    /// Replaces an expired session ID the way `configure()` would, so a process that
    /// runs past the 24-hour expiry gets a new ID. Caller must hold `sessionLock`.
    private func rotateExpiredSessionLocked() {
        guard let fraudDetection = self.fraudDetection,
              let s = sessionHelper.getSession(), s.isExpired() else { return }

        UnifiedLogger.shared.info("Session ID expired, creating a new one", className: String(describing: Verisoul.self))
        dataCollectionTask?.cancel()
        dataCollectionTask = nil

        let sessionId = sessionHelper.initSessionId(projectId: projectId, env: env, reinitialize: false)
        fraudDetection.reset()
        fraudDetection.setSessionId(sessionId: sessionId)
        startTouchCaptureIfForegroundLocked(fraudDetection)
        startOrDeferPassLocked("expired session ID")
    }

    /// The stored session ID when its native data is done, it hasn't expired, and it belongs to
    /// the current project and environment.
    private func cachedSessionId() -> String? {
        guard let s = sessionHelper.getSession(), !s.isExpired(), s.status.nativeDataCollection == .done,
              s.projectId == projectId, s.env == env else { return nil }
        return s.sessionId
    }

    private func waitForDataCollection(_ task: Task<Void, Never>, timeout: TimeInterval) async throws {
        let lock = NSLock()
        var didResume = false
        var pendingCancel = false
        var cancelHandler: (() -> Void)?

        func safeResume(_ block: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            block()
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // The timeout counts only foreground time. A wall-clock timer keeps running while
                // iOS suspends the app, then fires as soon as the user opens it.
                let monitor = self.foregroundMonitor
                let waitStart = monitor.foregroundTime()
                let ticker = DispatchSource.makeTimerSource(queue: .global())
                ticker.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(50))
                ticker.setEventHandler {
                    guard monitor.foregroundTime() - waitStart >= timeout else { return }
                    ticker.cancel()
                    task.cancel()
                    safeResume {
                        continuation.resume(throwing: VerisoulException(
                            code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                            message: "Data collection timed out"
                        ))
                    }
                }
                ticker.resume()

                let handler = {
                    ticker.cancel()
                    task.cancel()
                    safeResume {
                        continuation.resume(throwing: CancellationError())
                    }
                }

                lock.lock()
                cancelHandler = handler
                let shouldCancelNow = pendingCancel
                pendingCancel = false
                lock.unlock()

                if shouldCancelNow {
                    handler()
                    return
                }

                Task {
                    await task.value
                    ticker.cancel()
                    safeResume {
                        continuation.resume()
                    }
                }
            }
        } onCancel: {
            lock.lock()
            if let handler = cancelHandler {
                lock.unlock()
                handler()
            } else {
                pendingCancel = true
                lock.unlock()
            }
        }
    }

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

    public func configure(
        env: VerisoulEnvironment,
        projectId: String,
        reinitialize: Bool = false,
        collectTouchData: Bool = true
    ) {
        // Before taking sessionLock: on the main thread the first state read can run the
        // foreground handler, which takes that lock
        foregroundMonitor.installIfNeeded()

        sessionLock.lock()
        defer { sessionLock.unlock() }

        do {
            UnifiedLogger.shared.info("Initializing Verisoul SDK...", className: String(describing: Verisoul.self))

            let previousSessionId = sessionHelper.getSessionId()
            let previousProjectId = self.projectId
            let previousEnv = self.env

            self.env = env
            self.projectId = projectId
            self.touchCaptureEnabled = collectTouchData

            let sessionId = self.sessionHelper.initSessionId(projectId: projectId, env: env, reinitialize: reinitialize)

            // A pass for an older ID must not mark the new one as collected
            if sessionId != previousSessionId || projectId != previousProjectId || env != previousEnv {
                dataCollectionTask?.cancel()
                dataCollectionTask = nil
            }

            UIDevice.current.isBatteryMonitoringEnabled = true

            let networkingClient = VerisoulNetworkingClient(env: env, projectId: projectId)
            self.networking = networkingClient
            self.deviceAttest = DeviceAttest(networkManager: networkingClient, projectId: projectId)
            self.deviceCheck = DeviceCheck()
            let logger = WebSocketLogger(env: env)
            self.eventLogger = logger
            let fraud = FraudDetection(networkManager: networkingClient, projectId: projectId)
            fraud.setSessionId(sessionId: sessionId)
            self.fraudDetection?.pause()
            self.fraudDetection = fraud
            startTouchCaptureIfForegroundLocked(fraud)

            UnifiedLogger.shared.setEventLogger(eventLogger: logger)

            startOrDeferPassLocked("configure")
        } catch {
            UnifiedLogger.shared.error("Error during SDK configure: \(error.localizedDescription)", className: String(describing: Verisoul.self))
        }
    }

    public func setTouchCaptureEnabled(_ enabled: Bool) {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        touchCaptureEnabled = enabled
        guard let fraudDetection else {
            UnifiedLogger.shared.warning(
                "setTouchCaptureEnabled() called before configure(). Ignoring.",
                className: String(describing: Verisoul.self)
            )
            return
        }

        if enabled {
            startTouchCaptureIfForegroundLocked(fraudDetection)
        } else {
            fraudDetection.pause()
        }
    }

    public func reinitialize() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        guard let fraudDetection = self.fraudDetection else {
            UnifiedLogger.shared.warning("reinitialize() called before configure(). Ignoring.", className: String(describing: Verisoul.self))
            return
        }
        
        do {
            let now = Date().timeIntervalSince1970
            if now - lastReinitializeTime < reinitializeDebounceInterval {
                UnifiedLogger.shared.info("Reinitialize request debounced.", className: String(describing: Verisoul.self))
                return
            }
            lastReinitializeTime = now

            // Cancel any in-flight data collection
            dataCollectionTask?.cancel()
            dataCollectionTask = nil
            
            sessionHelper.reinitializeSession(projectId: projectId, env: env)
            guard let sessionId = sessionHelper.getSessionId() else { return  }
            fraudDetection.reset()
            fraudDetection.setSessionId(sessionId: sessionId)
            startTouchCaptureIfForegroundLocked(fraudDetection)

            startOrDeferPassLocked("reinitialize")
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
        guard let fraudDetection = self.fraudDetection,
              let deviceAttest = self.deviceAttest,
              let deviceCheck = self.deviceCheck,
              let networking = self.networking else { return }

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
        guard let deviceAttest = self.deviceAttest else { return }
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
        guard let fraudDetection = self.fraudDetection,
              let networking = self.networking else { return }
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
        foregroundMonitor.installIfNeeded()

        if let sessionId = cachedSessionId() {
            UnifiedLogger.shared.info("Session ID retrieved from cache: \(sessionId)", className: String(describing: Verisoul.self))
            return sessionId
        }

        while true {
            // Collection runs only in the foreground, so a call made in the background waits
            // until the user opens the app. An unconfigured SDK fails fast instead.
            sessionLock.lock()
            let configured = fraudDetection != nil
            sessionLock.unlock()
            if configured && !foregroundMonitor.isForeground {
                UnifiedLogger.shared.info("App is in the background, waiting for it to enter the foreground", className: String(describing: Verisoul.self))
                try await foregroundMonitor.waitUntilForeground()
                if let sessionId = cachedSessionId() {
                    UnifiedLogger.shared.info("Session ID retrieved after entering the foreground: \(sessionId)", className: String(describing: Verisoul.self))
                    return sessionId
                }
            }

            // Refresh expired/missing session
            sessionLock.lock()
            if fraudDetection != nil && !foregroundMonitor.isForeground {
                // Back in the background before a pass could start; wait again
                sessionLock.unlock()
                continue
            }
            rotateExpiredSessionLocked()
            var currentTask = dataCollectionTask
            if let task = currentTask, task.isCancelled {
                // An earlier caller's timeout cancelled this pass, so it can't finish
                currentTask = nil
            }
            if currentTask == nil && sessionHelper.isNeedToSubmitDeviceData() {
                UnifiedLogger.shared.info("No active collection, starting fresh data collection", className: String(describing: Verisoul.self))
                currentTask = startDataCollectionLocked()
            }
            let capturedGeneration = dataCollectionGeneration
            let passEpoch = dataCollectionEpoch
            let timeout = sessionTimeout
            sessionLock.unlock()

            if let task = currentTask {
                UnifiedLogger.shared.info("Awaiting data collection to complete...", className: String(describing: Verisoul.self))

                // Wait for data collection with timeout
                do {
                    try await waitForDataCollection(task, timeout: timeout)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as VerisoulException {
                    // The native data can land while App Attest is still running
                    if let sessionId = cachedSessionId() {
                        UnifiedLogger.shared.info("Session ID retrieved at timeout: \(sessionId)", className: String(describing: Verisoul.self))
                        return sessionId
                    }
                    // Timeout occurred - rethrow immediately with the standardized error code
                    // Don't fall through to polling loop which would double the wait time
                    UnifiedLogger.shared.error("Data collection timed out: \(error.localizedDescription)", className: String(describing: Verisoul.self))
                    throw error
                } catch {
                    // Other errors (like task cancellation on success) - continue to check session
                    UnifiedLogger.shared.info("Data collection completed", className: String(describing: Verisoul.self))
                }

                if let sessionId = cachedSessionId() {
                    UnifiedLogger.shared.info("Session ID retrieved after data collection: \(sessionId)", className: String(describing: Verisoul.self))
                    return sessionId
                }

                sessionLock.lock()
                let generationNow = dataCollectionGeneration
                let hasNewTask = dataCollectionTask != nil
                sessionLock.unlock()
                if generationNow != capturedGeneration, hasNewTask {
                    continue
                }

                // The pass ended without native data. Fail now instead of polling; the next
                // session() call starts a fresh pass.
                if sessionHelper.isNeedToSubmitDeviceData() {
                    clearDataCollectionTask(ifGeneration: capturedGeneration)
                    // The app went to the background during this pass, so iOS may have cut it
                    // off. Wait for the foreground and start a fresh pass.
                    if foregroundMonitor.backgroundEpoch != passEpoch {
                        UnifiedLogger.shared.info("Data collection was interrupted by the app going to the background, retrying in the foreground", className: String(describing: Verisoul.self))
                        continue
                    }
                    UnifiedLogger.shared.error("Data collection failed", className: String(describing: Verisoul.self))
                    throw VerisoulException(
                        code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                        message: "Data collection failed"
                    )
                }
            }

            break
        }
        
        UnifiedLogger.shared.info("No active collection found, polling for session...", className: String(describing: Verisoul.self))
        sessionLock.lock()
        let pollingTimeout = sessionTimeout
        sessionLock.unlock()
        // Counts only foreground time, like the collection timeout
        let pollingStart = foregroundMonitor.foregroundTime()
        while foregroundMonitor.foregroundTime() - pollingStart < pollingTimeout {
            if let sessionId = cachedSessionId() {
                UnifiedLogger.shared.info("Session ID retrieved after polling: \(sessionId)", className: String(describing: Verisoul.self))
                return sessionId
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        UnifiedLogger.shared.error("Failed to retrieve session ID in \(pollingTimeout) seconds.", className: String(describing: Verisoul.self))
        throw VerisoulException(
            code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
            message: "Session ID retrieval timed out after \(pollingTimeout) seconds"
        )
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
                    continuation.resume(throwing: VerisoulException(
                        code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                        message: "Session ID is nil"
                    ))
                }
                return
            }

            guard let webView = webView else {
                safeResume {
                    continuation.resume(throwing: VerisoulException(
                        code: VerisoulErrorCodes.WEBVIEW_UNAVAILABLE,
                        message: "WebView is nil"
                    ))
                }
                return
            }

            webView.startSession(env: env, projectId: projectId, sessionId: sessionId) { result in
                switch result {
                case .success:
                    UnifiedLogger.shared.info("WebView initialized successfully.", className: String(describing: Verisoul.self))
                    safeResume {
                        continuation.resume()
                    }
                case .failure(let error):
                    UnifiedLogger.shared.error("WebView initialization failed: \(error.localizedDescription)", className: String(describing: Verisoul.self))
                    safeResume {
                        if let verisoulError = error as? VerisoulException {
                            continuation.resume(throwing: verisoulError)
                        } else {
                            continuation.resume(throwing: VerisoulException(
                                code: VerisoulErrorCodes.SESSION_UNAVAILABLE,
                                message: "WebView initialization failed",
                                cause: error
                            ))
                        }
                    }
                }
            }
        }
    }
}
