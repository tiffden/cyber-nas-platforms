// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CyberspaceMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CyberspaceMac",
            targets: ["CyberspaceMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CyberspaceMac",
            path: "CyberspaceMac",
            exclude: [
                "Resources/Assets.xcassets/.gitkeep",
                "Resources/Preview Content/.gitkeep",
                "App/.gitkeep",
                "Features/Audit/.gitkeep",
                "Features/Certificates/.gitkeep",
                "Features/Keyring/.gitkeep",
                "Features/Onboarding/.gitkeep",
                "Features/Realm/.gitkeep",
                "Features/Settings/.gitkeep",
                "Features/Terminal/.gitkeep",
                "Shared/API/.gitkeep",
                "Shared/Models/.gitkeep",
                "Shared/Security/.gitkeep",
                "Shared/State/.gitkeep",
                "Shared/UIComponents/.gitkeep",
                "Bridges/AppKitTerminal/.gitkeep",
                "SupportingFiles/.gitkeep"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CyberspaceMacUnitTests",
            dependencies: ["CyberspaceMac"],
            path: "Tests/Unit"
        )
    ]
)
