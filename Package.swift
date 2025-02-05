// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "VerisoulSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "VerisoulSDK",
            targets: ["VerisoulSDK"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "VerisoulSDK",
            path: "Sources/VerisoulSDK.xcframework"
        )
    ]
)
