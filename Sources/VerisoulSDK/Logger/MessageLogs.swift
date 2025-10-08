//
//  MessageLog.swift
//  VerisoulSDK
//
//  Created by Ivan Divljak on 27.1.25..
//
import Foundation
import UIKit
struct LogMessage: Codable {
    let level: String
    let message: String
    var session_id: String
    var project_id: String
    let timestamp: Int64
    let value: Double?
    let type: String?
    let attributes: [String: String]?
    let name: String?
    let platform: String?
    let version: String?
}

extension LogMessage {
    init(logMessage: LogMessage, projectId: String, sessionId: String) {
        self.project_id = projectId
        self.session_id = sessionId
        self.message = logMessage.message
        self.level = logMessage.level
        self.timestamp = logMessage.timestamp
        self.value = logMessage.value
        self.type = logMessage.type
        self.attributes = logMessage.attributes
        self.name = logMessage.name
        self.platform = logMessage.platform
        self.version = logMessage.version
    }
    
    init(message: String, level: String) {
        self.project_id = ""
        self.session_id = ""
        self.message = message
        self.level = level
        self.timestamp = Date().millisecondsSince1970
        self.value = nil
        self.type = nil
        self.attributes = nil
        self.name = nil
        self.platform = "iOS"
        self.version = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
    
    init(value: Double, name: String) {
        self.project_id = ""
        self.session_id = ""
        self.message = "log_forward_metric"
        self.level = "metric"
        self.timestamp = Date().millisecondsSince1970
        self.value = value
        self.type = "gauge"
        self.name = name
        self.attributes = ["platform": "iOS",
                           "version": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"]
        self.platform = nil
        self.version = nil
    }
}

struct LogData: Codable {
    let data: [LogMessage]
    let session_id: String
    let project_id: String
    let event_id: String
    let time: Int64 = Date().millisecondsSince1970
}

struct LogPayload: Codable {
    let type: String
    let data: LogData
}
