import AppKit

/// The collapsed sticky note on the desktop: a borderless, non-activating panel.
///
/// Non-activating, so clicking the note (a check-off) works on the first click without taking
/// focus from the app you're in (prototype checklist #2). macOS fixes that at creation; it can't
/// be turned off later with public API (Phase 3 research), which is why the notebook is a separate
/// ordinary window (`NotebookWindow`).
final class NotePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = false
        hidesOnDeactivate = false
        // Hide (⌘H) never hides the note: it lives on the desktop. Showing it again after a
        // hide could put it on whichever desktop is active then (desktop-window-findings.md).
        canHide = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Buttons and check-offs don't take keyboard focus from other apps; text fields can.
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // The controller restores the note's position itself. macOS window restoration would
        // only add a "reopen windows?" alert after a crash, which blocks launch.
        isRestorable = false
        level = NoteWindowMode.collapsed.level
        collectionBehavior = NoteWindowMode.collapsed.collectionBehavior
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The expanded notebook: an ordinary window (title bar hidden), so clicking it activates
/// 66 Days the normal way, and macOS never places it on another app's full-screen space
/// (both confirmed by the Phase 3 window probe).
final class NotebookWindow: NSWindow {
    /// Esc or Close (⌘W): the controller folds the notebook back into the note.
    var onClose: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // The content draws the whole notebook (paper, corners); the window itself is clear, so
        // no system background shows in the title bar strip or around the corners.
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
        level = NoteWindowMode.expanded.level
        collectionBehavior = NoteWindowMode.expanded.collectionBehavior
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func performClose(_ sender: Any?) {
        onClose?()
    }
}
