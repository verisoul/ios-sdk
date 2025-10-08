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
    private var logs: [LogMessage] {
        get { logQueue.sync { _logs } }
        set { logQueue.async(flags: .barrier) { self._logs = newValue } }
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
                logs.append(LogMessage(message: formattedMessage, level: level.description))
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
                logs.append(LogMessage(value: value, name: formattedMessage))
                startQueueProcessor()
            }
        } catch {
            logger.error("metric error: \(error.localizedDescription)")
        }
    }

    private func startQueueProcessor() {
        do {
            if logs.count >= logQueueMaxSize {
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
                self.timeoutHandler?.invalidate()
                self.timeoutHandler = nil

                guard self.logs.count > 0,
                      let sessionId = self.sessionId,
                      let projectId = self.projectId else {
                    return
                }

                let logsToSend = self.logs.map {
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
                        self.logs.removeAll()
                    } catch {
                        self.logger.error("sendLog task error: \(error.localizedDescription)")
                    }
                }
            } catch {
                self.logger.error("triggerSendLog error: \(error.localizedDescription)")
            }
        }
    }
}
