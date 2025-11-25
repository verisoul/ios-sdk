import Foundation

/// Custom exception for Verisoul SDK errors
/// Provides standardized error codes for consistent error handling across platforms.
///
/// - Parameters:
///   - errorCode: The error code from `VerisoulErrorCodes`
///   - message: Human-readable error message
///   - cause: The underlying cause of the exception (optional)
public class VerisoulException: NSError {
    
    /// The string error code identifying the type of error
    public let errorCode: String
    
    /// The underlying cause of the exception, if any
    public let cause: Error?
    
    /// Initialize a new Verisoul exception
    /// - Parameters:
    ///   - code: The error code from `VerisoulErrorCodes`
    ///   - message: Human-readable error message
    ///   - cause: The underlying cause of the exception (optional)
    public init(code: String, message: String, cause: Error? = nil) {
        self.errorCode = code
        self.cause = cause
        
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let cause = cause {
            userInfo[NSUnderlyingErrorKey] = cause
        }
        
        super.init(domain: "ai.verisoul.sdk", code: 0, userInfo: userInfo)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var description: String {
        return "VerisoulException(errorCode='\(errorCode)', message='\(localizedDescription)')"
    }
}
