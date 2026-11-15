// swift-tools-version: 6.2
// AppShell: the macOS-only shell around the app's content. The desktop sticky-note panel
// (collapsed and expanded), its saved positions, day-change monitoring and the login item.
// See claude-context/build-plan.md, Phase 3, and memory/desktop-window-findings.md (LOCKED).
import PackageDescription

let package = Package(
    name: "AppShell",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppShell", targets: ["AppShell"])
    ],
    targets: [
        .target(
            name: "AppShell",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "AppShellTests",
            dependencies: ["AppShell"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
