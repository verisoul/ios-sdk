import UIKit
import DeviceCheck
import MessageUI
import LocalAuthentication

class DeviceInfoCollector {
    #if DEBUG
    static var _testOverrideData: [String: Any]?
    #endif

    static func collect() -> [String: Any] {
        #if DEBUG
        if let override = _testOverrideData { return override }
        #endif
        let startTime = CFAbsoluteTimeGetCurrent()
        let timezone = TimeZone.current
        let languages = Locale.preferredLanguages
        let locale = Locale.current
        
#if targetEnvironment(simulator)
        let isSimulator = true
#else
        let isSimulator = false
#endif

        let uiKitProps = readUIKitPropertiesOnMainThread()
        
        var deviceInfo: [String: Any] = [
            "device_name": uiKitProps.deviceName,
            "system_name": uiKitProps.systemName,
            "system_version": uiKitProps.systemVersion,
            "model": uiKitProps.model,
            "localized_model": uiKitProps.localizedModel,
            "battery_level": uiKitProps.batteryLevel,
            "battery_state": batteryStateString(uiKitProps.batteryState),
            "is_battery_monitoring_enabled": uiKitProps.isBatteryMonitoringEnabled,
            "is_multitasking_supported": uiKitProps.isMultitaskingSupported,
            "is_proximity_monitoring_enabled": uiKitProps.isProximityMonitoringEnabled,
            "proximity_state": uiKitProps.proximityState,
            "device_orientation": orientationString(uiKitProps.deviceOrientation),
            "time_zone": timezone.identifier,
            "time_zone_abbreviation": timezone.abbreviation() ?? "",
            "seconds_from_gmt": timezone.secondsFromGMT(),
            "is_daylight_savings": timezone.isDaylightSavingTime(),
            "screen_brightness": uiKitProps.screenBrightness,
            "accessibility_reduce_motion_enabled": uiKitProps.reduceMotionEnabled,
            "accessibility_bold_text_enabled": uiKitProps.boldTextEnabled,
            "accessibility_assistive_touch_enabled": uiKitProps.assistiveTouchRunning,
            "app_language": Bundle.main.preferredLocalizations.first ?? "",
            "screen_bounds_width": uiKitProps.screenBoundsWidth,
            "screen_bounds_height": uiKitProps.screenBoundsHeight,
            "screen_scale": uiKitProps.screenScale,
            "screen_native_bounds_width": uiKitProps.screenNativeBoundsWidth,
            "screen_native_bounds_height": uiKitProps.screenNativeBoundsHeight,
            "screen_native_scale": uiKitProps.screenNativeScale,
            "identifierForVendor": fetchIdentifierForVendor(),
            "preferred_languages": languages,
            "current_locale_identifier": locale.identifier,
            "calendar_identifier": String(describing: Calendar.current.identifier),
            "can_send_mail": MFMailComposeViewController.canSendMail(),
            "can_send_text": MFMessageComposeViewController.canSendText(),
            "is_simulator": isSimulator,
            "is_debugger_attached": DebuggerChecker.amIDebugged(),
            "biometric_authentication_enabled": isBiometricEnabled(),
        ]
        
        if #available(iOS 16, *) {
            deviceInfo["current_locale_language_code"] = locale.language.languageCode?.identifier ?? ""
            deviceInfo["current_locale_region_code"] = locale.region?.identifier ?? ""
            deviceInfo["current_locale_currency_code"] = locale.currency?.identifier ?? ""
            deviceInfo["current_locale_currency_symbol"] = locale.currencySymbol ?? ""
        } else {
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

        let endTime = CFAbsoluteTimeGetCurrent()
        UnifiedLogger.shared.metric(value: (endTime - startTime),
                                    name: "device_info_duration",
                                    className: String(describing: DeviceInfoCollector.self))
        return deviceInfo
    }

    // MARK: - UIKit Main-Thread Access

    private struct UIKitProperties {
        let deviceName: String
        let systemName: String
        let systemVersion: String
        let model: String
        let localizedModel: String
        let batteryLevel: Float
        let batteryState: UIDevice.BatteryState
        let isBatteryMonitoringEnabled: Bool
        let isMultitaskingSupported: Bool
        let isProximityMonitoringEnabled: Bool
        let proximityState: Bool
        let deviceOrientation: UIDeviceOrientation
        let screenBrightness: CGFloat
        let screenBoundsWidth: CGFloat
        let screenBoundsHeight: CGFloat
        let screenScale: CGFloat
        let screenNativeBoundsWidth: CGFloat
        let screenNativeBoundsHeight: CGFloat
        let screenNativeScale: CGFloat
        let reduceMotionEnabled: Bool
        let boldTextEnabled: Bool
        let assistiveTouchRunning: Bool
    }

    /// Reads all UIKit/UIDevice/UIScreen properties on the main thread.
    /// UIKit is not thread-safe; reading these from a background thread can
    /// return NaN/Infinity for float properties, which crashes NSJSONSerialization.
    private static func readUIKitPropertiesOnMainThread() -> UIKitProperties {
        let read = {
            let device = UIDevice.current
            let screen = UIScreen.main
            device.isBatteryMonitoringEnabled = true
            let props = UIKitProperties(
                deviceName: device.name,
                systemName: device.systemName,
                systemVersion: device.systemVersion,
                model: device.model,
                localizedModel: device.localizedModel,
                batteryLevel: device.batteryLevel,
                batteryState: device.batteryState,
                isBatteryMonitoringEnabled: device.isBatteryMonitoringEnabled,
                isMultitaskingSupported: device.isMultitaskingSupported,
                isProximityMonitoringEnabled: device.isProximityMonitoringEnabled,
                proximityState: device.proximityState,
                deviceOrientation: device.orientation,
                screenBrightness: screen.brightness,
                screenBoundsWidth: screen.bounds.width,
                screenBoundsHeight: screen.bounds.height,
                screenScale: screen.scale,
                screenNativeBoundsWidth: screen.nativeBounds.width,
                screenNativeBoundsHeight: screen.nativeBounds.height,
                screenNativeScale: screen.nativeScale,
                reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled,
                boldTextEnabled: UIAccessibility.isBoldTextEnabled,
                assistiveTouchRunning: UIAccessibility.isAssistiveTouchRunning
            )
            device.isBatteryMonitoringEnabled = false
            return props
        }

        if Thread.isMainThread {
            return read()
        }
        return DispatchQueue.main.sync { read() }
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
