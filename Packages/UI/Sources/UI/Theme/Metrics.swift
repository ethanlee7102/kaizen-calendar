import CoreGraphics

/// Layout numbers from the specs, kept in one place.
nonisolated public enum Metrics {
    // Collapsed note (spec-collapsed-note.md §2).
    public static let noteWidth: CGFloat = 300
    public static let noteCornerRadius: CGFloat = 14
    public static let notePadding: CGFloat = 18
    public static let dotGridSpacing: CGFloat = 14
    public static let filterLineHeight: CGFloat = 22
    public static let gridRowHeight: CGFloat = 32
    public static let habitRowMinHeight: CGFloat = 44
    public static let leafButtonSize: CGFloat = 40

    // Paper cards: day card, forms (spec-collapsed-note.md §6).
    public static let cardCornerRadius: CGFloat = 12

    // Expanded notebook window (spec-expanded-structure.md).
    public static let expandedSize = CGSize(width: 880, height: 620)
}
