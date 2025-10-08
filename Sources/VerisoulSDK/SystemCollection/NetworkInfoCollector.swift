import Network
import CoreLocation
import CoreFoundation
import Foundation
import Darwin
import CFNetwork
import SystemConfiguration.CaptiveNetwork


struct Interface {
    let name: String
    let address: String?
    let netmask: String?
    let broadcastAddress: String?
    let family: Family?
    
    enum Family: Int32 {
        case ipv4 = 2
        case ipv6 = 30
    }
    
    static func allInterfaces() throws -> [Interface] {
        var interfaces: [Interface] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            UnifiedLogger.shared.error("InterfaceErrorDomain", className: String(describing: NetworkInfoCollector.self))
            return [];
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let ifa = ptr?.pointee else { continue }
            
            let name = String(cString: ifa.ifa_name)
            let saFamily = ifa.ifa_addr.pointee.sa_family
            
            // Only process IPv4 or IPv6
            guard saFamily == UInt8(AF_INET) || saFamily == UInt8(AF_INET6) else { continue }
            
            let family: Family? = saFamily == UInt8(AF_INET) ? .ipv4 : .ipv6
            let address = Interface.getAddressString(ifa.ifa_addr)
            let netmask = Interface.getAddressString(ifa.ifa_netmask)
            let broadcast = Interface.getAddressString(ifa.ifa_dstaddr)
            
            interfaces.append(Interface(
                name: name,
                address: address,
                netmask: netmask,
                broadcastAddress: broadcast,
                family: family
            ))
        }
        
        return interfaces
    }
    
    private static func getAddressString(_ addr: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let addr = addr else { return nil }
        
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(
            addr, socklen_t(addr.pointee.sa_len),
            &hostBuffer, socklen_t(hostBuffer.count),
            nil, 0,
            NI_NUMERICHOST
        ) == 0 {
            return String(cString: hostBuffer)
        }
        
        return nil
    }
}

class NetworkInfoCollector {
    
    static func collect() -> [String: Any] {
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            var networkInfo: [String: Any] = [:]
            let monitor = NWPathMonitor()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.verisoul.network.monitor")
            var didLeaveGroup = false
            
            group.enter()
            
            // Capture proxy settings (no special entitlements required)
            if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
                
                // HTTP Proxy
                networkInfo["http_proxy_enabled"] = proxySettings[kCFNetworkProxiesHTTPEnable as String] as? Bool ?? false
                if let httpProxy = proxySettings[kCFNetworkProxiesHTTPProxy as String] as? String {
                    networkInfo["http_proxy_host"] = httpProxy
                    networkInfo["http_proxy_port"] = proxySettings[kCFNetworkProxiesHTTPPort as String] as? Int ?? 0
                }
                
                
                // Auto-configuration (PAC)
                networkInfo["auto_config_enabled"] = proxySettings[kCFNetworkProxiesProxyAutoConfigEnable as String] as? Bool ?? false
                if let pacURL = proxySettings[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String {
                    networkInfo["auto_config_url"] = pacURL
                }
                networkInfo["scoped"] = proxySettings["__SCOPED__"]
            }
            
            // Collect interface details
            let interfaces = try Interface.allInterfaces()
            let interfaceDetails = interfaces.map { interface -> [String: Any] in
                [
                    "name": interface.name,
                    "family": interface.family.map { "\($0)" } ?? "Unknown",
                    "address": interface.address ?? "Unknown",
                    "netmask": interface.netmask ?? "Unknown",
                    "broadcast_address": interface.broadcastAddress ?? "N/A"
                ]
            }
            networkInfo["interface_details"] = interfaceDetails
            
            // NWPathMonitor for live status
            monitor.pathUpdateHandler = { path in
                networkInfo["network_status"] = connectionStatusString(path.status)
                if #available(iOS 14.2, *) {
                    networkInfo["unsatisfied_reason"] = String(describing: path.unsatisfiedReason)
                }
                networkInfo["is_expensive"] = path.isExpensive
                networkInfo["is_constrained"] = path.isConstrained
                networkInfo["interface_types"] = getInterfaceTypes(path).joined(separator: ", ")
                networkInfo["available_interfaces"] = path.availableInterfaces.map { $0.debugDescription }.joined(separator: ", ")
                networkInfo["gateways"] = path.gateways.map { $0.debugDescription }.joined(separator: ", ")
                networkInfo["supports_ipv4"] = path.supportsIPv4
                networkInfo["supports_ipv6"] = path.supportsIPv6
                networkInfo["supports_dns"] = path.supportsDNS
                networkInfo["local_endpoint"] = path.localEndpoint?.debugDescription ?? "None"
                networkInfo["remote_endpoint"] = path.remoteEndpoint?.debugDescription ?? "None"
                networkInfo["debug_description"] = path.debugDescription
                
                monitor.cancel()
                if !didLeaveGroup {
                    didLeaveGroup = true
                    group.leave()
                }
            }
            
            monitor.start(queue: queue)
            
            let result = group.wait(timeout: .now() + 1.0)
            if result == .timedOut {
                monitor.cancel()
                if !didLeaveGroup {
                    didLeaveGroup = true
                    group.leave()
                }
            }
            
            let currentWifissid = getWiFiInfo()
            
            if(currentWifissid != nil){
                networkInfo["current_wifi_radio"] = currentWifissid
            }
            let endTime = CFAbsoluteTimeGetCurrent()
            UnifiedLogger.shared.metric(value: (endTime - startTime),
                                        name: "network_duration",
                                        className: String(describing: NetworkInfoCollector.self))
            return networkInfo
        } catch {
            UnifiedLogger.shared.error("NetworkInfoCollectionFailed: \(error)",
                                       className: String(describing: NetworkInfoCollector.self))
            return [:]
        }
    }
    
    
    private static func connectionStatusString(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied:
            return "Connected"
        case .unsatisfied:
            return "Not Connected"
        case .requiresConnection:
            return "Requires Connection"
        @unknown default:
            return "Unknown"
        }
    }
    
    private static func getInterfaceTypes(_ path: NWPath) -> [String] {
        var interfaces: [String] = []
        
        if path.usesInterfaceType(.wifi) {
            interfaces.append("WiFi")
        }
        if path.usesInterfaceType(.cellular) {
            interfaces.append("Cellular")
        }
        if path.usesInterfaceType(.wiredEthernet) {
            interfaces.append("Ethernet")
        }
        if path.usesInterfaceType(.loopback) {
            interfaces.append("Loopback")
        }
        if path.usesInterfaceType(.other) {
            interfaces.append("Other")
        }
        
        return interfaces.isEmpty ? ["None"] : interfaces
    }
    
    private static func getWiFiInfo() -> [String: String?]? {
        do {
            let status = CLLocationManager.authorizationStatus()
                guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                    return nil

                }
            guard let interfaces = CNCopySupportedInterfaces() as? [String] else {
                return nil
            }
            
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject] {
                    let ssid = info[kCNNetworkInfoKeySSID as String] as? String
                    let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String
                    return ["ssid": ssid, "bssid": bssid]
                }
            }
            
            return nil
        } catch {
            UnifiedLogger.shared.error("getWiFiInfo failed: \(error)",
                                       className: String(describing: NetworkInfoCollector.self))
            return nil
        }
    }
}
