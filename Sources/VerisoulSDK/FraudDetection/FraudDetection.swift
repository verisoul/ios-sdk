import UIKit
import CoreMotion

struct AccelerometerData: Codable {
    let timestamp: [Int]
    let x: [Double]
    let y: [Double]
    let z: [Double]

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case x
        case y
        case z
    }
}

struct TouchData: Codable {
    let x: CGFloat
    let y: CGFloat
    let upTimestamp: Int64
    let downTimestamp: Int64

    private enum CodingKeys: String, CodingKey {
        case upTimestamp = "up_timestamp"
        case downTimestamp = "down_timestamp"
        case x
        case y
    }
}

struct SensorPayload: Codable {
    let accelerometer: AccelerometerData
    let sampleNumber: Int
    let touch: TouchData
    let sessionId: String?
    let projectId: String?


    private enum CodingKeys: String, CodingKey {
        case sampleNumber = "sample_number"
        case sessionId = "session_id"
        case projectId = "project_id"
        case accelerometer
        case touch
    }
}

final class TouchCaptureGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var capturer: FraudDetection?
    private var touchStartTimes: [ObjectIdentifier: Date] = [:]

    init(capturer: FraudDetection) {
        self.capturer = capturer
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let now = Date()
        for touch in touches {
            touchStartTimes[ObjectIdentifier(touch)] = now
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let identifier = ObjectIdentifier(touch)
            let downTime = touchStartTimes.removeValue(forKey: identifier) ?? Date()
            capturer?.handleTouchEnded(touch: touch.location(in: view), downTime: downTime)
        }

        // This recognizer only observes touches. Failing ensures it never wins
        // recognition or changes the host application's gesture handling.
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            touchStartTimes.removeValue(forKey: ObjectIdentifier(touch))
        }
        state = .failed
    }

    override func reset() {
        touchStartTimes.removeAll()
        super.reset()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

public class FraudDetection: NSObject {

    // Capture state is shared across threads: stop() runs from send completions on the Swift
    // concurrency pool, from the 5-minute work item on a global queue, and from pause()/reset()
    // on whatever thread called configure()/reinitialize(). Every field below is read and
    // written only while holding stateLock. It is a leaf lock: never call the logger,
    // SessionHelper, UIKit or the network while holding it. Starting and stopping the motion
    // manager is the one exception, so a stop can't race a start.
    private let stateLock = NSLock()
    private var attachedWindows = NSHashTable<UIWindow>(options: .weakMemory)
    private var timer: Timer?
    private var sendCount = 0
    private var projectId: String?
    private var sessionId: String?
    private var networkManager: VerisoulNetworkingClientInterface
    private var payloadQueue: [SensorPayload] = []
    private let accelerometerUpdateInterval: TimeInterval = 1.0 / 50.0
    private var isCaptureActive = false
    private var didScheduleInitialSample = false
    private var isAccelerometerAvailable = true
    // The 5-minute stop. Store it so stop() can cancel it.
    private(set) var workItem: DispatchWorkItem?

    init(networkManager: VerisoulNetworkingClientInterface, projectId: String?) {
        self.networkManager = networkManager
        self.projectId = projectId
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    var isCaptureActiveForTesting: Bool {
        withStateLock { isCaptureActive }
    }

    var sendCountForTesting: Int {
        withStateLock { sendCount }
    }

    var hasPendingStopTimersForTesting: Bool {
        withStateLock { workItem != nil || timer != nil }
    }

    /// Lets tests stand in for the 5-minute work item on the simulator, which has no
    /// accelerometer and so never creates one.
    func _setWorkItemForTesting(_ item: DispatchWorkItem?) {
        withStateLock { workItem = item }
    }

    func reset() {
        pause()
        withStateLock {
            sendCount = 0
            didScheduleInitialSample = false
        }
    }

    public func setSessionId(sessionId: String) {
        withStateLock { self.sessionId = sessionId }
        self.flushPayloadQueue()
    }

    public func startGlobalCapture() {
        guard SessionHelper.shared.isNeedToSubmitTouchData() else { return }

        stateLock.lock()
        guard !isCaptureActive else {
            stateLock.unlock()
            return
        }
        isCaptureActive = true
        isAccelerometerAvailable = true
        let scheduleInitialSample = !didScheduleInitialSample
        didScheduleInitialSample = true
        stateLock.unlock()

        setupMotionManager(updateInterval: accelerometerUpdateInterval)
        if scheduleInitialSample {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.handleTouchEnded(touch: nil, downTime: Date())
            }
        }
        DispatchQueue.main.async {
            self.periodicAttachGesture()
        }
    }

    public func stop() {
        stop(markCollectionDone: true)
    }

    func pause() {
        stop(markCollectionDone: false)
    }

    private func stop(markCollectionDone: Bool) {
        // Take everything that needs tearing down while holding the lock, so concurrent
        // stop() calls each see a consistent state and only one of them tears it down.
        stateLock.lock()
        let wasActive = isCaptureActive
        isCaptureActive = false
        isAccelerometerAvailable = true
        motionManager.stopAccelerometerUpdates()
        let pendingWorkItem = workItem
        workItem = nil
        let pendingTimer = timer
        timer = nil
        let windows = attachedWindows.allObjects
        attachedWindows.removeAllObjects()
        stateLock.unlock()

        pendingWorkItem?.cancel()
        if let pendingTimer {
            // The attach-retry timer is scheduled on the main run loop and must be
            // invalidated there.
            if Thread.isMainThread {
                pendingTimer.invalidate()
            } else {
                DispatchQueue.main.async { pendingTimer.invalidate() }
            }
        }
        removeGestureRecognizers(from: windows)
        if markCollectionDone {
            SessionHelper.shared.setTouchDataCollectionIsDone()
        }
        if wasActive || pendingWorkItem != nil || pendingTimer != nil || !windows.isEmpty {
            UnifiedLogger.shared.info("Stopped collecting data.", className: String(describing: FraudDetection.self))
        }
    }

    @objc private func periodicAttachGesture() {
        stateLock.lock()
        guard isCaptureActive else {
            let staleTimer = timer
            timer = nil
            stateLock.unlock()
            staleTimer?.invalidate()
            return
        }
        stateLock.unlock()

        guard let window = UIWindow.topMostWindow() else {
            UnifiedLogger.shared.warning("No topMostWindow found right now.", className: String(describing: FraudDetection.self))
            scheduleAttachRetry()
            return
        }
        attachGestureIfNeeded(to: window)
        let retryTimer: Timer? = withStateLock {
            let t = timer
            timer = nil
            return t
        }
        retryTimer?.invalidate()
    }

    private func scheduleAttachRetry() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard timer == nil, isCaptureActive else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.periodicAttachGesture()
        }
    }

    func attachGestureIfNeeded(to window: UIWindow) {
        let alreadyAttached: Bool = withStateLock {
            if attachedWindows.contains(window) { return true }
            attachedWindows.add(window)
            return false
        }
        if alreadyAttached {
            UnifiedLogger.shared.debug("Already attached to window: \(window)", className: String(describing: FraudDetection.self))
            return
        }

        UnifiedLogger.shared.info("Attaching gesture recognizer to window: \(window)", className: String(describing: FraudDetection.self))

        // Remove stale recognizers from a prior SDK configuration without
        // touching recognizers owned by the host application.
        for recognizer in window.gestureRecognizers ?? [] where recognizer is TouchCaptureGestureRecognizer {
            window.removeGestureRecognizer(recognizer)
        }

        window.addGestureRecognizer(TouchCaptureGestureRecognizer(capturer: self))
    }

    private func removeGestureRecognizers(from windows: [UIWindow]) {
        guard !windows.isEmpty else { return }

        let remove = {
            for window in windows {
                for recognizer in window.gestureRecognizers ?? [] {
                    guard let touchRecognizer = recognizer as? TouchCaptureGestureRecognizer,
                          touchRecognizer.capturer === self else { continue }
                    window.removeGestureRecognizer(touchRecognizer)
                }
            }
        }

        // Never main.sync here: callers hold Verisoul.sessionLock, and a
        // main-thread caller contending that lock would deadlock against us.
        // Asynchronous removal is safe — isCaptureActive is already false, so
        // a recognizer that outlives this call by a beat records nothing.
        if Thread.isMainThread {
            remove()
        } else {
            DispatchQueue.main.async(execute: remove)
        }
    }

    private let motionManager = CMMotionManager()
    private let accelerometerBuffer = RingBuffer(capacity: 200)
    private let dataAccessQueue = DispatchQueue(label: "com.fraudDetection.dataAccessQueue")
    private let motionManagerQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.fraudDetection.motionManagerQueue"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private func setupMotionManager(updateInterval: TimeInterval) {
        guard motionManager.isAccelerometerAvailable else {
            withStateLock { isAccelerometerAvailable = false }
            UnifiedLogger.shared.error("Accelerometer not available on this device.", className: String(describing: FraudDetection.self))
            return
        }

        UnifiedLogger.shared.info("Setting up motion manager...", className: String(describing: FraudDetection.self))

        let item = DispatchWorkItem { [weak self] in
            UnifiedLogger.shared.info("Stopping manager", className: String(describing: FraudDetection.self))
            self?.stop()
        }

        stateLock.lock()
        // A stop() that ran after startGlobalCapture() set isCaptureActive wins: don't start
        // the accelerometer or the 5-minute timer for capture that is already over.
        guard isCaptureActive else {
            stateLock.unlock()
            return
        }
        workItem?.cancel()
        workItem = item
        motionManager.accelerometerUpdateInterval = updateInterval
        motionManager.startAccelerometerUpdates(to: motionManagerQueue) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            let timestamp = CACurrentMediaTime()

            self.dataAccessQueue.async {
                self.accelerometerBuffer.push(
                    timestamp: timestamp,
                    x: data.acceleration.x,
                    y: data.acceleration.y,
                    z: data.acceleration.z
                )
            }
        }
        stateLock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + 60 * 5, execute: item)
    }

    private func canSendSample() -> Bool {
        withStateLock { isCaptureActive && sendCount < 10 }
    }

    internal func handleTouchEnded(touch: CGPoint?, downTime: Date) {
        UnifiedLogger.shared.debug("Touch ended at point: \(touch)", className: String(describing: FraudDetection.self))
        guard canSendSample() else { return }

        let touchTime = CACurrentMediaTime()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.canSendSample() else { return }

            self.dataAccessQueue.async {
                let (accelerometerAvailable, sampleCount, sessionId, projectId) = self.withStateLock {
                    (self.isAccelerometerAvailable, self.sendCount, self.sessionId, self.projectId)
                }
                let startTime = touchTime - 1.0
                let endTime   = touchTime + 1.0

                let relevantData: [(timestamp: TimeInterval, x: Double, y: Double, z: Double)] =
                accelerometerAvailable
                    ? self.accelerometerBuffer.samples(inRange: startTime...endTime)
                    : [(timestamp: TimeInterval, x: Double, y: Double, z: Double)]()

                var tsArray = [Int]()
                var xArray  = [Double]()
                var yArray  = [Double]()
                var zArray  = [Double]()

                for sample in relevantData {
                    tsArray.append(sample.timestamp.millisecondsSince1970)
                    xArray.append(sample.x)
                    yArray.append(sample.y)
                    zArray.append(sample.z)
                }

                let accelData =   AccelerometerData(
                    timestamp: tsArray,
                    x: xArray,
                    y: yArray,
                    z: zArray
                )

                let now = Date()

                let touchData = TouchData(
                    x: touch?.x ?? 0,
                    y: touch?.y ?? 0,
                    upTimestamp: touch != nil ? now.millisecondsSince1970 : 0,
                    downTimestamp: touch != nil ? downTime.millisecondsSince1970 : 0
                )

                let sensorPayload = SensorPayload(
                    accelerometer: accelData,
                    sampleNumber: touch != nil ? sampleCount : -1,
                    touch: touchData,
                    sessionId: sessionId,
                    projectId: projectId
                )

                Task {
                    try await self.sendDataToEndpoint(sensorPayload)
                }
            }
        }
    }


    private func sendDataToEndpoint(_ payload: SensorPayload) async throws {
        let isActive = withStateLock { isCaptureActive }
        if payload.sampleNumber <= 10, isActive {
            UnifiedLogger.shared.info("Touch data send : \(payload.touch.x) , \(payload.touch.y)", className: String(describing: FraudDetection.self))


            do {
                let data = try JSONEncoder().encode(payload)

                // Convert JSON to [String: Any]
                guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    UnifiedLogger.shared.error("No data.", className: String(describing: FraudDetection.self))
                    return
                }

                try await self.networkManager.sendAccelometerData(payload: jsonObject)

                // Sends complete concurrently. Only the one that brings the count to exactly 10
                // stops capture; the rest only count.
                let reachedLimit: Bool = withStateLock {
                    sendCount += 1
                    return sendCount == 10
                }
                if reachedLimit {
                    UnifiedLogger.shared.info("Reached 10 sends. Stopping.", className: String(describing: FraudDetection.self))
                    stop()
                }

                UnifiedLogger.shared.info("Server responded with success status code.", className: String(describing: FraudDetection.self))
            } catch {
                UnifiedLogger.shared.error("Error sending data: \(error)", className: String(describing: FraudDetection.self))
                AppAttestError.sendRequest(error.localizedDescription)
            }
        }
    }




    private func flushPayloadQueue() {
        let queuedPayloads: [SensorPayload] = withStateLock {
            let payloads = payloadQueue
            payloadQueue.removeAll()
            return payloads
        }

        for payload in queuedPayloads {
            Task {
                try await self.sendDataToEndpoint(payload)
            }
        }
    }
}

extension UIWindow {
    static func topMostWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }

            return windows.first(where: { $0.isKeyWindow }) ?? windows.first
        } else {
            return UIApplication.shared.keyWindow
        }
    }
}

private class RingBuffer {
    private let capacity: Int
    private var buffer: [(timestamp: TimeInterval, x: Double, y: Double, z: Double)]
    private var head = 0
    private var count = 0

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: (0, 0, 0, 0), count: capacity)
    }

    func push(timestamp: TimeInterval, x: Double, y: Double, z: Double) {
        let index = (head + count) % capacity
        if count < capacity {
            buffer[index] = (timestamp, x, y, z)
            count += 1
        } else {
            buffer[head] = (timestamp, x, y, z)
            head = (head + 1) % capacity
        }
    }

    func samples(inRange range: ClosedRange<TimeInterval>) -> [(timestamp: TimeInterval, x: Double, y: Double, z: Double)] {
        var result = [(TimeInterval, Double, Double, Double)]()

        for i in 0..<count {
            let index = (head + i) % capacity
            let sample = buffer[index]
            if range.contains(sample.timestamp) {
                result.append(sample)
            }
        }

        return result
    }
}

