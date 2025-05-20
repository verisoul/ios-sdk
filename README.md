<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="resources/verisoul-logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="resources/verisoul-logo-light.svg">
  <img src="resources/verisoul-logo-light.svg" alt="Verisoul logo" width="312px" style="visibility:visible;max-width:100%;">
</picture>
</p>

# iOS SDK

## Overview
The purpose of this app is to demonstrate Verisoul's iOS SDK integration.

_To run the app a Verisoul Project ID is required._ Schedule a call [here](https://meetings.hubspot.com/henry-legard) to get started.

## Getting Started

You can install VerisoulSDK in your iOS project using either CocoaPods or Swift Package Manager.

### CocoaPods

To integrate VerisoulSDK with CocoaPods:

1. Ensure CocoaPods is installed on your machine. If not, run:
   ```sh
   sudo gem install cocoapods
   ```
2. Add VerisoulSDK to your Podfile:
   ```ruby
   pod 'VerisoulSDK', '~> 0.3.12'
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

## Capabilities

To fully utilize VerisoulSDK, you must add the `App Attest` capability to your project. This capability allows the SDK to perform necessary checks and validations to ensure the integrity and security of your application.

Update your app’s entitlements file:

```
<key>com.apple.developer.devicecheck.appattest-environment</key>
<string>production/development (depending on your needs)</string>
```


## Usage

### 1. Initialization

`configure(env:projectId:bundleIdentifier:)`

Configure the SDK by passing it the environment, project ID, and bundle identifier. This function initializes the networking, device check, and device attestation components.

**Parameters:**

- `env (VerisoulEnvironment)`: The environment to configure the SDK with (e.g., dev, staging, prod).
- `projectId (String)`: Your project's unique identifier.
- `bundleIdentifier (String)`: The bundle identifier of your app.


```swift
Verisoul.shared.configure(env: .prod, projectId: "your-project-id")
```

**Note:** The `configure(env:projectId:)` method should be called once, typically during the app's initialization process (e.g., in the `AppDelegate` or `SceneDelegate`).

### 2. Get Session ID

`session() async throws -> String`

Once the minimum amount of data is gathered the session ID becomes available. The session ID is needed in order to request a risk assessment from Verisoul's API. Note that session IDs are short lived and will expire after 24 hours. The application can obtain session ID by providing the callback as shown below:


```swift
do {
    let sessionId = try await Verisoul.shared.session()
    print("Session ID: \(sessionId)")
} catch {
    print("Failed to retrieve session ID: \(error)")
}
```

## Update the privacy manifest file

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!--
   PrivacyInfo.xcprivacy
   test

   Created by Raine Scott on 1/30/25.
   Copyright (c) 2025 ___ORGANIZATIONNAME___.
   All rights reserved.
-->
<plist version="1.0">
<dict>
    <!-- Privacy manifest file for Verisoul Fraud Prevention SDK for iOS -->
    <key>NSPrivacyTracking</key>
    <false/>

    <!-- Privacy manifest file for Verisoul Fraud Prevention SDK for iOS -->
    <key>NSPrivacyTrackingDomains</key>
    <array/>

    <!-- Privacy manifest file for Verisoul Fraud Prevention SDK for iOS -->
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
      <dict>
        <!-- The value provided by Apple for 'Device ID' data type -->
        <key>NSPrivacyCollectedDataType</key>
        <string>NSPrivacyCollectedDataTypeDeviceID</string>

        <!-- Verisoul Fraud Prevention SDK does not link the 'Device ID' with user's identity -->
        <key>NSPrivacyCollectedDataTypeLinked</key>
        <false/>

        <!-- Verisoul Fraud Prevention SDK does not use 'Device ID' for tracking -->
        <key>NSPrivacyCollectedDataTypeTracking</key>
        <false/>

        <!-- Verisoul Fraud Prevention SDK uses 'Device ID' for App Functionality
             (prevent fraud and implement security measures) -->
        <key>NSPrivacyCollectedDataTypePurposes</key>
        <array>
          <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
        </array>
      </dict>
    </array>

    <!-- Privacy manifest file for Verisoul Fraud Prevention SDK for iOS -->
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
      <dict>
        <!-- The value provided by Apple for 'System boot time APIs' -->
        <key>NSPrivacyAccessedAPIType</key>
        <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
        
        <!-- Verisoul Fraud Prevention SDK uses 'System boot time APIs' to measure the amount of
             time that has elapsed between events that occurred within the SDK -->
        <key>NSPrivacyAccessedAPITypeReasons</key>
        <array>
          <string>35F9.1</string>
        </array>
      </dict>
    </array>
</dict>
</plist>

```

## Questions and Feedback
Comprehensive documentation about Verisoul's iOS SDK and API can be found at [docs.verisoul.ai](https://docs.verisoul.ai/). Additionally, reach out to Verisoul at [help@verisoul.ai](mailto:help@verisoul.ai) for any questions or feedback.
