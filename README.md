<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="resources/verisoul-logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="resources/verisoul-logo-light.svg">
  <img src="resources/verisoul-logo-light.svg" alt="Verisoul logo" width="312px" style="visibility:visible;max-width:100%;">
</picture>
</p>

# iOS SDK

Verisoul provides an iOS SDK that allows you to implement fraud prevention in your iOS applications. This guide covers the installation, configuration, and usage of the Verisoul iOS SDK.

_To run the SDK a Verisoul Project ID is required._ Schedule a call [here](https://meetings.hubspot.com/henry-legard) to get started.

## System Requirements

- iOS 14.0 or higher
- Xcode 15.0 or higher
- Swift 5.9 or higher
- CocoaPods 1.10+ (if using CocoaPods)

## Installation

You can install VerisoulSDK in your iOS project using either CocoaPods or Swift Package Manager.

### CocoaPods

To integrate VerisoulSDK with CocoaPods:

1. Ensure CocoaPods is installed on your machine. If not, run:
   ```sh
   sudo gem install cocoapods
   ```
2. Add VerisoulSDK to your Podfile:
   ```ruby
   pod 'VerisoulSDK', '~> 0.4.63'
   ```
3. Run the following command to install the SDK:
   ```sh
   pod install
   ```
4. Open the `.xcworkspace` file in Xcode and start using the SDK.

### Swift Package Manager (SPM)

To integrate VerisoulSDK using Swift Package Manager:

1. Open your project in Xcode.
2. Go to `File > Add Packages`.
3. Enter the repository URL for VerisoulSDK:
   ```url
   https://github.com/verisoul/ios-sdk.git
   ```
4. Choose the version you wish to use and add the package.

The SDK will automatically integrate into your project.

### iOS Device Check

To fully utilize the Verisoul SDK, you must add the `App Attest` capability to your project. This capability allows the SDK to perform necessary checks and validations to ensure the integrity and security of your application.

Update your app's entitlements file:

```xml
<key>com.apple.developer.devicecheck.appattest-environment</key>
<string>production</string>  <!-- Use 'development' for testing -->
```

## Usage

### Initialize the SDK

Call `configure()` when your application starts, typically in `AppDelegate` or the main app entry point.

```swift
import VerisoulSDK

Verisoul.shared.configure(env: .prod, projectId: "your-project-id")
```

The `configure()` method initializes the Verisoul SDK with your project credentials. This method must be called once when your application starts.

**Parameters:**

- `env`: The environment to use `.prod` for production or `.sandbox` for testing
- `projectId`: Your unique Verisoul project identifier

### Get Session ID

The `session()` method returns the current session identifier after the SDK has collected sufficient device data. This session ID is required to request a risk assessment from Verisoul's API.

**Important Notes:**

- Session IDs are short-lived and expire after 24 hours
- The session ID becomes available once minimum data collection is complete (typically within seconds)
- You should send this session ID to your backend, which can then call Verisoul's API to get a risk assessment

**Example:**

```swift
do {
    let sessionId = try await Verisoul.shared.session()
    // Send sessionId to your backend for risk assessment
    print("Session ID: \(sessionId)")
} catch {
    print("Failed to retrieve session ID: \(error)")
}
```

### Reinitialize Session

The `reinitialize()` method generates a fresh session ID and resets the SDK's data collection. This is essential for maintaining data integrity when user context changes.

**Example:**

```swift
// User logs out
await Verisoul.shared.reinitialize()

// Now ready for a new user to log in with a fresh session
```

After calling this method, you can call `session()` to retrieve the new session identifier.

### Provide Touch Events

The Verisoul SDK automatically captures touch events when integrated. No additional code is required for touch event collection.

## Example

For a complete working example, see the [example folder](https://github.com/verisoul/ios-sdk/tree/main/Example) in this repository.

## Additional Resource
- [Verisoul CocoaPods](https://cocoapods.org/pods/VerisoulSDK)
