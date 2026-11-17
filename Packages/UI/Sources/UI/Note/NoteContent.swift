import Core

// What the collapsed note shows, worked out from Core values with no SwiftUI involved, so every
// rule and every line of copy here is unit-tested (spec-collapsed-note.md §2–§4, §6–§8,
// spec-edge-states.md). The views only draw it.

/// One habit as the note sees it.
nonisolated public struct NoteHabit: Sendable, Identifiable {
    public let name: String
    /// The optional "I'm ___" line.
    public let identity: String?
    public let evaluation: HabitEvaluation

    public init(name: String, identity: String?, evaluation: HabitEvaluation) {
        self.name = name
        self.identity = identity
        self.evaluation = evaluation
    }

    public var id: HabitID { evaluation.id }
    var history: HabitHistory { evaluation.history }
}

/// Everything the note needs to draw itself.
nonisolated public struct NoteInput: Sendable {
    public var today: DayKey
    /// Every readable habit, active and inactive, in list order (inactive ones keep their past
    /// seals and slices).
    public var habits: [NoteHabit]
    /// Daily notes by day.
    public var notes: [DayKey: String]
    /// The one-time "Welcome back" note is waiting to be dismissed.
    public var showsWelcomeBack: Bool
    /// "You found something: Dark mode." right after an unlock, until dismissed (spec-stamp-book.md).
    public var unlockNotice: UnlockNotice?
    /// A letter is waiting: the sealed envelope in the header (spec-reports.md).
    public var envelope: NoteEnvelope?
    /// Milestone cards (100 / 254 / 365) already dismissed.
    public var milestonesSeen: [HabitID: Set<Int>]

    public init(today: DayKey, habits: [NoteHabit], notes: [DayKey: String] = [:], showsWelcomeBack: Bool = false,
                unlockNotice: UnlockNotice? = nil, envelope: NoteEnvelope? = nil, milestonesSeen: [HabitID: Set<Int>] = [:]) {
        self.today = today
        self.habits = habits
        self.notes = notes
        self.showsWelcomeBack = showsWelcomeBack
        self.unlockNotice = unlockNotice
        self.envelope = envelope
        self.milestonesSeen = milestonesSeen
    }

    /// The note's rows: habits with an open active period (the repository's rule).
    public var activeHabits: [NoteHabit] { habits.filter(\.history.isActiveNow) }
    public var hasInactiveHabits: Bool { habits.contains { !$0.history.isActiveNow } }
    public func habit(_ id: HabitID) -> NoteHabit? { habits.first { $0.id == id } }

    public var grid: MonthGrid { MonthGrid(containing: today) }
    public var progress: TodayProgress { TodayProgress(evaluations: activeHabits.map(\.evaluation), today: today) }
    public var addHabitState: HabitRules.AddHabitState { HabitRules.addHabitState(activeCount: activeHabits.count) }

    /// The month name in the header, e.g. "November".
    public var monthTitle: String { DayText.monthName(today.month) }
    public var yearTitle: String { String(today.year) }
}

// MARK: - Month grid

/// One day in the month grid.
nonisolated public struct NoteCell: Hashable, Sendable, Identifiable {
    public let day: DayKey
    public let mark: DayCellMark
    public let isToday: Bool
    /// Past days and today open the day card; future days are disabled.
    public let opensDayCard: Bool
    /// The hover text, e.g. "Nov 4 — Read: done · Meditate: missed (recovered)". Nil when the
    /// day has nothing to tell.
    public let tooltip: String?
    public let accessibilityLabel: String

    public var id: DayKey { day }
}

