// swift-tools-version: 6.2
// Throwaway prototype: checks whether a desktop-level "sticky note" window behaves the way 66 Days needs.
import PackageDescription

let package = Package(
    name: "DesktopWindowPrototype",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "DesktopWindowPrototype")
    ]
)
