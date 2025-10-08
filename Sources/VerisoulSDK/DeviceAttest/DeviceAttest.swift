import Foundation
import DeviceCheck
import CryptoKit

// MARK: - Protocol

/// Protocol to define the interface for device attestation functionality.
internal protocol DeviceAttestInterface {
    func getKeyId() async throws -> String?
    func getNewKeyId() async throws -> String?
    func getChallenge() async throws -> String?
    func verifyAttestation(_ data: Data, challenge: String, keyId: String) async throws -> String?
    func generateAttestation(keyId: String, challenge: Data) async throws -> Data?
    func generateAssertion(keyId: String, requestData: Data) async throws -> Data?
    func attestApp(projectId: String) async throws -> Bool?
    func setSessionId(sessionId: String) async throws
}

// MARK: - Errors

/// Enum for defining possible errors related to app attestation.
enum AppAttestError: Error {
    case getKey(Error?)
    case generateAttestation(Error?)
    case generateAssertion(Error?)
    case createAttestationRequest(Error?)
    case sendRequest(String?)
    case notSupported
}

// MARK: - DeviceAttest

/// Class that implements the `DeviceAttestInterface` protocol.
public final class DeviceAttest: DeviceAttestInterface {

    // MARK: - Properties

    private let service: DCAppAttestService
    let keychainKey = "attest_key_id"
    let networkManager: VerisoulNetworkingClientInterface
    let projectId: String
    let encoder = JSONEncoder()
    var sessionId: String?
    var dataToSend: [String: Any]?

    public init(networkManager: VerisoulNetworkingClientInterface, projectId: String) {
        self.service = DCAppAttestService.shared
        self.networkManager = networkManager
        self.projectId = projectId

        UnifiedLogger.shared.info("DeviceAttest service initialized.", className: String(describing: DeviceAttest.self))
    }

    // MARK: - DeviceAttestInterface Methods

    /// Retrieves the current key ID from the device.
    public func getKeyId() async throws -> String? {
        log("Fetching the current key ID.")

        guard service.isSupported else {
            try throwError(.notSupported, message: "DeviceAttest is not supported on this device.")
            return nil
        }

        do {
            let keyId = try await service.generateKey()
            KeychainHelper.shared.set(keyId, key: keychainKey)
            log("Key ID retrieved successfully.")
            return keyId
        } catch {
            try throwError(.getKey(error), message: "Failed to retrieve key ID: \(error.localizedDescription)")
            return nil
        }
    }

    /// Generates a new key ID by removing the old key and retrieving a new one.
    public func getNewKeyId() async throws -> String? {
        log("Generating new key ID by removing the old one.")

        KeychainHelper.shared.remove(key: keychainKey)

        do {
            return try await getKeyId()
        } catch {
            try throwError(.getKey(error), message: "Failed to generate new key ID: \(error.localizedDescription)")
            return nil

        }
    }

    /// Fetches a challenge string from the network manager.
    public func getChallenge() async throws -> String? {
        log("Fetching challenge string from the network manager.")

        do {
            guard let challenge = try await networkManager.getChallenge() else { return nil }
            log("Challenge string retrieved successfully.")
            return challenge
        } catch {
            try throwError(.createAttestationRequest(error), message: "Failed to retrieve challenge string: \(error.localizedDescription)")
            return nil;
        }
    }

    /// Verifies the attestation data with the network service.
    public func verifyAttestation(_ data: Data, challenge: String, keyId: String) async throws -> String? {
        log("Verifying attestation data with network service.")

        do {
            guard let verificationResult = try await networkManager.verifyAttestation(data, challenge: challenge, keyId: keyId) else { return nil }
            log("Attestation verification successful.")
            
            guard challenge != nil else {
                return nil;

            }
            return verificationResult
        } catch {
            try throwError(.sendRequest(error.localizedDescription), message: "Attestation verification failed: \(error.localizedDescription)")
            return nil

        }
    }

    /// Generates the attestation data for the specified key ID and challenge.
    public func generateAttestation(keyId: String, challenge: Data) async throws -> Data? {
        log("Generating attestation for key ID: \(keyId).")

        guard service.isSupported else {
            try throwError(.notSupported, message: "DeviceAttest is not supported on this device.")
            return nil

        }

        let challengeHash = Data(SHA256.hash(data: challenge))
        do {
            let attestation = try await service.attestKey(keyId, clientDataHash: challengeHash)
            log("Attestation generated successfully.")
            return attestation
        } catch {
            KeychainHelper.shared.remove(key: keychainKey)
            try throwError(.generateAttestation(error), message: "Failed to generate attestation: \(error.localizedDescription)")
            return nil

        }
    }