nonisolated public extension NoteInput {
    /// A cell of the grid, in all-habits view or filtered to `filter`.
    func cell(for day: DayKey, filter: HabitID?) -> NoteCell {
        let filtered = filter.flatMap(habit)
        let mark: DayCellMark = if let filtered {
            DayCellMark(DayMarks.singleHabit(on: day, evaluation: filtered.evaluation))
        } else {
            DayCellMark(DayMarks.allHabits(on: day, evaluations: habits.map(\.evaluation), today: today))
        }
        let statuses = (filtered.map { [$0] } ?? habits).compactMap { habit -> String? in
            let status = habit.evaluation.status(on: day)
            return status.isScheduled ? "\(habit.name): \(DayText.tooltipWord(status))" : nil
        }
        let note = notes[day].map { "“\($0)”" }
        let details = (statuses.isEmpty ? [] : [statuses.joined(separator: " · ")]) + (note.map { [$0] } ?? [])
        let date = DayText.shortDate(day)
        let tooltip = day > today || details.isEmpty ? nil : "\(date) — \(details.joined(separator: " "))"

        var label = DayText.longDate(day)
        if day == today { label += ", today" }
        if let summary = DayText.markSummary(mark) { label += ": \(summary)" }
        if day <= today, !details.isEmpty { label += ". \(details.joined(separator: " "))" }
        return NoteCell(day: day, mark: mark, isToday: day == today, opensDayCard: day <= today,
                        tooltip: tooltip, accessibilityLabel: label)
    }
}

// MARK: - Today line

nonisolated public struct TodayLine: Hashable, Sendable {
    /// "Mon, Nov 9 · 1 of 3 done", "Mon, Nov 9 · All done", or just the date.
    public let summary: String
    /// Handwritten under Today: "Nothing scheduled today." (spec-edge-states.md).
    public let nothingScheduled: Bool
}

nonisolated public extension NoteInput {
    var todayLine: TodayLine {
        let date = DayText.weekdayDate(today)
        let progress = progress
        if activeHabits.isEmpty { return TodayLine(summary: date, nothingScheduled: false) }
        if progress.nothingScheduled { return TodayLine(summary: date, nothingScheduled: true) }
        let count = progress.allDone ? "All done" : "\(progress.done) of \(progress.total) done"
        return TodayLine(summary: "\(date) · \(count)", nothingScheduled: false)
    }

    /// The daily note line shows once every scheduled habit is done or rested (§7).
    var showsDailyNoteLine: Bool { !activeHabits.isEmpty && progress.allDone }
}

// MARK: - Habit rows

/// The handwritten third line of a habit row (§4).
nonisolated public enum RowLine: Hashable, Sendable {
    /// "Never miss twice. Today counts."
    case danger
    /// "Recovered. You didn't miss twice."
    case recovered
    /// "Rest day. Streak paused."
    case resting

    public var text: String {
        switch self {
        case .danger: "Never miss twice. Today counts."
        case .recovered: "Recovered. You didn’t miss twice."
        case .resting: "Rest day. Streak paused."
        }
    }
}

nonisolated public struct NoteRow: Sendable, Identifiable {
    public enum Check: Hashable, Sendable {
        /// The leaf button.
        case leaf(LeafState)
        /// Not scheduled today: "next: Wed" instead of a leaf (these rows sit in the folded
        /// "Not scheduled today" section). Nil: no scheduled day ahead (shouldn't happen while active).
        case next(String?)
    }

    public let id: HabitID
    public let name: String
    /// "10 pages · 5-day streak", "starts today", "starts Mon", …
    public let subtitle: String
    public let line: RowLine?
    public let check: Check
    /// Clicking the leaf checks it off, or unchecks it when done. False when not scheduled today.
    public let canToggle: Bool
    public let isDone: Bool
    public let journey: Journey
    /// Scheduled today (open, done or rested): a row in the main list. Otherwise it's in the
    /// folded "Not scheduled today" section (user's request, 2026-11-15).
    public let isScheduledToday: Bool
}

