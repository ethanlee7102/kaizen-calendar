/// How one habit did on one day.
public enum HabitDayStatus: String, Hashable, Sendable, Codable {
    /// Before the habit was created.
    case beforeStart
    /// The habit was inactive (moved to inactive, not yet reactivated).
    case inactive
    /// Active, but not one of its scheduled weekdays.
    case notScheduled
    /// After today.
    case future
    /// Today, scheduled, not done or rested yet.
    case pending
    case done
    /// Rested (today-only, pauses the streak).
    case rest
    /// Missed, and the next scheduled day hasn't recovered it (yet).
    case missed
    /// Missed, then done on the next scheduled (non-rest) day: never missed twice.
    case missedRecovered

    /// Days the habit counted on: scheduled and active.
    public var isScheduled: Bool {
        switch self {
        case .pending, .done, .rest, .missed, .missedRecovered: true
        default: false
        }
    }

    public var isMiss: Bool { self == .missed || self == .missedRecovered }
}

/// What the habit row's handwritten line shows today (spec-collapsed-note.md §4).
public enum RecoveryState: Hashable, Sendable {
    case none
    /// Missed on its last scheduled day, scheduled today, not done or rested yet:
    /// "Never miss twice. Today counts."
    case danger
    /// That miss was recovered today: "Recovered. You didn't miss twice."
    case recovered
    /// Rested today: "Rest day. Streak paused."
    case resting
}

/// Everything computed about one habit, as of `today`. Built in one pass over the habit's
/// scheduled days, so lookups afterwards are cheap.
///
/// Rules (memory/streak-rules.md, journey-vs-streak.md):
/// - Only scheduled days while active count. Rest days are skipped: they pause the streak.
/// - Never miss twice: one miss is forgiven if the next scheduled day is done; two missed
///   scheduled days in a row break the streak (one break per run of misses).
/// - The streak number counts done days since the last break (decided 2026-11-11).
/// - The journey counts done days and never resets.
public struct HabitEvaluation: Sendable {
    public let history: HabitHistory
    public let today: DayKey

    /// Every day the habit counted on from creation through today, in order (scheduled while
    /// active, plus a done deactivation day).
    public let scheduledDays: [DayKey]
    private let statuses: [DayKey: HabitDayStatus]

    /// Current streak: done days since the last break.
    public let currentStreak: Int
    public let longestStreak: Int
    /// Days the streak broke (the second consecutive miss).
    public let breakDays: [DayKey]
    /// Done days in order; the journey is their count.
    public let doneDays: [DayKey]
    /// Done or missed scheduled days, in order (rest and pending excluded).
    public let decidedDays: [DayKey]
    public let recovery: RecoveryState

    public init(history: HabitHistory, today: DayKey) {
        self.history = history
        self.today = today

        var days: [DayKey] = []
        var status: [DayKey: HabitDayStatus] = [:]
        if history.createdDay <= today {
            for day in history.createdDay...today where history.counts(on: day) {
                days.append(day)
                status[day] = if history.completions.contains(day) {
                    .done
                } else if history.rests.contains(day) {
                    .rest
                } else if day == today {
                    .pending
                } else {
                    .missed
                }
            }
        }

        // Resolve recoveries: a single miss (the day before wasn't a miss) whose next non-rest
        // scheduled day is done. A miss in a run of two or more broke the streak instead.
        let counted = days.filter { status[$0] != .rest }
        for (i, day) in counted.enumerated() where status[day] == .missed {
            let isSingle = i == 0 || !status[counted[i - 1]]!.isMiss
            if isSingle, i + 1 < counted.count, status[counted[i + 1]] == .done {
                status[day] = .missedRecovered
            }
        }

        // Streak pass over decided days (today counts only once it's done).
        var streak = 0
        var longest = 0
        var consecutiveMisses = 0
        var breaks: [DayKey] = []
        var done: [DayKey] = []
        for day in counted {
            switch status[day]! {
            case .done:
                streak += 1
                longest = max(longest, streak)
                consecutiveMisses = 0
                done.append(day)
            case .missed, .missedRecovered:
                consecutiveMisses += 1
                if consecutiveMisses == 2 {
                    streak = 0
                    breaks.append(day)
                }
            default:
                break // pending today
            }
        }

        // Today's handwritten line.
        // A miss from before a pause doesn't carry over: after reactivating, it's a fresh start.
        let previous = counted.last { $0 < today }
        let previousIsSingleMiss: Bool = {
            guard let previous, previous >= history.currentPeriodStart, status[previous]!.isMiss else { return false }
            let before = counted.last { $0 < previous }
            return before.map { !status[$0]!.isMiss } ?? true
        }()
        recovery = switch status[today] {
        case .rest: .resting
        case .pending where previousIsSingleMiss: .danger
        case .done where previousIsSingleMiss: .recovered
        default: .none
        }

        scheduledDays = days
        statuses = status
        currentStreak = streak
        longestStreak = longest
        breakDays = breaks
        doneDays = done
        decidedDays = counted.filter { status[$0] != .pending }
    }

