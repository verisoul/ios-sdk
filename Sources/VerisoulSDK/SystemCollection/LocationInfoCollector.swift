import Foundation
import CoreLocation


class LocationInfoCollector: NSObject, CLLocationManagerDelegate {
    private static let locationManager = CLLocationManager()
    
    static func collect() -> [String: Any] {
        let startTime = CFAbsoluteTimeGetCurrent()
        // Check if location services are enabled
        guard CLLocationManager.locationServicesEnabled() else {
            return [:]
        }
        
        // Retrieve current authorization status, handling iOS < 14 vs. iOS >= 14
        let authorizationStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authorizationStatus = locationManager.authorizationStatus
        } else {
            authorizationStatus = CLLocationManager.authorizationStatus()
        }
        
        // If not authorized, return empty dictionary
        guard authorizationStatus == .authorizedWhenInUse ||
                authorizationStatus == .authorizedAlways else {
            return ["location_status": "not_authorized"]
        }
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // If we have a recent location available, return its data
        if let location = locationManager.location {
            let endTime = CFAbsoluteTimeGetCurrent()
            UnifiedLogger.shared.metric(value: (endTime - startTime),
                                        name: "location_duration",
                                        className: String(describing: LocationInfoCollector.self))
            return formatLocationData(location)
        }
        
        // Otherwise, return an empty dictionary
        return [:]
    }
    
    private static func formatLocationData(_ location: CLLocation) -> [String: Any] {
        var data = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "horizontal_accuracy": location.horizontalAccuracy,
            "vertical_accuracy": location.verticalAccuracy,
            "speed": location.speed,
            "course": location.course,
            "timestamp": location.timestamp.timeIntervalSince1970
        ] as [String: Any]
        if #available(iOS 15.0, *) {
            guard let sourceInformation = location.sourceInformation else {
                return data
            }
            data["is_produced_by_accessory"] = sourceInformation.isProducedByAccessory
            data["is_simulated_by_software"] = sourceInformation.isSimulatedBySoftware
        }
        return data
    }
    

}
