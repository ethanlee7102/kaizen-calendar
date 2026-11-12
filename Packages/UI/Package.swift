// swift-tools-version: 6.2
// UI: shared SwiftUI views, components and design tokens (reusable on iOS later).
import PackageDescription

let package = Package(
    name: "UI",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "UI", targets: ["UI"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "UI",
            dependencies: ["Core"],
            resources: [.copy("Resources/Fonts")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "UITests",
            dependencies: ["UI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
