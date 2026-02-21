// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftUISPKIBridgeStaging",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftUISPKIBridgeStaging",
            targets: ["SwiftUISPKIBridgeStaging"]
        )
    ],
    targets: [
        .target(
            name: "SwiftUISPKIBridgeStaging",
            path: "swiftui",
            exclude: [
                "scripts"
            ]
        )
    ]
)
