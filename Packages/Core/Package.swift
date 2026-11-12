// swift-tools-version: 6.2
// Core: the habit rules as pure Swift (no UI, no database). See claude-context/build-plan.md, Phase 1.
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
