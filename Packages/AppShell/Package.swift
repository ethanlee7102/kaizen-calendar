// swift-tools-version: 6.2
// AppShell: the macOS-only shell around the app's content. The desktop sticky-note panel
// (collapsed and expanded), its saved positions, day-change monitoring, the login item and the
// global expand/collapse shortcut.
// See claude-context/build-plan.md, Phase 3, and memory/desktop-window-findings.md (LOCKED).
import PackageDescription

let package = Package(
    name: "AppShell",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppShell", targets: ["AppShell"])
    ],
    dependencies: [
        // The optional global expand/collapse shortcut and its recorder (spec-settings.md).
        // Sandbox-safe (Carbon hot keys, no Accessibility permission).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "AppShell",
            dependencies: [.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "AppShellTests",
            dependencies: ["AppShell"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