nonisolated public extension NoteInput {
    /// Today's habits: the main list.
    var scheduledRows: [NoteRow] { rows.filter(\.isScheduledToday) }
    /// Habits not scheduled today: the folded section under the main list.
    var unscheduledRows: [NoteRow] { rows.filter { !$0.isScheduledToday } }

    /// Every active habit's row, in list order.
    var rows: [NoteRow] {
        activeHabits.map { habit in
            let evaluation = habit.evaluation
            let status = evaluation.status(on: today)
            let line: RowLine? = switch evaluation.recovery {
            case .danger: .danger
            case .recovered: .recovered
            case .resting: .resting
            case .none: nil
            }
            let check: NoteRow.Check = switch status {
            case .done: .leaf(.checked)
            case .pending: .leaf(.unchecked)
            case .rest: .leaf(.rested)
            default: .next(Self.nextDay(of: habit.history, after: today).map { "next: \($0.weekday.shortName)" })
            }
            let scheduled = [.pending, .done, .rest].contains(status)
            return NoteRow(id: habit.id, name: habit.name, subtitle: Self.subtitle(of: habit, today: today),
                           line: line, check: check, canToggle: scheduled, isDone: status == .done,
                           journey: evaluation.journey, isScheduledToday: scheduled)
        }
    }

    /// The next day after `today` the habit is scheduled. Not Core's `nextScheduledDay`: that one
    /// is empty for a habit that isn't active *as of today*, such as one created "tomorrow" after
    /// today moved backwards, which is still a row on the note (Phase 4 review).
    static func nextDay(of history: HabitHistory, after today: DayKey) -> DayKey? {
        (1...7).lazy.map { today.adding(days: $0) }.first { history.isScheduled(on: $0) }
    }

    /// The row's second line (§2.7): `[target] · [N]-day streak`, with the new-habit and
    /// not-scheduled variants.
    static func subtitle(of habit: NoteHabit, today: DayKey) -> String {
        let evaluation = habit.evaluation
        let lead = DayText.lead(of: habit.history, on: today)
        let tail: String = switch evaluation.status(on: today) {
        // In the "Not scheduled today" section, so it doesn't say so again: the streak, or when a
        // new habit starts.
        case .notScheduled where evaluation.decidedDays.isEmpty:
            Self.nextDay(of: habit.history, after: today).map { day in
                day == today.adding(days: 1) ? "starts tomorrow" : "starts \(day.weekday.shortName)"
            } ?? "\(evaluation.currentStreak)-day streak"
        // Created "tomorrow": today moved backwards (a later day-end time, flying west).
        case .beforeStart:
            habit.history.createdDay == today.adding(days: 1)
                ? "starts tomorrow" : "starts \(DayText.weekdayDate(habit.history.createdDay))"
        // Before its first decided day (nothing done or missed yet): it starts today.
        case .pending where evaluation.decidedDays.isEmpty: "starts today"
        default: "\(evaluation.currentStreak)-day streak"
        }
        return ([lead, tail].compactMap { $0 }).joined(separator: " · ")
    }
}

// MARK: - Day card

nonisolated public struct DayCard: Sendable {
    public enum RestAction: Hashable, Sendable {
        /// "Rest today"
        case rest
        /// "Undo rest"
        case undoRest
    }

    public struct Row: Sendable, Identifiable {
        public let id: HabitID
        public let name: String
        public let leaf: LeafState
        public let isDone: Bool
        /// Done / Missed / Missed, then recovered / Rest day / Not yet
        public let status: String
        /// False for inactive habits: they're read-only until reactivated (spec-goals-list.md).
        public let isChangeable: Bool
        public let restAction: RestAction?
    }

    public let day: DayKey
    /// "Sun, Nov 8", or "Mon, Nov 9 · Today".
    public let title: String
    public let access: EditRules.DayAccess
    public let rows: [Row]
    public let note: String
}

nonisolated public extension NoteInput {
    /// The day card for `day`: one row per habit that counted that day, in list order.
    func dayCard(for day: DayKey) -> DayCard {
        let rows = habits.compactMap { habit -> DayCard.Row? in
            let evaluation = habit.evaluation
            let status = evaluation.status(on: day)
            guard status.isScheduled else { return nil }
            let changeable = habit.history.isActiveNow
            var rest: DayCard.RestAction?
            if changeable, day == today {
                if status == .rest { rest = .undoRest } else if EditRules.canRest(evaluation, on: day) { rest = .rest }
            }
            let leaf: LeafState = switch status {
            case .done: .checked
            case .rest: .rested
            default: .unchecked
            }
            return DayCard.Row(id: habit.id, name: habit.name, leaf: leaf, isDone: status == .done,
                               status: DayText.cardStatus(status), isChangeable: changeable, restAction: rest)
        }
        let title = DayText.weekdayDate(day) + (day == today ? " · Today" : "")
        return DayCard(day: day, title: title, access: EditRules.access(to: day, today: today), rows: rows,
                       note: notes[day] ?? "")
    }
}

