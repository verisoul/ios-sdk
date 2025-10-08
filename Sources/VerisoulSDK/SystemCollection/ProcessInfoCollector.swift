import Foundation
import Darwin

class ProcessInfoCollector {
    static func collect() -> [String: Any] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let processInfo = ProcessInfo.processInfo
        let memoryUsage = getDetailedMemoryUsage()
        
        let data = [
            "process_name": processInfo.processName,
            "process_id": processInfo.processIdentifier,
            "processor_count": processInfo.processorCount,
            "active_processor_count": processInfo.activeProcessorCount,
            "total_physical_memory": formatMemory(processInfo.physicalMemory),
            "app_memory_usage": memoryUsage.appMemoryUsage,
            "system_free_memory": memoryUsage.freeMemory,
            "system_used_memory": memoryUsage.usedMemory,
            "system_wired_memory": memoryUsage.wiredMemory,
            "system_compressed_memory": memoryUsage.compressedMemory,
            "thermal_state": getThermalStateString(processInfo.thermalState),
            "low_power_mode_enabled": processInfo.isLowPowerModeEnabled,
            "ios_version": processInfo.operatingSystemVersionString,
            "environment": processInfo.environment,
            "system_uptime": processInfo.systemUptime.milliseconds
        ] as [String : Any]
        let endTime = CFAbsoluteTimeGetCurrent()
        UnifiedLogger.shared.metric(value: (endTime - startTime),
                                    name: "process_duration",
                                    className: String(describing: ProcessInfoCollector.self))
        return data
    }
    
    private static func getDetailedMemoryUsage() -> (
        appMemoryUsage: Double,
        freeMemory: Double,
        usedMemory: Double,
        wiredMemory: Double,
        compressedMemory: Double
    ) {
        // Get app's memory usage
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0,
                          &count)
            }
        }
        
        let appMemoryUsage = kerr == KERN_SUCCESS
        ? formatMemory(UInt64(taskInfo.resident_size))
        : -888
        
        // Get system memory statistics
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let hostPort = mach_host_self()
        let hostResult = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(hostPort,
                                  HOST_VM_INFO64,
                                  $0,
                                  &vmCount)
            }
        }
        
        if hostResult == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            
            let free = UInt64(vmStats.free_count) * pageSize
            let active = UInt64(vmStats.active_count) * pageSize
            let inactive = UInt64(vmStats.inactive_count) * pageSize
            let wired = UInt64(vmStats.wire_count) * pageSize
            let compressed = UInt64(vmStats.compressor_page_count) * pageSize
            let used = active + inactive + wired + compressed
            
            return (
                appMemoryUsage: appMemoryUsage,
                freeMemory: formatMemory(free),
                usedMemory: formatMemory(used),
                wiredMemory: formatMemory(wired),
                compressedMemory: formatMemory(compressed)
            )
        }
        
        // If we fail to get data
        return (
            appMemoryUsage: appMemoryUsage,
            freeMemory: -888,
            usedMemory: -888,
            wiredMemory: -888,
            compressedMemory: -888
        )
    }
    
    private static func formatUptime(_ uptime: TimeInterval) -> String {
        let days = Int(uptime / 86400)
        let hours = Int((uptime.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(uptime.truncatingRemainder(dividingBy: 60))
        
        var components: [String] = []
        
        if days > 0 { components.append("\(days)d") }
        if hours > 0 { components.append("\(hours)h") }
        if minutes > 0 { components.append("\(minutes)m") }
        if seconds > 0 || components.isEmpty { components.append("\(seconds)s") }
        
        return components.joined(separator: " ")
    }
    
    private static func formatMemory(_ bytes: UInt64) -> Double {
        return  Double(bytes) / (1024 * 1024 * 1024)
    }
    
    private static func getThermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}
