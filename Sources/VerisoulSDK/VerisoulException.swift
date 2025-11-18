import Foundation

/// Custom exception for Verisoul SDK errors
// Provides standardized error codes for consistent error handling
//
// @param code - The error code [VerisoulErrorCodes]
// @param message - Human readable error message
// @param cause - The underlying cause of the exception

public class VerisoulException: NSError {
    
    public let code: String
    
    public let cause: Error?
    
    public init(code: String, message: String, cause: Error? = nil) {
        self.code = code
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
        return "VerisoulException(code='\(code)', message='\(localizedDescription)')"
    }
}
