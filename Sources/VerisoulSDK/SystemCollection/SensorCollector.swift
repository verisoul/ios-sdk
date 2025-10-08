import CoreMotion
import UIKit
import AVKit
class SensorCollector {
    
    // Function to check availability of sensors
    static func collect() -> [String: Bool] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let motionManager = CMMotionManager()
        let altimeter = CMAltimeter()
        var sensorAvailability = [String: Bool]()
        sensorAvailability["accelerometer"] = motionManager.isAccelerometerAvailable
        sensorAvailability["altimeter"] = CMAltimeter.isRelativeAltitudeAvailable()
        sensorAvailability["gyroscope"] = motionManager.isGyroAvailable
        let recordingSession = AVAudioSession.sharedInstance().availableModes
        sensorAvailability["magnetometer"] = motionManager.isMagnetometerAvailable
        
        sensorAvailability["barometer"] = motionManager.isDeviceMotionAvailable
        sensorAvailability["pedometer"] = CMPedometer.isPedometerEventTrackingAvailable()
        
        sensorAvailability["proximity_sensor"] = UIDevice.current.isProximityMonitoringEnabled
        
        sensorAvailability["device_motion"] = motionManager.isDeviceMotionAvailable
        let endTime = CFAbsoluteTimeGetCurrent()
        UnifiedLogger.shared.metric(value: (endTime - startTime),
                                    name: "process_duration",
                                    className: String(describing: ProcessInfoCollector.self))
        return sensorAvailability
    }
}
