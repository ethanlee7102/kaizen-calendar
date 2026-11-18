import Core

/// The one-time handwritten "Drag me anywhere." on the note after onboarding
/// (spec-onboarding.md, page 3). Decided in the Phase 7 build (user's choice): it shows from
/// Finish until the note is first dragged, its × is clicked, or the day ends, and never again.
/// Kept on this Mac (the app stores it in UserDefaults), like the note's position.
nonisolated public struct DragHint: Codable, Hashable, Sendable {
    /// The day onboarding finished; nil before that.
    public private(set) var shownOn: DayKey?
    /// Dragged or dismissed: never shows again.
    public private(set) var isDone = false

    public init() {}

    public static let text = "Drag me anywhere."

    public func isShowing(today: DayKey) -> Bool { !isDone && shownOn == today }

    /// Onboarding finished: show it today. Only ever once.
    public mutating func start(today: DayKey) {
        guard shownOn == nil, !isDone else { return }
        shownOn = today
    }

    /// The note was dragged, or × clicked. A drag before onboarding finished counts too: it's
    /// pointless to say what the user already did.
    public mutating func finish() { isDone = true }
}
