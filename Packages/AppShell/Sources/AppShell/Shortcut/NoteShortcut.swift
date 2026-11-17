import KeyboardShortcuts
import SwiftUI

/// The optional global keyboard shortcut that expands and collapses the note (spec-settings.md:
/// "Expand/collapse shortcut", default none). Device-local: KeyboardShortcuts keeps it in
/// UserDefaults, like the note position.
public enum NoteShortcut {
    static let name = KeyboardShortcuts.Name("toggleNotebook")

    /// Runs `action` whenever the shortcut is pressed, in any app. Call once at launch.
    public static func onPress(_ action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name, action: action)
    }

    /// The Settings row's recorder: click, then press the shortcut (Delete clears it).
    public static func recorder() -> some View {
        KeyboardShortcuts.Recorder(for: name)
            .accessibilityIdentifier("settings.shortcut")
    }
}
