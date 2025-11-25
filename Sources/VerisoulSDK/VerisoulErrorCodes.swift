import Foundation

/// Standard error codes used by the Verisoul SDK.
/// These codes provide consistent error handling across platforms.
@objc public class VerisoulErrorCodes: NSObject {
    
    /// WebView is not available on the device (missing, disabled, or corrupted)
    @objc public static let WEBVIEW_UNAVAILABLE = "WEBVIEW_UNAVAILABLE"
    
    /// Session is not available or could not be retrieved
    @objc public static let SESSION_UNAVAILABLE = "SESSION_UNAVAILABLE"
    
    /// Invalid environment parameter
    @objc public static let INVALID_ENVIRONMENT = "INVALID_ENVIRONMENT"
}
