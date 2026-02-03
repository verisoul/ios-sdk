import os
import Foundation

enum LogLevel: String {
    case info
    case warning
    case debug
    case error

    var description: String {
        switch self {
        case .info: return "info"
        case .warning: return "warn"
        case .debug: return "info"
        case .error: return "error"
        }
    }
}

internal class UnifiedLogger {

    private let logger: Logger = Logger(subsystem: "verisoul.sdk", category: "main")
    private var eventLogger: WebSocketLogger?
    private var projectId: String?
    private var sessionId: String?
    private var timeoutHandler: Timer?
    private let logQueueMaxSize = 100
    private let logQueueTimeout: TimeInterval = 10
    private let logQueue = DispatchQueue(label: "com.verisoul.logqueue", attributes: .concurrent)
    private var _logs: [LogMessage] = []
    private var isSendingLogs = false
    private func appendLog(_ log: LogMessage) -> Int {
        var count = 0
        logQueue.sync(flags: .barrier) {
            _logs.append(log)
            count = _logs.count
        }
        return count
    }

    private func logsCount() -> Int {
        return logQueue.sync { _logs.count }
    }

    internal static let shared = UnifiedLogger()

    var isLoggingEnabled: Bool = {
#if DEBUG
        return true
#else
        return false
#endif
    }()

    func setEventLogger(eventLogger: WebSocketLogger) {
        do {
            self.eventLogger = eventLogger
            startQueueProcessor()
            self.eventLogger?.stopListening()
        } catch {
            logger.error("setEventLogger error: \(error.localizedDescription)")
        }
    }

    func initLoggerData(projectId: String, sessionId: String) {
        do {
            self.projectId = projectId
            self.sessionId = sessionId
        } catch {
            logger.error("initLoggerData error: \(error.localizedDescription)")
        }
    }

    internal func log(_ message: String, level: LogLevel, className: String) {
        do {
            
            let formattedMessage = "[\(className)] \(message)"
            if isLoggingEnabled {
                switch level {
                case .info: logger.info("\(formattedMessage)")
                case .warning: logger.warning("\(formattedMessage)")
                case .debug: logger.info("\(formattedMessage)")
                case .error: logger.error("\(formattedMessage)")
                }
            } else {
                let logCount = appendLog(LogMessage(message: formattedMessage, level: level.description))
                if logCount >= logQueueMaxSize {
                    triggerSendLog()
                    return
                }
                startQueueProcessor()
            }
        } catch {
            logger.error("log error: \(error.localizedDescription)")
        }
    }

    internal func info(_ message: String, className: String) {
        do {
            log(message, level: .info, className: className)
        } catch {
            logger.error("info log error: \(error.localizedDescription)")
        }
    }

    internal func warning(_ message: String, className: String) {
        do {
            log(message, level: .warning, className: className)
        } catch {
            logger.error("warning log error: \(error.localizedDescription)")
        }
    }

    internal func debug(_ message: String, className: String) {
        do {
            log(message, level: .debug, className: className)
        } catch {
            logger.error("debug log error: \(error.localizedDescription)")
        }
    }

    internal func error(_ message: String, className: String) {
        do {
            log(message, level: .error, className: className)
        } catch {
            logger.error("error log error: \(error.localizedDescription)")
        }
    }

    internal func metric(value: Double, name: String , className: String) {
        do {
            let formattedMessage = "[\(className)] \(name)"
            if isLoggingEnabled {
                logger.info("\(formattedMessage) \(value)")
            } else {
                let logCount = appendLog(LogMessage(value: value, name: formattedMessage))
                if logCount >= logQueueMaxSize {
                    triggerSendLog()
                    return
                }
                startQueueProcessor()
            }
        } catch {
            logger.error("metric error: \(error.localizedDescription)")
        }
    }

    private func startQueueProcessor() {
        do {
            if logsCount() >= logQueueMaxSize {
                triggerSendLog()
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.timeoutHandler?.invalidate()
                    self.timeoutHandler = Timer.scheduledTimer(
                        timeInterval: self.logQueueTimeout,
                        target: self,
                        selector: #selector(self.triggerSendLog),
                        userInfo: nil,
                        repeats: false
                    )
                }
            }
        } catch {
            logger.error("startQueueProcessor error: \(error.localizedDescription)")
        }
    }

    @objc private func triggerSendLog() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            do {
                guard let sessionId = self.sessionId,
                      let projectId = self.projectId else {
                    return
                }

                let currentLogs: [LogMessage]? = logQueue.sync(flags: .barrier) {
                    guard !self.isSendingLogs, !self._logs.isEmpty else { return nil }
                    self.isSendingLogs = true
                    let logs = self._logs
                    self._logs.removeAll()
                    return logs
                }
                guard let currentLogs = currentLogs else {
                    let shouldRetry = logQueue.sync { self.isSendingLogs || !self._logs.isEmpty }
                    if shouldRetry {
                        self.startQueueProcessor()
                    }
                    return
                }

                self.timeoutHandler?.invalidate()
                self.timeoutHandler = nil
                let logsToSend = currentLogs.map {
                    LogMessage(logMessage: $0, projectId: projectId, sessionId: sessionId)
                }

                Task {
                    do {
                        try await self.eventLogger?.sendLog(
                            log: LogData(
                                data: logsToSend,
                                session_id: sessionId,
                                project_id: projectId,
                                event_id: UUID().uuidString
                            )
                        )
                        self.logQueue.sync(flags: .barrier) {
                            self.isSendingLogs = false
                        }
                    } catch {
                        self.logQueue.sync(flags: .barrier) {
                            self._logs.insert(contentsOf: currentLogs, at: 0)
                            self.isSendingLogs = false
                        }
                        self.startQueueProcessor()
                        self.logger.error("sendLog task error: \(error.localizedDescription)")
                    }
                }
            } catch {
                self.logger.error("triggerSendLog error: \(error.localizedDescription)")
            }
        }
    }
}
