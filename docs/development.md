# Development

Build Pacemark with Xcode 27, Swift 6 and XcodeGen. The deployment target is macOS 15.

```sh
swift build
swift test
./Scripts/build-app.sh --deps-only
xcodebuild -project Pacemark.xcodeproj -scheme PacemarkAppTests -destination 'platform=macOS' -derivedDataPath .xcode-derived CODE_SIGNING_ALLOWED=NO test
./Scripts/pacemark.sh build
```

The packaging command produces `Pacemark.app` in the checkout. It uses ad-hoc signing by default. Set `PACEMARK_CODESIGN_IDENTITY` to use a local signing identity.

Provider logic, polling, accounts and preferences live in `Sources/PacemarkCore`. Stateless views live in `Sources/PacemarkSharedUI`. The menu bar, popover and Settings live in `Sources/PacemarkApp`. See [the local verification guide](dev/LOCAL-MODELS.md) for isolated replay and live-window QA.