    /// Generates an assertion for the specified key ID and request data.
    public func generateAssertion(keyId: String, requestData: Data) async throws -> Data? {
        log("Generating assertion for key ID: \(keyId).")

        guard service.isSupported else {
            try throwError(.notSupported, message: "DeviceAttest is not supported on this device.")
            return nil

        }

        let clientDataHash = Data(SHA256.hash(data: requestData))
        do {
            let assertionValue = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
            log("Assertion generated successfully.")
            return assertionValue
        } catch {
            KeychainHelper.shared.remove(key: keychainKey)
            try throwError(.generateAssertion(error), message: "Failed to generate assertion: \(error.localizedDescription)")
            return nil

        }
    }


    public func sendAssertion() async throws -> Bool? {
        guard let sessionId = self.sessionId else {
            // Nothing to send if we don't have a sessionId
            return false

        }
        guard let dataToSend = self.dataToSend else {
            // Nothing to send if we have no data
            return false
        }

        // Pass data & sessionId along to the network
        let response = try? await networkManager.verifyAssertion(
            sessionId: sessionId,
            data: dataToSend,
            projectId: self.projectId
        )

        return response?.lowercased() == "ok"

    }

    internal func setSessionId(sessionId: String) async throws {
        self.sessionId = sessionId
        try await self.sendAssertion()

    }
    /// Executes the full attestation flow and returns a `SendMessageREQUEST`.
    internal func attestApp(projectId: String) async throws -> Bool? {
        log("Starting full attestation flow (non-throwing).")

         let startTime = CFAbsoluteTimeGetCurrent()

         // 1. Get the keyId (fallback is "" on error).
         let keyId = (try? await getKeyId()) ?? ""

         // 2. Get the challenge (fallback is "" on error).
         let challenge = (try? await getChallenge()) ?? ""

         // 3. Generate attestation (fallback is empty Data on error).
         let attestationData = (try? await generateAttestation(
             keyId: keyId,
             challenge: Data(challenge.utf8))
         ) ?? Data()

         // 4. Verify attestation (this might be an empty or partial response).
         //    We only store it if we want, or log the success.
         //    If it fails, fallback is an empty String.
         let verificationResult = (try? await verifyAttestation(
             attestationData,
             challenge: challenge,
             keyId: keyId)
         ) ?? ""

         // 5. Create a payload
         let payload = Payload(challenge: challenge)

         // 6. Encode the payload (fallback is empty Data on error).
         let encodedPayload: Data
         do {
             encodedPayload = try encoder.encode(payload)
         } catch {
             log("Failed to encode payload: \(error.localizedDescription)", level: .error)
             encodedPayload = Data()
         }

         // 7. Generate assertion (fallback is empty Data on error).
         let assertion = (try? await generateAssertion(
             keyId: keyId,
             requestData: encodedPayload)
         ) ?? Data()

         // 8. Collect the partial (or full) data
         let data = [
             "assertion": assertion.base64EncodedString(),
             "challenge": challenge,
             "project_id": projectId,
             "payload": encodedPayload.base64EncodedString(),
             "key_id": keyId
         ]

         self.dataToSend = data
        var isSuccess = false
         // 9. Attempt to send it, ignoring errors. Wrap in do/catch or use try?
         do {
             isSuccess =  ((try? await self.sendAssertion()) ?? false)
         } catch {
             log("Failed to send assertion: \(error.localizedDescription)", level: .error)
         }

         let endTime = CFAbsoluteTimeGetCurrent()
         log("Non-throwing attestation flow completed. Duration: \(endTime - startTime)s")

         // Optionally record a metric even if partial data.
         UnifiedLogger.shared.metric(
             value: (endTime - startTime),
             name: "attestation_flow_duration",
             className: String(describing: DeviceAttest.self)
         )
        return isSuccess
    }

    // MARK: - Helper Methods

    /// Logs a message with the specified level.
    private func log(_ message: String, level: LogLevel = .info) {
        UnifiedLogger.shared.log(message, level: level, className: String(describing: DeviceAttest.self))
    }

    /// Throws an error and logs the associated message.
    private func throwError(_ error: AppAttestError, message: String) throws{
        log(message, level: .error)
    }
}
