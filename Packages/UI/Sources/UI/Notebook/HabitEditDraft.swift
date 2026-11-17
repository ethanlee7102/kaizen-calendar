import Core

/// The Edit form on a habit's page (spec-goals-list.md, goal-creation): name, identity and the
/// schedule. Changes apply from today; past days keep their schedule. The target has its own form
/// (`TargetDraft`), so its history stays a deliberate change. The unit can't be changed: it would
/// relabel every past target ("5 pages" becoming "5 minutes"); measuring something else is a new
/// habit (user's choice after the Phase 5 review).
nonisolated public struct HabitEditDraft: Hashable, Sendable {
    public var name: String
    public var identity: String
    /// Amount habits: shown, not editable.
    public let unit: String
    public var scheduleChoice: HabitDraft.ScheduleChoice
    public var weekdays: WeekdaySet

    public let isAmount: Bool
    private let original: Original

    private struct Original: Hashable, Sendable {
        let name: String
        let identity: String
        let schedule: Schedule
    }

    /// What the repository should save.
    public struct Changes: Hashable, Sendable {
        public let name: String
        public let identity: String?
        /// Nil when the schedule didn't change.
        public let schedule: Schedule?
    }

    public init(habit: NoteHabit, today: DayKey) {
        let history = habit.history
        let schedule = history.schedule(on: today)
        name = habit.name
        identity = habit.identity ?? ""
        if case .amount(let unit) = history.kind {
            self.unit = unit
            isAmount = true
        } else {
            unit = ""
            isAmount = false
        }
        scheduleChoice = schedule.isEveryDay ? .everyDay : .specificDays
        weekdays = schedule.isEveryDay ? [] : schedule.days
        original = Original(name: name, identity: identity, schedule: schedule)
    }

    public var schedule: Schedule? {
        switch scheduleChoice {
        case .everyDay: .everyDay
        case .specificDays: Schedule(days: weekdays)
        }
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The changes to save, or nil while the form is incomplete (no name, no day) or nothing
    /// changed, which disables Save.
    public var changes: Changes? {
        let name = Self.trimmed(name)
        let identity = Self.trimmed(identity)
        guard !name.isEmpty, let schedule else { return nil }
        let changed = name != original.name || identity != Self.trimmed(original.identity)
            || schedule != original.schedule
        guard changed else { return nil }
        return Changes(name: name, identity: identity.isEmpty ? nil : identity,
                       schedule: schedule == original.schedule ? nil : schedule)
    }

    /// Under the name for amount habits: "Measured in pages. To measure something else, start a
    /// new habit."
    public var unitNote: String? {
        isAmount ? "Measured in \(unit). To measure something else, start a new habit." : nil
    }

    /// Shown under the schedule when it would change.
    public var scheduleNote: String? {
        guard let schedule, schedule != original.schedule else { return nil }
        return "The new schedule starts today. Past days keep theirs."
    }
}

/// "Change target" (amount habits): the new amount, from today on. A second change the same day
/// replaces the first (the typo-fix rule in Core).
nonisolated public struct TargetDraft: Hashable, Sendable {
    /// Digits only (the field filters input).
    public var text: String
    public let current: Int
    public let unit: String

    public init(current: Int, unit: String) {
        self.current = current
        self.unit = unit
        text = String(current)
    }

    public var amount: Int? {
        guard let value = Int(text), (1...HabitDraft.maxTarget).contains(value) else { return nil }
        return value
    }

    /// Save is enabled for a valid amount that differs from the current one.
    public var newAmount: Int? { amount.flatMap { $0 == current ? nil : $0 } }

    /// Under the field while it holds 0.
    public var hint: String? { !text.isEmpty && Int(text) == 0 ? "At least 1." : nil }
}

/// "Change schedule" (yes/no habits): the new days, from today on.
nonisolated public struct ScheduleDraft: Hashable, Sendable {
    public var choice: HabitDraft.ScheduleChoice
    public var weekdays: WeekdaySet
    public let current: Schedule

    public init(current: Schedule) {
        self.current = current
        choice = current.isEveryDay ? .everyDay : .specificDays
        weekdays = current.isEveryDay ? [] : current.days
    }

    public var schedule: Schedule? {
        switch choice {
        case .everyDay: .everyDay
        case .specificDays: Schedule(days: weekdays)
        }
    }

    /// Save is enabled for a valid schedule that differs from the current one.
    public var newSchedule: Schedule? { schedule.flatMap { $0 == current ? nil : $0 } }
}
