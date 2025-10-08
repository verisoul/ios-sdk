import Foundation

// Protocol to define the interface for VerisoulNetworkingClient
public protocol VerisoulNetworkingClientInterface {

    // Method to post device data to the Verisoul server
    func postDeviceData(sessionId: String, data: [String: Any], deviceCheck: String, projectId: String) async throws -> Bool?

    // Method to fetch a challenge from the Verisoul server
    func getChallenge() async throws -> String?

    // Method to verify the attestation with the given data, challenge, and keyId
    func verifyAttestation(_ data: Data, challenge: String, keyId: String) async throws -> String?

    func verifyAssertion(sessionId: String, data: [String: Any], projectId: String) async throws -> String?

    func sendAccelometerData(payload: [String: Any]) async throws
}

// VerisoulNetworkingClient class implementing the VerisoulNetworkingClientInterface protocol
public class VerisoulNetworkingClient: VerisoulNetworkingClientInterface {

    private let networkManager = NetworkManager()
    private let env: VerisoulEnvironment
    private let projectId: String

    // MARK: - Initialization

    init(env: VerisoulEnvironment, projectId: String) {
        self.env = env
        self.projectId = projectId
    }

    // MARK: - Networking Methods

    /// Posts device data to the Verisoul server
    /// - Parameters:
    ///   - sessionId: The session ID for the device.
    ///   - data: A dictionary of device data to be sent.
    ///   - attestation: A dictionary of attestation data to be sent.
    ///   - deviceCheck: A base64 encoded string representing the device check token.
    /// - Returns: The status of the request.
    public func postDeviceData(sessionId: String, data: [String: Any], deviceCheck: String, projectId: String) async throws -> Bool? {
        UnifiedLogger.shared.info("Posting device data to Verisoul server",
                                  className: String(describing: VerisoulNetworkingClient.self))

        let parameters: [String: Any] = [
            "session_id": sessionId,
            "data": data,
            "device_check": deviceCheck,
            "project_id": projectId
        ]


        guard let url = URL(string: "https://ingest.\(env.rawValue).verisoul.ai/ios") else {
//        guard let url = URL(string: "http://192.168.86.49:3002/ios") else {
            UnifiedLogger.shared.error("Invalid URL for device data POST: ingest.\(env.rawValue).verisoul.ai/ios", className: String(describing: VerisoulNetworkingClient.self))
            return nil
        }

        do {
            let result = try await networkManager.request(
                url: url,
                method: .POST,
                parameters: parameters,
                headers: ["content-type": "application/json"],
                responseType: VerisoulRESPONSE.self
            )
            UnifiedLogger.shared.info("Device data posted successfully. Status: \(result?.status)", className: String(describing: VerisoulNetworkingClient.self))
            return result?.status.lowercased() == "ok"
        } catch {
            UnifiedLogger.shared.error("Error posting device data: \(error.localizedDescription)", className: String(describing: VerisoulNetworkingClient.self))
            return nil

        }
    }

    /// Fetches a challenge from the Verisoul server
    /// - Returns: The challenge string from the server.
    public func getChallenge() async throws -> String? {
        guard let url = URL(string: "https://ingest.\(env.rawValue).verisoul.ai/worker/challenge/\(projectId)") else {
            UnifiedLogger.shared.error("Invalid URL for challenge GET: ingest.\(env.rawValue).verisoul.ai/worker/challenge/\(projectId)", className: String(describing: VerisoulNetworkingClient.self))
            return nil

        }

        do {
            let result = try await networkManager.request(
                url: url,
                method: .GET,
                responseType: AttestChallengeRESPONSE.self
            )
            UnifiedLogger.shared.info("Challenge fetched successfully. Challenge: \(result?.challenge)", className: String(describing: VerisoulNetworkingClient.self))
            return result?.challenge
        } catch {
            UnifiedLogger.shared.error("Error fetching challenge: \(error.localizedDescription)", className: String(describing: VerisoulNetworkingClient.self))
            return nil

        }
    }

