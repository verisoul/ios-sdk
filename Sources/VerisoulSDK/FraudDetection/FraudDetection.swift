import UIKit
import CoreMotion

enum AccelerometerState: String {
    case collecting, stopped
}

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


public class FraudDetection: NSObject {

    private var attachedWindows = NSHashTable<UIWindow>(options: .weakMemory)
    private var timer: Timer?
    private var sendCount = 0
    private var projectId: String?
    private var sessionId: String?
    private var networkManager: VerisoulNetworkingClientInterface
    private var state = AccelerometerState.stopped
    private var payloadQueue: [SensorPayload] = []
    private let accelerometerUpdateInterval: TimeInterval = 1.0 / 50.0

    private var isAccelerometerAvailable = true
    init(networkManager: VerisoulNetworkingClientInterface, projectId: String?) {
        self.networkManager = networkManager
        self.projectId = projectId
    }

    func reset() {
        sendCount = 0
    }

    public func setSessionId(sessionId: String) {
        self.sessionId = sessionId
        self.flushPayloadQueue()
    }

    public func startGlobalCapture() {
        guard SessionHelper.shared.isNeedToSubmitTouchData() else { return }
        isAccelerometerAvailable = true
        setupMotionManager(updateInterval: accelerometerUpdateInterval)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            self.handleTouchEnded(touch: nil,downTime: Date())
        }
        DispatchQueue.main.async {
            self.periodicAttachGesture()
        }
    }

    public func stop() {
        motionManager.stopAccelerometerUpdates()
        state = .stopped
        isAccelerometerAvailable = true
        if(workItem?.isCancelled == false){
            workItem?.cancel()
        }
        timer?.invalidate()
        timer = nil
        SessionHelper.shared.setTouchDataCollectionIsDone()
        UnifiedLogger.shared.info("Stopped collecting data.", className: String(describing: FraudDetection.self))
    }

    @objc private func periodicAttachGesture() {
        guard let window = UIWindow.topMostWindow() else {
            UnifiedLogger.shared.warning("No topMostWindow found right now.", className: String(describing: FraudDetection.self))
            return
        }
        attachGestureIfNeeded(to: window)
    }

    private func attachGestureIfNeeded(to window: UIWindow) {
        if attachedWindows.contains(window) {
            UnifiedLogger.shared.debug("Already attached to window: \(window)", className: String(describing: FraudDetection.self))
            return
        }

        UnifiedLogger.shared.info("Attaching gesture recognizer to window: \(window)", className: String(describing: FraudDetection.self))

        if let viewWithTag = window.viewWithTag(100) {
            viewWithTag.removeFromSuperview()
        }

        let glassView = PassthroughWindow(frame: window.bounds)
        glassView.tag = 100
        glassView.capturer = self
        window.addSubview(glassView)
        attachedWindows.add(window)
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


    // Store this if you may need to cancel it later
    var workItem:DispatchWorkItem?

    private func setupMotionManager(updateInterval: TimeInterval) {
        guard motionManager.isAccelerometerAvailable else {
            self.isAccelerometerAvailable = false
            UnifiedLogger.shared.error("Accelerometer not available on this device.", className: String(describing: FraudDetection.self))
            return
        }

        UnifiedLogger.shared.info("Setting up motion manager...", className: String(describing: FraudDetection.self))
        motionManager.accelerometerUpdateInterval = updateInterval

        workItem = DispatchWorkItem {
            UnifiedLogger.shared.info("Stopping manager", className: String(describing: FraudDetection.self))
            self.stop()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 60 * 5,execute: workItem!)

        motionManager.startAccelerometerUpdates(to: motionManagerQueue) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            let timestamp = CACurrentMediaTime()
            self.state = .collecting

            self.dataAccessQueue.async {
                self.accelerometerBuffer.push(
                    timestamp: timestamp,
                    x: data.acceleration.x,
                    y: data.acceleration.y,
                    z: data.acceleration.z
                )
            }
        }
    }

    internal func handleTouchEnded(touch: CGPoint?, downTime: Date) {
        UnifiedLogger.shared.debug("Touch ended at point: \(touch)", className: String(describing: FraudDetection.self))
        if (state == .stopped && isAccelerometerAvailable) || sendCount > 10   { return }

        let touchTime = CACurrentMediaTime()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            self.dataAccessQueue.async {
                let startTime = touchTime - 1.0
                let endTime   = touchTime + 1.0

                let relevantData: [(timestamp: TimeInterval, x: Double, y: Double, z: Double)] =
                self.isAccelerometerAvailable
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
                    sampleNumber: touch != nil ? self.sendCount: -1,
                    touch: touchData,
                    sessionId: self.sessionId,
                    projectId: self.projectId
                )

                Task {
                    try await self.sendDataToEndpoint(sensorPayload)
                }
            }
        }
    }


    private func sendDataToEndpoint(_ payload: SensorPayload) async throws {
        if(payload.sampleNumber<=10){
            UnifiedLogger.shared.info("Touch data send : \(payload.touch.x) , \(payload.touch.y)", className: String(describing: FraudDetection.self))


            do {
                let data = try JSONEncoder().encode(payload)

                // Convert JSON to [String: Any]
                guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    UnifiedLogger.shared.error("No data.", className: String(describing: FraudDetection.self))
                    return
                }

                try await self.networkManager.sendAccelometerData(payload: jsonObject)

                sendCount += 1
                if sendCount >= 10 {
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
        let queuedPayloads = self.payloadQueue
        self.payloadQueue.removeAll()

        for payload in queuedPayloads {
            Task {
                var copy = payload
                try await self.sendDataToEndpoint(copy)
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

