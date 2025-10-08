//
//  SessionHelper.swift
//  VerisoulSDK
//
//  Created by ahmed alaa on 14/02/2025.
//

import Foundation


class SessionHelper {
    private var lastSessionId: String?
    private let userDefaultHelper: UserDefaultsHelper

    static let shared = SessionHelper()

    // Private initializer to prevent instantiating more than one instance
    private init() {
        userDefaultHelper = UserDefaultsHelper.shared
    }



    private func initSession(projectId: String, env: VerisoulEnvironment) {

        lastSessionId = UUID().uuidString.lowercased()
        UnifiedLogger.shared.info("Creating new Session Data with ID: \(lastSessionId)", className: String(describing: SessionHelper.self))


        let sessionData = SessionData(
            sessionId: lastSessionId!,
            expirationTime: Date().timeIntervalSince1970 + SessionData.EXPIRATION_TIME,
            projectId: projectId,
            env: env,
            status: SessionStatus(deviceCheck: .waiting, nativeDataCollection: .waiting,touchDataCollection: .waiting)
        )
        userDefaultHelper.saveSession(sessionData)
    }

    func initSessionId(projectId: String, env: VerisoulEnvironment, reinitialize:Bool) -> String {
        if let sessionData = userDefaultHelper.getSession(),
           sessionData.sessionId != "",
           !sessionData.isExpired(),
           sessionData.projectId == projectId,
           sessionData.env == env, !reinitialize {
            lastSessionId = sessionData.sessionId
        } else {
            UnifiedLogger.shared.info("Session Data has been expired", className: String(describing: SessionHelper.self))
            userDefaultHelper.clearSession()
            initSession(projectId: projectId, env: env)
        }
        guard let lastSessionId = lastSessionId else {
            UnifiedLogger.shared.error("Failed to initialize session ID", className: String(describing: SessionHelper.self))
            return ""
        }
        return lastSessionId
    }



    func reinitializeSession(projectId: String, env: VerisoulEnvironment) {
        userDefaultHelper.clearSession()
        initSession(projectId: projectId, env: env)

    }

        func getSessionId() -> String? {
        return userDefaultHelper.getSession()?.sessionId
    }

    func getSession() -> SessionData? {
        return userDefaultHelper.getSession()
    }

    func setDeviceCheckIsDone() {
        guard var sessionData = userDefaultHelper.getSession() else { return }
        sessionData.status.deviceCheck = .done
        UnifiedLogger.shared.info("Device Check data has been collected", className: String(describing: SessionHelper.self))
        userDefaultHelper.saveSession(sessionData)
    }

    func setDeviceDataCollectionIsDone() {
        guard var sessionData = userDefaultHelper.getSession() else { return }
        sessionData.status.nativeDataCollection = .done
        UnifiedLogger.shared.info("Native Device data has been collected", className: String(describing: SessionHelper.self))
        userDefaultHelper.saveSession(sessionData)
    }

    func setTouchDataCollectionIsDone() {
        guard var sessionData = userDefaultHelper.getSession() else { return }
        sessionData.status.touchDataCollection = .done
        UnifiedLogger.shared.info("Touch Device data has been collected", className: String(describing: SessionHelper.self))
        userDefaultHelper.saveSession(sessionData)
    }

    func isNeedToSubmitDeviceData() -> Bool {
        guard let s = userDefaultHelper.getSession() else { return true }
        if s.isExpired() { return true }          // <- NEW: force recollect when stale
        return s.status.nativeDataCollection != .done
    }

    func isNeedToSubmitTouchData() -> Bool {
        guard let s = userDefaultHelper.getSession() else { return true }
        if s.isExpired() { return true }
        return s.status.touchDataCollection != .done
    }

    func isNeedToSubmitDeviceCheckData() -> Bool {
        guard let s = userDefaultHelper.getSession() else { return true }
        if s.isExpired() { return true }
        return s.status.deviceCheck != .done
    }
}