    public func sendAccelometerData(payload: [String: Any]) async throws {

        guard let url = URL(string: "https://ingest.\(env).verisoul.ai/accelerometer") else {
//        guard let url = URL(string: "http://192.168.86.49:3002/accelerometer") else {
            UnifiedLogger.shared.error("Invalid URL for challenge POST: ingest.\(env).verisoul.ai/accelerometer", className: String(describing: VerisoulNetworkingClient.self))
            return
        }
        guard let sessionId = SessionHelper.shared.getSessionId() else {
            UnifiedLogger.shared.error("Session id missing", className: String(describing: VerisoulNetworkingClient.self))
            return

        }
        do {
            let result = try await networkManager.requestEmpty(
                url: url,
                method: .POST,
                parameters: payload,
                headers: ["content-type": "application/json"]
            )
            return
        } catch {
            UnifiedLogger.shared.error("Error send accelometer data: \(error.localizedDescription)", className: String(describing: VerisoulNetworkingClient.self))
            return

        }
    }

    public func verifyAssertion(sessionId: String, data: [String: Any], projectId: String) async throws -> String? {

        let parameters: [String: Any] = [
            "session_id": sessionId,
            "data": data,
            "project_id": projectId
        ]

        guard let url = URL(string: "https://ingest.\(env.rawValue).verisoul.ai/assertion") else {
//        guard let url = URL(string: "http://192.168.86.49:3002/attestation") else {
            UnifiedLogger.shared.error("Invalid URL for assertion verification POST: ingest.\(env.rawValue).verisoul.ai/worker/assertion", className: String(describing: VerisoulNetworkingClient.self))
            return nil

        }

        do {
            let result = try await networkManager.request(
                url: url,
                method: .POST,
                parameters: parameters,
                headers: ["content-type": "application/json"],
                responseType: VerisoulRESPONSE.self
            )
            UnifiedLogger.shared.info("Assertion verified successfully. Status: \(result?.status)", className: String(describing: VerisoulNetworkingClient.self))
            return result?.status
        } catch {
            UnifiedLogger.shared.error("Error verifying assertion: \(error.localizedDescription)", className: String(describing: VerisoulNetworkingClient.self))
            return nil

        }
    }

    /// Verifies the attestation with the given data, challenge, and key ID
    /// - Parameters:
    ///   - data: The attestation data.
    ///   - challenge: The challenge string.
    ///   - keyId: The key ID associated with the attestation.
    /// - Returns: The status of the verification request.
    public func verifyAttestation(_ data: Data, challenge: String, keyId: String) async throws -> String?{

        guard let url = URL(string: "https://ingest.\(env.rawValue).verisoul.ai/attestation") else {
//        guard let url = URL(string: "http://192.168.86.49:3002/attestation") else {
            UnifiedLogger.shared.error("Invalid URL for attestation verification POST: ingest.\(env.rawValue).verisoul.ai/worker/attestation", className: String(describing: VerisoulNetworkingClient.self))
            return nil

        }

        let body = VerifyAttestationRequest(attestation: data.base64EncodedString(),
                                            challenge: challenge,
                                            projectId: projectId,
                                            keyId: keyId)

        do {
            let result = try await networkManager.request(
                url: url,
                method: .POST,
                parameters: body.dictionary,
                headers: ["content-type": "application/json"],
                responseType: VerisoulRESPONSE.self
            )
            UnifiedLogger.shared.info("Attestation verified successfully. Status: \(result?.status)", className: String(describing: VerisoulNetworkingClient.self))
            return result?.status
        } catch {
            UnifiedLogger.shared.error("Error verifying attestation: \(error.localizedDescription)", className: String(describing: VerisoulNetworkingClient.self))
            return nil

        }
    }
}

// MARK: - Extension for Encodable to convert to dictionary

extension Encodable {

    /// Converts an `Encodable` object to a dictionary.
    var dictionary: [String: Any]? {
        let encoder = JSONEncoder()

        guard let data = try? encoder.encode(self) else {
            return nil
        }

        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments))
            .flatMap { $0 as? [String: Any] }
    }
}
