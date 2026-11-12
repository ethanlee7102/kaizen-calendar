import Foundation

public struct HabitID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }
}

/// "Track an amount" (a numeric target such as 10 pages) or "Just do it" (yes/no).
public enum HabitKind: Hashable, Sendable, Codable {
    case amount(unit: String)
    case yesNo
}

/// Why a target or schedule changed (shown in "How far you've come").
public enum ChangeSource: String, Hashable, Sendable, Codable {
    case initial, suggested, manual
}

public struct TargetChange: Hashable, Sendable, Codable {
    public let day: DayKey
    public let amount: Int
    public let source: ChangeSource

    public init(day: DayKey, amount: Int, source: ChangeSource) {
        precondition(amount >= 1, "Targets are at least 1")
        self.day = day
        self.amount = amount
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case day, amount, source }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amount = try container.decode(Int.self, forKey: .amount)
        guard amount >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container,
                                                   debugDescription: "Targets are at least 1")
        }
        self.init(day: try container.decode(DayKey.self, forKey: .day), amount: amount,
                  source: try container.decode(ChangeSource.self, forKey: .source))
    }
}

public struct ScheduleChange: Hashable, Sendable, Codable {
    public let day: DayKey
    public let schedule: Schedule
    public let source: ChangeSource

    public init(day: DayKey, schedule: Schedule, source: ChangeSource) {
        self.day = day
        self.schedule = schedule
        self.source = source
    }
}

public enum InactiveReason: String, Hashable, Sendable, Codable {
    /// Passed the day-66 automaticity check ("Graduated ✓66").
    case graduated
    /// Moved to inactive any other way.
    case paused
}

/// A stretch of days when the habit was active. `end` is the day it was moved to inactive
/// (nil while still active). The end day itself counts only if the habit was already done
/// that day (see `HabitHistory.counts(on:)`).
public struct ActivePeriod: Hashable, Sendable, Codable {
    public let start: DayKey
    public let end: DayKey?
    public let endReason: InactiveReason?

    public init(start: DayKey, end: DayKey? = nil, endReason: InactiveReason? = nil) {
        precondition(end.map { $0 >= start } ?? true, "An active period can't end before it starts")
        self.start = start
        self.end = end
        self.endReason = endReason
    }

    /// Fully active on `day` (the end day is not).
    public func contains(_ day: DayKey) -> Bool {
        day >= start && end.map { day < $0 } ?? true
    }
}

/// Everything stored about one habit: facts only. Streaks, journey, consistency and
/// suggestions are all computed from this (D5 in research/technical-decisions.md).
///
/// Check-offs and rests are changed through `setDone(_:on:)` and `setRested(_:on:)`, which
/// keep them consistent. Who may change which day (the 2-day edit window, rest only today and
/// not on a danger day) is decided by `EditRules`, which callers check first.
public struct HabitHistory: Hashable, Sendable {
    public enum InvalidData: Error, Hashable, Sendable {
        case noSchedule
        case amountHabitWithoutTarget
        case noActivePeriod
        case firstPeriodNotOnCreatedDay
        case periodsOverlapOrOpenInMiddle
        case changeBeforeCreation
    }

    public let id: HabitID
    public var kind: HabitKind
    /// Habits always start the day they're created (no backdating).
    public let createdDay: DayKey
    /// Sorted by day; the first one is the initial schedule on `createdDay`.
    public private(set) var scheduleChanges: [ScheduleChange]
    /// Sorted by day; empty for yes/no habits.
    public private(set) var targetChanges: [TargetChange]
    /// Sorted, non-overlapping; the first starts on `createdDay`; only the last may be open.
    public private(set) var activePeriods: [ActivePeriod]
    public internal(set) var completions: Set<DayKey>
    public internal(set) var rests: Set<DayKey>

    /// Builds a habit from stored facts, rejecting data that can't be right (e.g. a corrupt
    /// database row) instead of crashing later.
    public init(
        id: HabitID = HabitID(),
        kind: HabitKind,
        createdDay: DayKey,
        scheduleChanges: [ScheduleChange],
        targetChanges: [TargetChange] = [],
        activePeriods: [ActivePeriod]? = nil,
        completions: Set<DayKey> = [],
        rests: Set<DayKey> = []
    ) throws(InvalidData) {
        let schedules = scheduleChanges.sorted { $0.day < $1.day }
        let targets = targetChanges.sorted { $0.day < $1.day }
        let periods = (activePeriods ?? [ActivePeriod(start: createdDay)]).sorted { $0.start < $1.start }

        guard !schedules.isEmpty else { throw .noSchedule }
        if case .amount = kind, targets.isEmpty { throw .amountHabitWithoutTarget }
        guard let first = periods.first else { throw .noActivePeriod }
        guard first.start == createdDay else { throw .firstPeriodNotOnCreatedDay }
        for (a, b) in zip(periods, periods.dropFirst()) {
            guard let end = a.end, end <= b.start else { throw .periodsOverlapOrOpenInMiddle }
        }
        guard schedules[0].day >= createdDay, targets.first.map({ $0.day >= createdDay }) ?? true else {
            throw .changeBeforeCreation
        }

        self.id = id
        self.kind = kind
        self.createdDay = createdDay
        self.scheduleChanges = schedules
        self.targetChanges = targets
        self.activePeriods = periods
        self.completions = completions
        self.rests = rests.subtracting(completions) // a done day isn't also a rest day
    }

