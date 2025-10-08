//
//  Status.swift
//  VerisoulSDK
//
//  Created by ahmed alaa on 14/02/2025.
//

import Foundation


enum Status: String {
    case done = "Done"
    case waiting = "Waiting"
    
    static func fromString(_ value: String) -> Status {
        return Status(rawValue: value) ?? .waiting
    }
}

struct SessionStatus {
    var deviceCheck: Status
    var nativeDataCollection: Status
    var touchDataCollection: Status
}

public struct SessionData {
    let sessionId: String
    let expirationTime: TimeInterval
    let projectId: String
    let env: VerisoulEnvironment
    var status: SessionStatus
    
    static let EXPIRATION_TIME: TimeInterval = 24 * 60 * 60 // 24 hours in milliseconds
    
    init(sessionId: String, expirationTime: TimeInterval, projectId: String, env: VerisoulEnvironment, status: SessionStatus) {
        self.sessionId = sessionId
        self.expirationTime = expirationTime
        self.projectId = projectId
        self.env = env
        self.status = status
    }
    
    func toJson() -> String {
        let json: [String: Any] = [
            "sessionId": sessionId,
            "expiration": expirationTime,
            "projectId": projectId,
            "env": env.rawValue,
            "status": [
                "DeviceCheck": status.deviceCheck.rawValue,
                "NativeDataCollection": status.nativeDataCollection.rawValue,
                "TouchDataCollection": status.touchDataCollection.rawValue
            ]
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }
    
    static func fromJson(_ json: String) -> SessionData? {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let sessionId = jsonObject["sessionId"] as? String,
              let projectId = jsonObject["projectId"] as? String,
              let envValue = jsonObject["env"] as? String,
              let env = VerisoulEnvironment(rawValue: envValue),
              let expirationTime = jsonObject["expiration"] as? TimeInterval,
              let statusObject = jsonObject["status"] as? [String: String] else { return nil }
        
        let status = SessionStatus(
            deviceCheck: Status.fromString(statusObject["DeviceCheck"] ?? ""),
            nativeDataCollection: Status.fromString(statusObject["NativeDataCollection"] ?? ""),
            touchDataCollection: Status.fromString(statusObject["TouchDataCollection"] ?? "")
        )
        
        return SessionData(sessionId: sessionId, expirationTime: expirationTime, projectId: projectId, env: env, status: status)
    }
    
    func isExpired() -> Bool {
        return Date().timeIntervalSince1970 >= expirationTime
    }
}
