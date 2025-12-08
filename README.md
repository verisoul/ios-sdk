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

### Error Codes

The SDK throws `VerisoulException` with the following error codes:

| Error Code          | Value                 | Description                                                                                                                                                | Recommended Action                                                                                                                                                                                                                                                                                                                                    |
| ------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| INVALID_ENVIRONMENT | "INVALID_ENVIRONMENT" | The environment parameter passed to init() is invalid. Valid values are "dev", "sandbox", or "prod".                                                       | Integration Error. This is a developer configuration issue, not a user error. Verify that the environment string passed to Verisoul.init() is exactly one of: dev, sandbox, or prod. Environment values are case-sensitive. Check for typos, extra whitespace, or incorrect values like "production" or "DEV".                                        |
| SESSION_UNAVAILABLE | "SESSION_UNAVAILABLE" | A valid session ID could not be obtained. This typically occurs when Verisoul's servers are unreachable due to network blocking or a very slow connection. | Retry with backoff. Verisoul may be blocked by a firewall, VPN, or the user has poor connectivity. Implement retry logic with exponential backoff. If the error persists, prompt the user to check their network connection or try disabling VPN/proxy settings. Consider logging this for debugging network issues in specific regions or networks.  |
| WEBVIEW_UNAVAILABLE | "WEBVIEW_UNAVAILABLE" | WebView is not available on the device. This can occur when WebView is disabled, missing, uninstalled, or corrupted on the device.                         | Prompt user action. This error is not retried by the SDK since WebView availability won't change during the session. Recommend prompting the user to: (1) Use a device that supports WebViews, (2) Enable WebView if it has been disabled in device settings, or (3) Update Android System WebView from the Play Store if it's outdated or corrupted. |

#### Detailed Error Code Documentation

**INVALID_ENVIRONMENT**

Type: Integration Error (Developer)

When it occurs:

- Passing an invalid string to `VerisoulEnvironment.fromValue()` or equivalent
- Environment value not matching exactly: `dev`, `sandbox`, or `prod`
- Case sensitivity issues (e.g., "DEV" instead of "dev")
- Extra whitespace (e.g., " dev ")
- Typos (e.g., "production" instead of "prod")

SDK Behavior:

- Exception thrown immediately during initialization
- No retries attempted

Developer Action:

```swift
// ✅ Correct
Verisoul.shared.configure(env: .prod, projectId: "your-project-id")

// ❌ Incorrect - will throw INVALID_ENVIRONMENT
// Using incorrect environment strings or values
```

**SESSION_UNAVAILABLE**

Type: Runtime Error (Network/Connectivity)

When it occurs:

- Network timeout waiting for session
- Verisoul servers unreachable
- Network blocking (firewall, corporate proxy, VPN)
- Very slow network connection
- All retry attempts exhausted

SDK Behavior:

- SDK automatically retries up to 4 times with delays
- WebView initialization retries up to 3 times
- Error thrown only after all retries are exhausted

Developer Action:

```swift
do {
    let sessionId = try await Verisoul.shared.session()
    // Use sessionId
} catch let error as VerisoulException {
    if error.code == VerisoulErrorCodes.SESSION_UNAVAILABLE {
        // Implement retry with backoff or prompt user about connectivity
    }
}
```

**WEBVIEW_UNAVAILABLE**

Type: Device Limitation Error

When it occurs:

- WebView is disabled on the device
- WebView component is missing or uninstalled
- WebView is corrupted or incompatible
- Device doesn't support WebView (rare, older/custom ROMs)

SDK Behavior:

- No retries - fails immediately
- This is intentional since WebView availability won't change during the app session

Developer Action:

```swift
do {
    let sessionId = try await Verisoul.shared.session()
    // Use sessionId
} catch let error as VerisoulException {
    if error.code == VerisoulErrorCodes.WEBVIEW_UNAVAILABLE {
        // Show user-friendly message:
        // "Please enable WebView in your device settings or
        //  update Android System WebView from the Play Store"
    }
}
```

#### Exception Structure

All errors are thrown as `VerisoulException` with the following properties:

| Property | Type       | Description                                             |
| -------- | ---------- | ------------------------------------------------------- |
| code     | String     | One of the error codes above                            |
| message  | String     | Human-readable error description                        |
| cause    | Throwable? | The underlying exception that caused the error (if any) |

## Example

For a complete working example, see the [example folder](https://github.com/verisoul/ios-sdk/tree/main/Example) in this repository.

## Additional Resource

- [Verisoul CocoaPods](https://cocoapods.org/pods/VerisoulSDK)