    public var id: HabitID { history.id }

    /// Active as of `today` (not as of the real present), so an evaluation for a past day,
    /// such as a report caught up after the Mac was off, sees the habit as it was then:
    /// created by then, and not yet moved to inactive (decided in the Phase 2 build).
    public var isActive: Bool { history.isActive(on: today) }

    public func status(on day: DayKey) -> HabitDayStatus {
        if let known = statuses[day] { return known }
        if day > today { return .future }
        if day < history.createdDay { return .beforeStart }
        if !history.isActive(on: day) { return .inactive }
        return .notScheduled
    }

    /// Never-miss-twice saves: misses that were recovered.
    public var saves: Int { statuses.values.count { $0 == .missedRecovered } }

    public var journey: Journey { Journey(doneDays: doneDays) }

    /// Scheduled today and not yet done or rested (counts toward "X of Y done").
    public var isOpenToday: Bool { status(on: today) == .pending }

    /// The next scheduled weekday after today, for "next: Wed" (spec-edge-states.md).
    public var nextScheduledDay: DayKey? {
        guard isActive else { return nil }
        return (1...7).lazy.map { today.adding(days: $0) }.first { history.isScheduled(on: $0) }
    }

    /// Done ÷ scheduled (rest excluded) over `range`. Today counts only once it's decided.
    public func consistency(in range: DayRange) -> Consistency {
        var done = 0
        var scheduled = 0
        for day in scheduledDays where range.contains(day) {
            switch status(on: day) {
            case .done: done += 1; scheduled += 1
            case .missed, .missedRecovered: scheduled += 1
            default: break
            }
        }
        return Consistency(done: done, scheduled: scheduled)
    }

    /// The last `count` decided scheduled days (done or missed, rest excluded) up to today.
    public func lastDecidedDays(_ count: Int) -> [DayKey] {
        Array(decidedDays.suffix(count))
    }
}

/// Done ÷ scheduled, with rest days excluded from both.
public struct Consistency: Hashable, Sendable, Codable {
    public let done: Int
    public let scheduled: Int

    public init(done: Int, scheduled: Int) {
        self.done = done
        self.scheduled = scheduled
    }

    /// 0...1, or nil when nothing was scheduled.
    public var rate: Double? { scheduled == 0 ? nil : Double(done) / Double(scheduled) }
    /// Rounded percent, or nil when nothing was scheduled.
    public var percent: Int? { rate.map { Int(($0 * 100).rounded()) } }

    public static func + (lhs: Consistency, rhs: Consistency) -> Consistency {
        Consistency(done: lhs.done + rhs.done, scheduled: lhs.scheduled + rhs.scheduled)
    }

    public static let zero = Consistency(done: 0, scheduled: 0)
}
