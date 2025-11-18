# Verisoul iOS Sample App

This example app demonstrates how to integrate the Verisoul SDK into an iOS application for fraud detection and account security.

## Requirements

- Xcode 15.0 or higher
- iOS 14.0 or higher
- CocoaPods (if not using SPM)
- Mac running macOS

> **Note**: Make sure you have completed the [Xcode setup](https://developer.apple.com/xcode/) before proceeding.

## Configure

Before running the sample app, you need to configure it with your Verisoul credentials.

1. Open `Example.xcodeproj` or `Example.xcworkspace` in Xcode

2. Locate the Verisoul configuration in the code (typically in `AppDelegate.swift` or `SceneDelegate.swift`) and add your credentials:

```swift
Verisoul.shared.configure(
    env: .sandbox, // Change to .prod for production
    projectId: "YOUR_PROJECT_ID" // Replace with your actual project ID
)
```

3. If you don't have a Verisoul Project ID, schedule a call [here](https://meetings.hubspot.com/henry-legard) to get started.

## Get Started

### Step 1: Install Dependencies

If the project uses CocoaPods, install the dependencies:

```sh
cd Example
pod install
```

If using Swift Package Manager, Xcode will automatically resolve dependencies when you open the project.

### Step 2: Run the App

1. Open the project in Xcode:
   - If using CocoaPods: Open `Example.xcworkspace`
   - If using SPM: Open `Example.xcodeproj`

2. Select your target device or simulator from the scheme selector

3. Click the Run button (⌘R) or go to `Product > Run`

The app will build and launch on your selected device/simulator.

> **Note:** To run on a physical device, you'll need to configure your Apple Developer account and signing certificates in Xcode.

## Troubleshooting

### CocoaPods Issues

If you encounter CocoaPods-related errors:

- Make sure CocoaPods is installed: `sudo gem install cocoapods`
- Try updating CocoaPods: `pod update`
- Clean the build: `Product > Clean Build Folder` (⇧⌘K)

### Signing Issues

If you see code signing errors:

- Go to the project settings in Xcode
- Select the `Example` target
- Under `Signing & Capabilities`, select your development team
- Ensure "Automatically manage signing" is checked

### Build Errors

If the project won't build:

- Clean the build folder: `Product > Clean Build Folder` (⇧⌘K)
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Restart Xcode

## Learn More

- [Verisoul Documentation](https://docs.verisoul.ai/)
- [iOS SDK Documentation](https://docs.verisoul.ai/integration/frontend/ios)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
