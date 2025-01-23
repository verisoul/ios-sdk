# VerisoulSDK v0.1

VerisoulSDK is an iOS SDK designed to help detect and prevent fake users, bots, multi-accounting, fraud, and other malicious activities on your platform. It provides a seamless and easy-to-integrate solution to ensure that every user is legitimate, trusted, and unique.

## Features
- **Bot Detection**: Detects and blocks bot traffic automatically.
- **Multi-Account Prevention**: Identifies and blocks users creating multiple accounts.
- **Fraud Prevention**: Detects high-risk accounts to prevent fraudulent behavior.
- **Quick Integration**: Supports both CocoaPods and Swift Package Manager (SPM).
- **Real-time Monitoring**: Continuously monitors user behavior to identify suspicious activities at critical moments in an account’s lifecycle.

## Installation

You can install VerisoulSDK in your iOS project using either CocoaPods or Swift Package Manager.

### CocoaPods

To integrate VerisoulSDK with CocoaPods:

1. Ensure CocoaPods is installed on your machine. If not, run:
   ```swift
   sudo gem install cocoapods
   ```
2. Add VerisoulSDK to your Podfile:
    ```swift
    pod 'VerisoulSDK', '~> 0.1'
     ```
3. Run the following command to install the SDK:
    ```swift
    pod install
     ```
4. Open the .xcworkspace file in Xcode and start using the SDK.


### Swift Package Manager (SPM)
To integrate VerisoulSDK using Swift Package Manager:

Open your project in Xcode.

Go to File > Add Packages.

Enter the repository URL for VerisoulSDK:
```swift
    https://github.com/verisoul/ios-sdk.git
```swift
Choose the version you wish to use and add the package.

The SDK will automatically integrate into your project.

### VerisoulSDK Class
VerisoulSDK provides the following public methods:

1. configure(env:projectId:bundleIdentifier:)
Configures the SDK with the environment, project ID, and bundle identifier. This initializes the networking, device check, and device attestation components.

Parameters:

env (VerisoulEnvironment): The environment to configure the SDK with (e.g., dev, staging, prod).
projectId (String): Your project's unique identifier.
bundleIdentifier (String): The app's bundle identifier.
```swift
    VerisoulSDK.shared.configure(env: .prod, projectId: "your-project-id", 
    bundleIdentifier: "com.example.app")
```swift
SDK Configuration: The configure(env:projectId:bundleIdentifier:) method should be called once, typically during the app's initialization process (e.g., in the AppDelegate or SceneDelegate)

2. session() async throws -> String
Retrieves the session ID asynchronously. Waits up to 10 seconds for the session ID from the web view.

Returns:
A string representing the session ID.
Throws:

An error if the session ID cannot be retrieved within the timeout.
```swift
do {
    let sessionId = try await VerisoulSDK.shared.session()
    print("Session ID: \(sessionId)")
} catch {
    print("Failed to retrieve session ID: \(error)")
}
```swift
