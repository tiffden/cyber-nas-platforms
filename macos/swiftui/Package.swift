// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Allow CHEZ_LIB override for non-standard Homebrew prefixes or
// alternative Chez Scheme versions. Default matches build.sh.
let chezLib = ProcessInfo.processInfo.environment["CHEZ_LIB"]
    ?? "/opt/homebrew/Cellar/chezscheme/10.3.0/lib/csv10.3.0/tarm64osx"

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
    dependencies: [
        // CyberspaceREPLUI: pure Swift REPL terminal UI from the overlay.
        // No C dependencies — safe to depend on without unsafe flag concerns.
        .package(path: "../../../cyber-nas-overlay/spki/scheme/swift")
    ],
    targets: [
        // ChezShim: C shim wrapping the 4 Chez macro functions that Swift
        // cannot call directly. Compiles chez-shim.c and exposes a Swift
        // module; no bridging header needed in the main target.
        .target(
            name: "ChezShim",
            path: "CyberspaceMac/Bridges/AppKitTerminal/ChezShim",
            publicHeadersPath: ".",
            cSettings: [
                .unsafeFlags(["-I\(chezLib)"])
            ]
        ),

        .executableTarget(
            name: "CyberspaceMac",
            dependencies: [
                "ChezShim",
                .product(name: "CyberspaceREPLUI", package: "swift")
            ],
            path: "CyberspaceMac",
            exclude: [
                // C shim compiled as separate ChezShim target — must not overlap
                "Bridges/AppKitTerminal/ChezShim",
                // Placeholder gitkeeps
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
            ],
            linkerSettings: [
                // Chez Scheme static libraries + system deps
                .unsafeFlags([
                    "\(chezLib)/libkernel.a",
                    "\(chezLib)/libz.a",
                    "\(chezLib)/liblz4.a",
                    "-liconv",
                    "-lncurses",
                    "-lm"
                ])
            ]
        ),
        .testTarget(
            name: "CyberspaceMacUnitTests",
            dependencies: ["CyberspaceMac"],
            path: "Tests/Unit"
        )
    ]
)
