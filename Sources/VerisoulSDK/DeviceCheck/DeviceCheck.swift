import Foundation
import DeviceCheck

// Protocol to define the interface for device check functionality
internal protocol DeviceCheckInterface {

    // Method to generate a device token.
    // This will throw an error if token generation fails.
    func generateDeviceToken() async throws -> Data?
}

// DeviceCheck class that implements the DeviceCheckInterface protocol
public class DeviceCheck: DeviceCheckInterface {

    let networkManager = NetworkManager()
    let service: DCDevice

    public init() {
        service = DCDevice.current
        UnifiedLogger.shared.info("DeviceCheck service initialized.", className: String(describing: DeviceCheck.self))
    }

    // MARK: - DeviceCheckInterface Method Implementations

    /// Generates a device token using the DeviceCheck service.
    /// Throws an error if DeviceCheck is not supported on the device, or if token generation fails.
    public func generateDeviceToken() async throws -> Data? {
        UnifiedLogger.shared.info("Attempting to generate device token.", className: String(describing: DeviceCheck.self))
        let startTime = CFAbsoluteTimeGetCurrent()
        // Ensure that DeviceCheck is supported on this device
        guard service.isSupported else {
            UnifiedLogger.shared.error("DeviceCheck is not supported on this device.", className: String(describing: DeviceCheck.self))
            return nil
        }

        do {
            // Attempt to generate the device token
            let token = try await DCDevice.current.generateToken()
            let endTime = CFAbsoluteTimeGetCurrent()
            UnifiedLogger.shared.info("Device token generated successfully. \(token)", className: String(describing: DeviceCheck.self))
            UnifiedLogger.shared.metric(value: (endTime - startTime),
                                        name: "device_token_generation_time",
                                        className: String(describing: self))
            return token
        } catch {
            // Handle any errors that occur during token generation
            UnifiedLogger.shared.error("Failed to generate device token: \(error.localizedDescription)", className: String(describing: DeviceCheck.self))
            return nil

        }
    }
}
