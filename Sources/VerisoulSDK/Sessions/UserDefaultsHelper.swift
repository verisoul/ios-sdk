//
//  UserDefaultsHelper.swift
//  VerisoulSDK
//
//  Created by ahmed alaa on 15/02/2025.
//

import Foundation


class UserDefaultsHelper {
    private let userDefaults = UserDefaults.standard
    private let sessionKey = "KEY_SESSION"
    
    static let shared = UserDefaultsHelper()
    
    // Private initializer to prevent instantiating more than one instance
    private init() {
        
    }
    
    func saveSession(_ sessionData: SessionData) {
        userDefaults.set(sessionData.toJson(), forKey: sessionKey)
    }
    
    func getSession() -> SessionData? {
        guard let json = userDefaults.string(forKey: sessionKey) else { return nil }
        return SessionData.fromJson(json)
    }
    
    func clearSession() {
        userDefaults.removeObject(forKey: sessionKey)
    }
}
