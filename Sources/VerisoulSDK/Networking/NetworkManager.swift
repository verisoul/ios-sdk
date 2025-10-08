import Foundation

extension URLRequest {
    var curlString: String {
        guard let url = self.url else { return "" }
        var components = ["curl -v"]

        components.append("'\(url.absoluteString)'")

        if self.httpMethod != "GET" {
            components.append("-X \(self.httpMethod ?? "GET")")
        }

        if let headers = self.allHTTPHeaderFields {
            for (key, value) in headers {
                components.append("-H '\(key): \(value)'")
            }
        }

        if let body = self.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            components.append("-d '\(bodyString)'")
        }

        return components.joined(separator: " \\\n  ")
    }
}


// Protocol that defines the necessary methods for a network manager
internal protocol NetworkManagerProtocol {

    // Generic method to perform API requests with a response type that conforms to Decodable
    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod,
        parameters: [String: Any]?,
        headers: [String: String]?,
        retryNumber: Int,
        responseType: T.Type
    ) async throws -> T?

    // Generic method to perform API requests without expecting a response body (empty response)
    func requestEmpty(
        url: URL,
        method: HTTPMethod,
        parameters: [String: Any]?,
        headers: [String: String]?,
        retryNumber: Int
    ) async throws
}

// NetworkManager class that conforms to NetworkManagerProtocol
class NetworkManager: NetworkManagerProtocol {

    private let session: URLSession

    private let maxRetryNumber = 3

    private let decoder = JSONDecoder()

    init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    // Implementation of the request method for API calls with Decodable response
    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod = .GET,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        retryNumber: Int = 0,
        responseType: T.Type
    ) async throws -> T? {
        UnifiedLogger.shared.info("Requesting URL: \(url) with method: \(method.rawValue)", className: String(describing: NetworkManager.self))

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Add headers if provided
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // If there are parameters, encode them into the body for POST, PUT, etc.
        if let parameters = parameters {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [])
            } catch {
                if retryNumber >= maxRetryNumber - 1 {
                UnifiedLogger.shared.error("Error encoding parameters: \(error.localizedDescription)", className: String(describing: NetworkManager.self))
                } else {
                    return try await self.request(url: url,method: method,parameters: parameters,
                                                  headers: headers,retryNumber: retryNumber + 1,
                                                  responseType: responseType)
                }
            }
        }

        do {
            let (data, response) = try await session.data(for: request)

            // Ensure the response is valid (status code 200-299)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                UnifiedLogger.shared.error("Bad server response: \(url) \((response as? HTTPURLResponse)?.statusCode ?? -1)", className: String(describing: NetworkManager.self))
                return nil;
            }

            // Decode the response data into the expected model type

            let responseObject = try decoder.decode(T.self, from: data)
            UnifiedLogger.shared.info("Successfully received response: \(url) Status code: \(httpResponse.statusCode)", className: String(describing: NetworkManager.self))
            return responseObject
        } catch {
            if retryNumber >= maxRetryNumber - 1 {
            UnifiedLogger.shared.error("Error during request: \(error.localizedDescription)", className: String(describing: NetworkManager.self))
                return nil;
            } else {
                return try await self.request(url: url,method: method,parameters: parameters,
                                              headers: headers,retryNumber: retryNumber + 1,
                                              responseType: responseType)
            }
        }
    }

    // Implementation of the empty request method (requests with no body or response data)
    func requestEmpty(
        url: URL,
        method: HTTPMethod = .GET,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil,
        retryNumber: Int = 0
    ) async throws {
        UnifiedLogger.shared.info("Empty request to URL: \(url) with method: \(method.rawValue)", className: String(describing: NetworkManager.self))

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Add headers if provided
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // If there are parameters, encode them into the body for POST, PUT, etc.
        if let parameters = parameters {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [])
//                UnifiedLogger.shared.debug("Request parameters: \(parameters)")
            } catch {
                if retryNumber >= maxRetryNumber - 1 {
                UnifiedLogger.shared.error("Error encoding parameters: \(error.localizedDescription)", className: String(describing: NetworkManager.self))
                } else {
                    return try await self.requestEmpty(url: url,method: method,parameters: parameters,
                                                       headers: headers,retryNumber: retryNumber + 1)
                }
            }
        }


        // Perform the network request using URLSession with async/await
        do {
            let (_, response) = try await session.data(for: request)

            // Ensure the response is valid (status code 200-299)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                UnifiedLogger.shared.error("Bad server response: \(url) \((response as? HTTPURLResponse)?.statusCode ?? -1), \(response)", className: String(describing: NetworkManager.self))
                return;

            }
            UnifiedLogger.shared.info("Successfully received response: \(url) Status code: \(httpResponse.statusCode)", className: String(describing: NetworkManager.self))
        } catch {
            if retryNumber >= maxRetryNumber - 1 {
            UnifiedLogger.shared.error("Error during empty request: \(error.localizedDescription), \(request)", className: String(describing: NetworkManager.self))
                return;
            } else {
                return try await self.requestEmpty(url: url,method: method,parameters: parameters,
                                                   headers: headers,retryNumber: retryNumber + 1)
            }
        }
    }
}
