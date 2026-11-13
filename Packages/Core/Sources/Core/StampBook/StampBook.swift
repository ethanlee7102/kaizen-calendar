/// Cosmetic unlocks in the Stamp book (spec-stamp-book.md). Never feature gates.
public enum Unlock: String, CaseIterable, Hashable, Sendable, Codable {
    /// Unlocked by the first stamp day. Until then the app is light only.
    case darkMode

    /// Stamp days needed. Never shown to the user (unlocks are surprises).
    public var stampsRequired: Int {
        switch self {
        case .darkMode: 1
        }
    }
}

/// Stamp days: days that earned the full vermilion seal, meaning every scheduled habit was
/// done and none was rested (spec-stamp-book.md). The count never resets.
public struct StampBook: Hashable, Sendable {
    /// Stamp days in order.
    public let stampDays: [DayKey]

    public init(stampDays: [DayKey]) { self.stampDays = stampDays }

    /// Scans every day from the first habit's creation through today.
    public init(evaluations: [HabitEvaluation], today: DayKey) {
        guard let first = evaluations.map(\.history.createdDay).min(), first <= today else {
            self.init(stampDays: [])
            return
        }
        self.init(stampDays: (first...today).filter {
            DayMarks.allHabits(on: $0, evaluations: evaluations, today: today) == .fullSeal
        })
    }

    public var count: Int { stampDays.count }

    /// Unlocks earned by the current count that aren't unlocked yet. Unlocks are stored when
    /// earned and never taken back, even if a later edit lowers the count.
    public func newUnlocks(alreadyUnlocked: Set<Unlock>) -> [Unlock] {
        Unlock.allCases.filter { !alreadyUnlocked.contains($0) && count >= $0.stampsRequired }
    }
}
