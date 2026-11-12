// swift-tools-version: 6.2
// Persistence: SQLiteData schema, migrations and queries. See claude-context/build-plan.md, Phase 2.
import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                "Core",
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
