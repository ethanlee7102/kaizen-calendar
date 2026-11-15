import AppKit

/// The window configurations of the note (`NotePanel`) and the notebook (`NotebookWindow`).
/// LOCKED after the desktop-window prototype and the Phase 3 window probe
/// (memory/desktop-window-findings.md); a test pins them. Don't change these without new research.
public enum NoteWindowMode: Sendable {
    /// The sticky note on the desktop (`NotePanel`).
    case collapsed
    /// The notebook: an ordinary window in front (`NotebookWindow`).
    case expanded

    /// Collapsed: just above the desktop icons, so it's clickable (wallpaper level isn't) and
    /// stays behind every app window. Expanded: a normal window.
    var level: NSWindow.Level {
        switch self {
        case .collapsed: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .expanded: .normal
        }
    }

    /// Collapsed: one desktop only (no `canJoinAllSpaces`: it made the note blink in after
    /// leaving a full-screen app), not arranged by Mission Control, skipped by window cycling.
    /// Expanded: a managed window on the current desktop that never goes over full-screen apps.
    var collectionBehavior: NSWindow.CollectionBehavior {
        switch self {
        case .collapsed: [.stationary, .ignoresCycle]
        case .expanded: [.managed, .fullScreenNone]
        }
    }
}
