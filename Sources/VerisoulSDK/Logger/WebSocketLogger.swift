import Foundation

class WebSocketLogger {
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private let url: URL

    init(env: VerisoulEnvironment) {
        self.urlSession = URLSession(configuration: .default)
        self.url = URL(string: "wss://ingest.\(env).verisoul.ai/ws")!
        self.webSocketTask = urlSession.webSocketTask(with: self.url)
        self.webSocketTask?.resume()
    }

    internal func stopListening() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 60 * 5) { [weak self] in
            self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
        }
    }

    deinit {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    func sendLog(log: LogData) async throws {
        do {
            let base = LogPayload(type: "Log", data: log)
            let logData = try JSONSerialization.data(withJSONObject: base.dictionary, options: [])
            let message = URLSessionWebSocketTask.Message.data(logData)

            guard let task = webSocketTask else {
                        UnifiedLogger.shared.error("WebSocket is not initialized", className: String(describing: WebSocketLogger.self))
  return
            }

            try await task.send(message)

            task.receive { result in
                // Handle response or ignore
                switch result {
                case .success: break
                case .failure(let error):
                    UnifiedLogger.shared.error("WebSocket receive error: \(error.localizedDescription)", className: String(describing: WebSocketLogger.self))
                }
            }
        } catch {
            UnifiedLogger.shared.error("Error sending log: \(error.localizedDescription)", className: String(describing: WebSocketLogger.self))
        }
    }
}
