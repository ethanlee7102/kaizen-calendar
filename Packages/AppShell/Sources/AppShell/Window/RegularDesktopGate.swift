import AppKit

/// Runs an action once the active space is a regular desktop, not another app's full-screen
/// space.
///
/// Why: the note is a non-activating panel, and macOS lets that kind of window join another app's
/// full-screen space. It joins whatever space is active when it's first shown, so launching from
/// a full-screen app stranded it there (Phase 3). macOS has no public "is this space full screen"
/// API, but it never places an ordinary window on another app's full-screen space. So the gate
/// orders in an invisible ordinary window and waits until that window is on the active space.
///
/// Confirmed by the Phase 3 window probe (2026-11-14): launched from full-screen VS Code, macOS
/// switched to the desktop as soon as the helper appeared (the app is active after a launch), and
/// the note was shown there. From a desktop, and at login, the note shows right away. If the user
/// stays in a full-screen app, the action waits for the next switch to a desktop.
/// (`.fullScreenNone` on the panel was tried first and does NOT keep it off full-screen spaces.)
final class RegularDesktopGate {
    private var helper: NSWindow?
    private var action: (() -> Void)?
    private var observer: NSObjectProtocol?

    /// Starts waiting. `action` runs at most once.
    func whenOnRegularDesktop(_ action: @escaping () -> Void) {
        self.action = action
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior = [.managed, .fullScreenNone, .ignoresCycle]
        if let visible = NSScreen.screens.first?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: visible.minX, y: visible.minY))
        }
        window.orderFront(nil) // not key; doesn't activate anything
        helper = window

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // The window server places the helper asynchronously; check on the next turns too.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.check()
        }
    }

    /// Runs the action now (another path already shows the user a regular desktop) and stops.
    func fulfill() {
        guard let action else { return }
        finish()
        action()
    }

    private func check() {
        guard let helper, helper.isOnActiveSpace else { return }
        fulfill()
    }

    private func finish() {
        action = nil
        helper?.orderOut(nil)
        helper = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
