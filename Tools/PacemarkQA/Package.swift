// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "PacemarkQA", platforms: [.macOS(.v15)], targets: [
    .target(name: "Display"),
    .executableTarget(name: "PacemarkQA", dependencies: ["Display"])
])
