/// Decides when a user's drag of the collapsed note is saved. Pure, so it's unit-tested.
///
/// Only the user's drags choose a position (desktop-window-findings.md). A drag starts with a
/// move while the left button is held. The last move can arrive after the button is released,
/// so the spot is saved once the moves have settled and the button is up; a drag paused with
/// the button still held waits for the release. After the save, moves by the system (a display
/// unplugged, a resolution change) are never saved.
nonisolated public struct DragSaveTracker: Equatable, Sendable {
    /// True from the first move of a user drag until its spot is saved.
    public private(set) var isDragging = false

    public init() {}

    /// The panel moved. Returns true when a settle check should be (re)scheduled.
    public mutating func moved(buttonDown: Bool) -> Bool {
        if buttonDown { isDragging = true }
        return isDragging
    }

    public enum Settled: Equatable, Sendable {
        /// Save the panel's frame now; the drag is over.
        case save
        /// The button is still held: check again later (no save yet).
        case waitForRelease
        /// No drag in progress.
        case nothing
    }

    /// The moves have settled.
    public mutating func settled(buttonDown: Bool) -> Settled {
        guard isDragging else { return .nothing }
        if buttonDown { return .waitForRelease }
        isDragging = false
        return .save
    }

    /// Ends a drag right away and says whether its spot should be saved (the notebook opens
    /// mid-drag).
    public mutating func finish() -> Bool {
        defer { isDragging = false }
        return isDragging
    }
}