    /// A new habit, created today with its first schedule (and target, for amount habits).
    public static func new(
        id: HabitID = HabitID(),
        kind: HabitKind,
        target: Int? = nil,
        schedule: Schedule,
        on day: DayKey
    ) -> HabitHistory {
        if case .amount = kind { precondition(target != nil, "An amount habit needs a target") }
        // Valid by construction.
        return try! HabitHistory(
            id: id, kind: kind, createdDay: day,
            scheduleChanges: [ScheduleChange(day: day, schedule: schedule, source: .initial)],
            targetChanges: target.map { [TargetChange(day: day, amount: $0, source: .initial)] } ?? []
        )
    }

    // MARK: Lookups

    public func schedule(on day: DayKey) -> Schedule {
        (scheduleChanges.last { $0.day <= day } ?? scheduleChanges[0]).schedule
    }

    public func target(on day: DayKey) -> Int? {
        (targetChanges.last { $0.day <= day } ?? targetChanges.first)?.amount
    }

    public func isActive(on day: DayKey) -> Bool {
        day >= createdDay && activePeriods.contains { $0.contains(day) }
    }

    public var isActiveNow: Bool { activePeriods.last?.end == nil }

    /// The current (or last) active period's start.
    public var currentPeriodStart: DayKey { activePeriods.last!.start }

    /// Scheduled and active: a day the habit counts on.
    public func isScheduled(on day: DayKey) -> Bool {
        isActive(on: day) && schedule(on: day).includes(day)
    }

    /// Whether `day` counts for this habit: scheduled while active, or the day it was moved
    /// to inactive if it was already done that day (so graduating on day 66 keeps day 66).
    public func counts(on day: DayKey) -> Bool {
        if isScheduled(on: day) { return true }
        return completions.contains(day) && schedule(on: day).includes(day)
            && activePeriods.contains { $0.end == day && $0.start <= day }
    }

    /// The last day a change to the target or schedule took effect.
    public var lastChangeDay: DayKey {
        max(scheduleChanges.last!.day, targetChanges.last?.day ?? createdDay)
    }

    // MARK: Check-offs and rests

    /// Checks the habit off (or unchecks it) on `day`. Checking off clears a rest.
    public mutating func setDone(_ done: Bool, on day: DayKey) {
        if done {
            completions.insert(day)
            rests.remove(day)
        } else {
            completions.remove(day)
        }
    }

    /// Marks (or unmarks) a rest on `day`. A done day can't be rested.
    public mutating func setRested(_ rested: Bool, on day: DayKey) {
        if rested {
            guard !completions.contains(day) else { return }
            rests.insert(day)
        } else {
            rests.remove(day)
        }
    }

    // MARK: Recording changes

    /// Records a target change from `day` on. A second change on the same day replaces the
    /// first instead of adding a history entry (a same-day typo fix, memory/goal-levels.md).
    /// If `day` is before the last change (the date moved backwards, e.g. flying west across
    /// the date line), it's treated as the same day as that change.
    public mutating func changeTarget(to amount: Int, on day: DayKey, source: ChangeSource) {
        let day = max(day, targetChanges.last?.day ?? createdDay)
        if let last = targetChanges.last, last.day == day {
            targetChanges.removeLast()
            // A same-day fix of the initial target stays the initial target.
            let kept: ChangeSource = last.source == .initial ? .initial : source
            if targetChanges.last?.amount != amount {
                targetChanges.append(TargetChange(day: day, amount: amount, source: kept))
            }
        } else if targetChanges.last?.amount != amount {
            targetChanges.append(TargetChange(day: day, amount: amount, source: source))
        }
    }

    /// Records a schedule change from `day` on; same-day changes replace each other.
    /// A `day` before the last change is treated as that day (see `changeTarget`).
    public mutating func changeSchedule(to schedule: Schedule, on day: DayKey, source: ChangeSource) {
        let day = max(day, scheduleChanges.last!.day)
        if let last = scheduleChanges.last, last.day == day {
            scheduleChanges.removeLast()
            let kept: ChangeSource = last.source == .initial ? .initial : source
            if scheduleChanges.last?.schedule != schedule {
                scheduleChanges.append(ScheduleChange(day: day, schedule: schedule, source: kept))
            }
        } else if scheduleChanges.last?.schedule != schedule {
            scheduleChanges.append(ScheduleChange(day: day, schedule: schedule, source: source))
        }
    }

    /// Moves the habit to inactive from `day` on. That day still counts if it was already done.
    public mutating func deactivate(on day: DayKey, reason: InactiveReason) {
        guard let last = activePeriods.last, last.end == nil else { return }
        activePeriods[activePeriods.count - 1] = ActivePeriod(start: last.start, end: max(day, last.start),
                                                              endReason: reason)
    }

    /// Brings the habit back from `day` on. Streak and journey continue where they left off.
    public mutating func reactivate(on day: DayKey) {
        guard let last = activePeriods.last, let end = last.end else { return }
        if day <= end {
            // Deactivated and reactivated the same day: as if it never left.
            activePeriods[activePeriods.count - 1] = ActivePeriod(start: last.start)
        } else {
            activePeriods.append(ActivePeriod(start: day))
        }
    }
}
