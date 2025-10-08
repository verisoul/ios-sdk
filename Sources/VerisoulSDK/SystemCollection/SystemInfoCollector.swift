import Metal
import UIKit
import Network
import Darwin
import CoreFoundation

class SystemInfoCollector {
    func collectAll() -> [String: Any] {
        var info: [String: Any] = [:]
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Collect Metal GPU information
        if let metalInfo = MetalInfoCollector.collect() {
            info["metal_gpu"] = metalInfo
        }
        
        // Collect UIDevice information
        info["device"] = DeviceInfoCollector.collect()
        
        info["sensor"] = SensorCollector.collect()
        
        // Collect Network information
        info["network"] = NetworkInfoCollector.collect()
        
        // Collect Process information
        info["process"] = ProcessInfoCollector.collect()

        // Collect Location information
        info["location"] = LocationInfoCollector.collect()

        
        let endTime = CFAbsoluteTimeGetCurrent()
        UnifiedLogger.shared.metric(value: (endTime - startTime),
                                    name: "system_info_collection_duration",
                                    className: String(describing: SystemInfoCollector.self))
        return info
    }
    
}
