import UIKit
import DeviceCheck
import MessageUI
import LocalAuthentication

class DeviceInfoCollector {
    static func collect() -> [String: Any] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let device = UIDevice.current
        let timezone = TimeZone.current
        let screen = UIScreen.main
        let languages = Locale.preferredLanguages
        let locale = Locale.current
        
        // Check if running on Simulator
#if targetEnvironment(simulator)
        let isSimulator = true
#else
        let isSimulator = false
#endif
        
        // Start battery monitoring
        device.isBatteryMonitoringEnabled = true
        
        var deviceInfo: [String: Any] = [
            "device_name": device.name,
            "system_name": device.systemName,
            "system_version": device.systemVersion,
            "model": device.model,
            "localized_model": device.localizedModel,
            "battery_level": device.batteryLevel,
            "battery_state": batteryStateString(device.batteryState),
            "is_battery_monitoring_enabled": device.isBatteryMonitoringEnabled,
            "is_multitasking_supported": device.isMultitaskingSupported,
            "is_proximity_monitoring_enabled": device.isProximityMonitoringEnabled,
            "proximity_state": device.proximityState,
            "device_orientation": orientationString(device.orientation),
            "time_zone": timezone.identifier,
            "time_zone_abbreviation": timezone.abbreviation() ?? "",
            "seconds_from_gmt": timezone.secondsFromGMT(),
            "is_daylight_savings": timezone.isDaylightSavingTime(),
            "screen_brightness": UIScreen.main.brightness,
            "accessibility_reduce_motion_enabled": UIAccessibility.isReduceMotionEnabled,
            "accessibility_bold_text_enabled": UIAccessibility.isBoldTextEnabled,
            "accessibility_assistive_touch_enabled": UIAccessibility.isAssistiveTouchRunning,
            "app_language": Bundle.main.preferredLocalizations.first ?? "",
            // Screen information (flattened)
            "screen_bounds_width": screen.bounds.width,
            "screen_bounds_height": screen.bounds.height,
            "screen_scale": screen.scale,
            "screen_native_bounds_width": screen.nativeBounds.width,
            "screen_native_bounds_height": screen.nativeBounds.height,
            "screen_native_scale": screen.nativeScale,
            "identifierForVendor": fetchIdentifierForVendor(),
            // Language and locale information
            "preferred_languages": languages,
            "current_locale_identifier": locale.identifier,
            
            // Calendar information
            "calendar_identifier": String(describing: Calendar.current.identifier),
            "can_send_mail": MFMailComposeViewController.canSendMail(),
            "can_send_text": MFMessageComposeViewController.canSendText(),
            // Simulator information
            "is_simulator": isSimulator,
            "is_debugger_attached": DebuggerChecker.amIDebugged(),
            "biometric_authentication_enabled": isBiometricEnabled(),
        ]
        
        // Handle locale properties for different iOS versions
        if #available(iOS 16, *) {
            deviceInfo["current_locale_language_code"] = locale.language.languageCode?.identifier ?? ""
            deviceInfo["current_locale_region_code"] = locale.region?.identifier ?? ""
            deviceInfo["current_locale_currency_code"] = locale.currency?.identifier ?? ""
            deviceInfo["current_locale_currency_symbol"] = locale.currencySymbol ?? ""
        } else {
            // Using deprecated APIs for older iOS versions
#if compiler(>=5.7)
            deviceInfo["current_locale_language_code"] = locale.languageCode ?? ""
            deviceInfo["current_locale_region_code"] = locale.regionCode ?? ""
            deviceInfo["current_locale_currency_code"] = locale.currencyCode ?? ""
            deviceInfo["current_locale_currency_symbol"] = locale.currencySymbol ?? ""
#endif
        }
        
        deviceInfo["current_locale_decimal_separator"] = locale.decimalSeparator ?? ""
        deviceInfo["current_locale_grouping_separator"] = locale.groupingSeparator ?? ""
        deviceInfo["device_check_enabled"] = DCDevice.current.isSupported
        deviceInfo["app_attest_enabled"] = DCAppAttestService.shared.isSupported
        // Stop battery monitoring
        device.isBatteryMonitoringEnabled = false
        let endTime = CFAbsoluteTimeGetCurrent()
        UnifiedLogger.shared.metric(value: (endTime - startTime),
                                    name: "device_info_duration",
                                    className: String(describing: DeviceInfoCollector.self))
        return deviceInfo
    }
    
    /// Checks if biometric authentication is enabled on the device.
    private static func isBiometricEnabled() -> Bool {
        let context = LAContext()
        var error: NSError?
        let isEnabled = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return isEnabled
    }
    
    
    // MARK: - Private Helper Methods
    
    /// Fetches the unique identifier for the device, storing it in the Keychain if necessary.
    /// Returns the identifier for vendor or a fallback string if unavailable.
    private static func fetchIdentifierForVendor() -> String {
        let keychainKey = "com.verisoul.sdk"
        
        UnifiedLogger.shared.debug("Fetching identifier for vendor...", className: String(describing: self))
        
        if let storedIdentifier = KeychainHelper.shared.get(key: keychainKey) {
            UnifiedLogger.shared.debug("Found stored identifier in Keychain.", className: String(describing: self))
            return storedIdentifier
        }
        
        if let identifier = UIDevice.current.identifierForVendor?.uuidString {
            KeychainHelper.shared.set(identifier, key: keychainKey)
            UnifiedLogger.shared.debug("Stored new identifier in Keychain: \(identifier)", className: String(describing: self))
            return identifier
        }
        
        UnifiedLogger.shared.warning("Identifier for vendor not available.", className: String(describing: self))
        return "Unavailable"
    }
    
    private static func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown:
            return "Unknown"
        case .unplugged:
            return "Unplugged"
        case .charging:
            return "Charging"
        case .full:
            return "Full"
        @unknown default:
            return "Unknown"
        }
    }
    
    private static func orientationString(_ orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .unknown:
            return "Unknown"
        case .portrait:
            return "Portrait"
        case .portraitUpsideDown:
            return "Portrait Upside Down"
        case .landscapeLeft:
            return "Landscape Left"
        case .landscapeRight:
            return "Landscape Right"
        case .faceUp:
            return "Face Up"
        case .faceDown:
            return "Face Down"
        @unknown default:
            return "Unknown"
        }
    }
}
