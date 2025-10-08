import Foundation
import Security

// Protocol to define the interface for keychain operations
internal protocol KeychainHelperInterface {
    
    // Method to set a sessionData in the keychain.
    func saveSession(_ sessionData: SessionData)
    
    // Method to retrieve a SessionData from the keychain.
    func getSession() -> SessionData?
        

    // Method to remove a sessionData pair from the keychain.
    func clearSession()
}

// KeychainHelper class that implements the KeychainHelperInterface protocol
public class KeychainHelper: KeychainHelperInterface {
    
    private var sessionIdKey = "session_id_key"

    // Singleton instance of KeychainHelper
    static let shared = KeychainHelper()
    
    // Private initializer to prevent instantiating more than one instance
    private init() {}
    

    public func saveSession(_ sessionData: SessionData) {
        set(sessionData.toJson(), key: sessionIdKey)
    }
    
    public func getSession() -> SessionData? {
        guard let json = get(key: sessionIdKey) else { return nil }
        return SessionData.fromJson(json)
    }
    
    public func clearSession() {
        remove(key: sessionIdKey)
    }
    
    // MARK: - KeychainHelperInterface Method Implementations
    
    /// Sets a value in the keychain under the given key.
    /// - Parameters:
    ///   - value: The string value to store.
    ///   - key: The key under which the value will be stored.
    func set(_ value: String, key: String) {
        let data = Data(value.utf8)
        
        // Define the keychain query dictionary for saving the value
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete any existing item with the same key before adding the new value
        SecItemDelete(query as CFDictionary)
        
        // Add the new item to the keychain
        SecItemAdd(query as CFDictionary, nil)
    }
    
    /// Retrieves the value associated with the given key from the keychain.
    /// - Parameter key: The key for the item to retrieve.
    /// - Returns: The stored string value, or nil if not found.
    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Removes the value associated with the given key from the keychain.
    /// - Parameter key: The key for the item to remove.
    /// - Returns: true if the item was removed successfully, false otherwise.
    @discardableResult
     func remove(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        return status == errSecSuccess
    }
}