/// Whether an open day card can be changed (spec-collapsed-note.md §6). Today and the 2 days
/// before are editable; older days need "Change anyway". A card opened as editable stays editable
/// until it's closed, even if midnight moves its day out of the window while you type (user's
/// choice after the Phase 4 review): its writes then go through as "change anyway".
nonisolated public struct DayCardEditing: Hashable, Sendable {
    /// The card's day was editable when it opened.
    public let openedEditable: Bool
    /// The user confirmed "Change anyway".
    public var unlocked = false

    public init(openedAs access: EditRules.DayAccess) { openedEditable = access == .editable }

    public func isEditable(now access: EditRules.DayAccess) -> Bool {
        access == .editable || unlocked || openedEditable
    }

    /// Writes need the repository's `changeAnyway` (the day is outside the window now).
    public func needsChangeAnyway(now access: EditRules.DayAccess) -> Bool {
        access != .editable && isEditable(now: access)
    }

    /// "Older than 2 days, so it's read-only." with the Change anyway link.
    public func showsReadOnlyNotice(now access: EditRules.DayAccess) -> Bool {
        access == .readOnly && !isEditable(now: access)
    }
}

// MARK: - Text

/// Dates and words as the note writes them. English only for now.
nonisolated public enum DayText {
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                         "September", "October", "November", "December"]

    public static func monthName(_ month: Int) -> String { months[month - 1] }
    public static func shortMonth(_ month: Int) -> String { String(months[month - 1].prefix(3)) }

    /// "Nov 4"
    public static func shortDate(_ day: DayKey) -> String { "\(shortMonth(day.month)) \(day.day)" }
    /// "Mon, Nov 9"
    public static func weekdayDate(_ day: DayKey) -> String { "\(day.weekday.shortName), \(shortDate(day))" }
    /// "November 4" (VoiceOver).
    public static func longDate(_ day: DayKey) -> String { "\(monthName(day.month)) \(day.day)" }

    static func tooltipWord(_ status: HabitDayStatus) -> String {
        switch status {
        case .done: "done"
        case .missed: "missed"
        case .missedRecovered: "missed (recovered)"
        case .rest: "rest day"
        case .pending: "not yet"
        default: ""
        }
    }

    static func cardStatus(_ status: HabitDayStatus) -> String {
        switch status {
        case .done: "Done"
        case .missed: "Missed"
        case .missedRecovered: "Missed, then recovered"
        case .rest: "Rest day"
        default: "Not yet"
        }
    }

    /// A short spoken summary of a cell's mark (VoiceOver), or nil when there's nothing to say.
    static func markSummary(_ mark: DayCellMark) -> String? {
        switch mark {
        case .fullSeal: "all done"
        case .slicedSeal(let inked): "\(inked.count { $0 }) of \(inked.count) done"
        case .pencilCircle: "missed"
        case .restDash: "rest day"
        case .goldSeam: "missed, then recovered"
        case .todayPending: "not done yet"
        case .faint, .future: nil
        }
    }

    /// The first part of a habit's subtitle: "10 pages" for amount habits, "3 days a week" for
    /// yes/no habits that aren't daily, nil for daily yes/no habits.
    static func lead(of history: HabitHistory, on day: DayKey) -> String? {
        switch history.kind {
        case .amount(let unit):
            return history.target(on: day).map { "\($0) \(unit)" }
        case .yesNo:
            let schedule = history.schedule(on: day)
            return schedule.isEveryDay ? nil : daysAWeek(schedule.daysPerWeek)
        }
    }

    static func daysAWeek(_ count: Int) -> String { count == 1 ? "1 day a week" : "\(count) days a week" }

    /// "every day" or "Mon, Wed, Fri".
    public static func schedule(_ schedule: Schedule) -> String {
        schedule.isEveryDay ? "every day" : schedule.days.weekdays.map(\.shortName).joined(separator: ", ")
    }
}
