/// Level-up and level-down suggestions (spec-suggestions.md). Suggestions only: the app
/// never changes a target or schedule on its own.
public enum SuggestionKind: String, Hashable, Sendable, Codable {
    case levelUp, levelDown
}

public enum SuggestedChange: Hashable, Sendable, Codable {
    case target(from: Int, to: Int)
    case schedule(from: Schedule, to: Schedule)
}

public struct Suggestion: Hashable, Sendable, Codable {
    public let habitID: HabitID
    public let kind: SuggestionKind
    public let change: SuggestedChange
}

/// A "Not now" on a suggestion.
public struct SuggestionDismissal: Hashable, Sendable, Codable {
    public let kind: SuggestionKind
    public let day: DayKey

    public init(kind: SuggestionKind, day: DayKey) {
        self.kind = kind
        self.day = day
    }
}

public enum Suggestions {
    /// Scheduled days (rest excluded) that must pass after any change, after a "Not now",
    /// and that the level-up and consistency checks look back over.
    public static let windowDays = 14
    public static let levelUpThreshold = 0.9
    public static let levelDownThreshold = 0.6
    /// "2 streak breaks within 3 weeks."
    public static let breakLookbackDays = 21

    /// The suggestion for a habit today, if any. Level-down wins over level-up.
    public static func suggestion(for evaluation: HabitEvaluation,
                                  dismissals: [SuggestionDismissal] = []) -> Suggestion? {
        let history = evaluation.history
        let today = evaluation.today
        // At least 14 days old (today counts as a day of the habit's life).
        guard evaluation.isActive,
              history.createdDay.days(to: today) + 1 >= windowDays else { return nil }

        let decided = evaluation.decidedDays
        // No suggestions in the 14 scheduled days after any target or schedule change.
        guard decided.count(where: { $0 >= history.lastChangeDay }) >= windowDays else { return nil }

        let window = Array(decided.suffix(windowDays))
        let doneInWindow = window.count { evaluation.status(on: $0) == .done }
        let rate = Double(doneInWindow) / Double(window.count)
        // Breaks before the last change were already answered by that change.
        let recentBreaks = evaluation.breakDays.count {
            $0 >= history.lastChangeDay && $0.days(to: today) < breakLookbackDays
        }

        // "Not now" hides a kind until 14 more scheduled days pass after the dismissal day.
        func isSnoozed(_ kind: SuggestionKind) -> Bool {
            guard let last = dismissals.filter({ $0.kind == kind }).map(\.day).max() else { return false }
            return decided.count { $0 > last } < windowDays
        }

        if rate < levelDownThreshold || recentBreaks >= 2, !isSnoozed(.levelDown),
           let change = levelDownChange(for: evaluation) {
            return Suggestion(habitID: history.id, kind: .levelDown, change: change)
        }
        let hasStreakBreakingMiss = window.contains { evaluation.status(on: $0) == .missed }
        if rate >= levelUpThreshold, !hasStreakBreakingMiss, !isSnoozed(.levelUp),
           let change = levelUpChange(for: evaluation) {
            return Suggestion(habitID: history.id, kind: .levelUp, change: change)
        }
        return nil
    }

    // MARK: Sizes

    /// About +10%, rounded, at least +1 (10 → 11, 12 → 13, 5 → 6).
    public static func raisedTarget(_ amount: Int) -> Int {
        amount + max(1, Int((Double(amount) * 0.1).rounded()))
    }

    /// About −25%, rounded, at least −1, never below 1. Nil when already at 1.
    public static func loweredTarget(_ amount: Int) -> Int? {
        guard amount > 1 else { return nil }
        return max(1, amount - max(1, Int((Double(amount) * 0.25).rounded())))
    }

    /// Yes/no habits on every day drop to this many days a week.
    public static let everyDayLevelDownDays = 5

    static func levelUpChange(for evaluation: HabitEvaluation) -> SuggestedChange? {
        let history = evaluation.history
        let today = evaluation.today
        switch history.kind {
        case .amount:
            let current = history.target(on: today)!
            return .target(from: current, to: raisedTarget(current))
        case .yesNo:
            let current = history.schedule(on: today)
            guard !current.isEveryDay else { return nil } // nothing to raise
            let added = dayToAdd(to: current.days)
            return .schedule(from: current, to: Schedule(days: current.days.union(WeekdaySet(added)))!)
        }
    }

    static func levelDownChange(for evaluation: HabitEvaluation) -> SuggestedChange? {
        let history = evaluation.history
        let today = evaluation.today
        switch history.kind {
        case .amount:
            let current = history.target(on: today)!
            return loweredTarget(current).map { .target(from: current, to: $0) }
        case .yesNo:
            let current = history.schedule(on: today)
            let removeCount = current.isEveryDay ? 7 - everyDayLevelDownDays : 1
            guard current.daysPerWeek - removeCount >= 1 else { return nil }
            var days = current.days
            for weekday in daysToRemove(from: current.days, count: removeCount, evaluation: evaluation) {
                days.remove(WeekdaySet(weekday))
            }
            return .schedule(from: current, to: Schedule(days: days)!)
        }
    }

    /// The unscheduled weekday that spreads the schedule most evenly (farthest from any
    /// scheduled day, counting around the week); ties go to the earliest in the week.
    static func dayToAdd(to days: WeekdaySet) -> Weekday {
        func gap(_ a: Weekday, _ b: Weekday) -> Int {
            let diff = abs(a.rawValue - b.rawValue)
            return min(diff, 7 - diff)
        }
        let candidates = Weekday.allCases.filter { !days.contains($0) }
        return candidates.max { a, b in
            let ga = days.weekdays.map { gap(a, $0) }.min()!
            let gb = days.weekdays.map { gap(b, $0) }.min()!
            return ga != gb ? ga < gb : a > b
        }!
    }

    /// The scheduled weekdays missed most often over the last 8 weeks (56 days including
    /// today); ties go to the latest in the week.
    static func daysToRemove(from days: WeekdaySet, count: Int, evaluation: HabitEvaluation) -> [Weekday] {
        let since = evaluation.today.adding(days: -55)
        var missRate: [Weekday: Double] = [:]
        for weekday in days.weekdays {
            let decided = evaluation.decidedDays.filter { $0 >= since && $0.weekday == weekday }
            let misses = decided.count { evaluation.status(on: $0).isMiss }
            missRate[weekday] = decided.isEmpty ? 0 : Double(misses) / Double(decided.count)
        }
        return days.weekdays
            .sorted { a, b in missRate[a]! != missRate[b]! ? missRate[a]! > missRate[b]! : a > b }
            .prefix(count)
            .sorted()
    }
}
