/// One habit's slice of a day's seal.
public struct SealSlice: Hashable, Sendable {
    public let habitID: HabitID
    public let status: HabitDayStatus
    /// Done slices are inked; rested, missed and pending ones aren't.
    public var isInked: Bool { status == .done }
}

/// A day's mark in the all-habits calendar (spec-collapsed-note.md §3).
public enum AllHabitsMark: Hashable, Sendable {
    /// Every scheduled habit done, none rested: the full vermilion seal. This is a stamp day.
    case fullSeal
    /// Some done (or today, in progress): one slice per scheduled habit, in habit order.
    case slicedSeal([SealSlice])
    /// A past day with scheduled habits and none done.
    case pencilCircle
    /// Every scheduled habit was rested.
    case restDash
    /// Nothing scheduled (or before any habit started): a faint number.
    case faint
    case future
}

/// A day's mark when the calendar is filtered to one habit (spec-collapsed-note.md §3).
public enum SingleHabitMark: Hashable, Sendable {
    case fullSeal
    /// Missed, then recovered: the gold seam.
    case goldSeam
    case pencilCircle
    case restDash
    /// Today, not done yet: indigo bold number.
    case todayPending
    case faint
    case future
}

public enum DayMarks {
    /// The all-habits mark for `day`. `evaluations` must be in habit order (sets slice order).
    /// Only habits active that day count, so inactive habits keep their past seals
    /// (spec-goals-list.md).
    public static func allHabits(on day: DayKey, evaluations: [HabitEvaluation], today: DayKey) -> AllHabitsMark {
        if day > today { return .future }
        let slices = evaluations.compactMap { evaluation -> SealSlice? in
            let status = evaluation.status(on: day)
            return status.isScheduled ? SealSlice(habitID: evaluation.id, status: status) : nil
        }
        if slices.isEmpty { return .faint }
        if slices.allSatisfy({ $0.status == .done }) { return .fullSeal }
        if slices.allSatisfy({ $0.status == .rest }) { return .restDash }
        if day == today || slices.contains(where: \.isInked) { return .slicedSeal(slices) }
        return .pencilCircle
    }

    public static func singleHabit(on day: DayKey, evaluation: HabitEvaluation) -> SingleHabitMark {
        switch evaluation.status(on: day) {
        case .done: .fullSeal
        case .missedRecovered: .goldSeam
        case .missed: .pencilCircle
        case .rest: .restDash
        case .pending: .todayPending
        case .future: .future
        case .beforeStart, .inactive, .notScheduled: .faint
        }
    }
}

/// "Today · X of Y done" (spec-collapsed-note.md §2). Rested and unscheduled habits don't
/// count toward Y.
public struct TodayProgress: Hashable, Sendable {
    public let done: Int
    public let total: Int
    /// At least one habit was rested today.
    public let anyRested: Bool

    public init(evaluations: [HabitEvaluation], today: DayKey) {
        var done = 0
        var total = 0
        var rested = false
        for evaluation in evaluations {
            switch evaluation.status(on: today) {
            case .done: done += 1; total += 1
            case .pending: total += 1
            case .rest: rested = true
            default: break
            }
        }
        self.done = done
        self.total = total
        anyRested = rested
    }

    /// Nothing is scheduled today: "Nothing scheduled today."
    public var nothingScheduled: Bool { total == 0 && !anyRested }
    /// Every scheduled habit is done or rested: "All done", and the daily note line appears.
    public var allDone: Bool { !nothingScheduled && done == total }
}
