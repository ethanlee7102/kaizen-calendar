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
        .package(path: "../Core"),
        // Snapshot tests of the note and its marks (tests only). Already used by SQLiteData, so
        // the app's Package.resolved pins it.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
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
            dependencies: [
                "UI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
