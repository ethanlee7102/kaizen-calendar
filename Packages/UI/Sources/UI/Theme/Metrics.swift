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
    /// The notebook's page; the divider tabs stick out to its right (mockup Expanded.dc.html).
    public static let notebookPageWidth: CGFloat = 770
    public static let notebookTabWidth: CGFloat = 118
    /// Cards over the notebook's page (day card, forms, confirmations).
    public static let notebookCardWidth: CGFloat = 380
}
