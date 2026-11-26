// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Opt-in DialKit live tuning (`Scripts/dialkit.sh`); off unless PACEMARK_DIALKIT=1.
let dialKit = ProcessInfo.processInfo.environment["PACEMARK_DIALKIT"] == "1"

let package = Package(
    name: "Pacemark",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "PacemarkCore", targets: ["PacemarkCore"]),
        .library(name: "PacemarkSharedUI", targets: ["PacemarkSharedUI"]),
        .executable(name: "Pacemark", targets: ["PacemarkApp"]),
    ],
    dependencies: dialKit ? [.package(url: "https://github.com/mikelikesdesign/dialkit-macos", revision: "cc305b46beb731e50cbdde84aed5530d83842acc")] : [],
    targets: [
        .target(name: "PacemarkCore"),
        .target(
            name: "PacemarkSharedUI",
            dependencies: ["PacemarkCore"]
        ),
        .executableTarget(
            name: "PacemarkApp",
            dependencies: ["PacemarkCore", "PacemarkSharedUI"]
                + (dialKit ? [
                    .product(name: "DialkitmacOS", package: "dialkit-macos"),
                    .product(name: "DialkitmacOSAgent", package: "dialkit-macos"),
                ] : []),
            // The app icon catalog is compiled by actool in the xcodegen/xcodebuild app
            // build only; excluding it keeps `swift build`/`swift test` (a plain CLI
            // executable, no app bundle) fast and free of asset-catalog processing.
            exclude: ["Resources/Assets.xcassets"],
            resources: [.process("Resources")],
            swiftSettings: dialKit ? [.define("PACEMARK_DIALKIT")] : []
        ),
        .testTarget(
            name: "PacemarkCoreTests",
            dependencies: ["PacemarkCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
