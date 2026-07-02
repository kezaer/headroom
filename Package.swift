// swift-tools-version: 6.0
import PackageDescription

// UsageBar — a menu bar app that shows remaining usage for AI subscriptions.
//
// Structured as a Swift package so the testable core (`UsageBarCore`) builds and
// verifies via `swift build` / `swift test` in CI and headless environments. The
// package opens directly in Xcode 26 and `xcodebuild -scheme UsageBar` builds it.
// Finalizing the distributable menu bar app (LSUIElement Info.plist, launch-at-login
// bundle, and the stable Apple Development signing identity in KTD8) is done in Xcode
// on the user's machine — see docs/plans and README.
let package = Package(
    name: "UsageBar",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "UsageBarCore", targets: ["UsageBarCore"]),
        .executable(name: "UsageBar", targets: ["UsageBarApp"]),
    ],
    targets: [
        .target(name: "UsageBarCore"),
        .executableTarget(
            name: "UsageBarApp",
            dependencies: ["UsageBarCore"]
        ),
        .testTarget(
            name: "UsageBarCoreTests",
            dependencies: ["UsageBarCore"]
        ),
    ]
)
