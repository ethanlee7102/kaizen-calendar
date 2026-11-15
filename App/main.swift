import AppKit

// The app is one AppKit panel (the note), so it uses the AppKit life cycle rather than a SwiftUI
// `App`: no SwiftUI scenes or windows to work around, and the menus are built in `MainMenu`.
// It's a regular Dock app with no menu bar icon (spec-visual-identity.md).
// No macOS window restoration: the note restores its own position (AppShell's PositionStore).
// Without this, a crash makes the next launch stop at a "reopen windows?" alert.
UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
let delegate = AppDelegate(options: .current)
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
