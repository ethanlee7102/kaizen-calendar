import Core

// What the notebook (the expanded view) shows, worked out from Core values with no SwiftUI
// involved, so every rule and line of copy is unit-tested (spec-expanded-structure.md,
// spec-calendar-and-goal-detail.md, spec-goals-list.md, spec-stamp-book.md, spec-settings.md).
// The views only draw it.

// MARK: - Tabs

/// The notebook's divider tabs, top to bottom.
nonisolated public enum NotebookTab: String, CaseIterable, Hashable, Sendable {
    case calendar, habits, reports, stampBook, science, settings

    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .habits: "Habits"
        case .reports: "Reports"
        case .stampBook: "Stamp book"
        case .science: "The Science"
        case .settings: "Settings"
        }
    }

    /// The tab `offset` places down (positive) or up, stopping at the ends (arrow keys).
    public func moved(by offset: Int) -> NotebookTab {
        let all = Self.allCases
        let index = all.firstIndex(of: self)! + offset
        return all[min(max(index, 0), all.count - 1)]
    }
}

// MARK: - Input

/// A habit whose stored rows can't be read: it can only be deleted.
nonisolated public struct UnreadableHabit: Hashable, Sendable, Identifiable {
    public let id: HabitID
    public let name: String

    public init(id: HabitID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A Stamp book unlock as the app has it.
nonisolated public struct UnlockInfo: Hashable, Sendable {
    public let unlock: Unlock
    /// Not seen in the Stamp book yet: the tab's "1 new" marker.
    public let isNew: Bool

    public init(unlock: Unlock, isNew: Bool) {
        self.unlock = unlock
        self.isNew = isNew
    }
}

/// Everything the notebook needs to draw itself.
nonisolated public struct NotebookInput: Sendable {
    /// Today, every readable habit (active and inactive) in list order, and the daily notes.
    public var note: NoteInput
    public var stampDays: Int
    /// Unlocks found so far, oldest first.
    public var unlocks: [UnlockInfo]
    public var settings: SettingsValues
    public var unreadableHabits: [UnreadableHabit]
    /// A habit was just deleted and can still be brought back ("Undo", about 10 seconds).
    public var pendingDeletion: String?
    /// Every report letter, newest first.
    public var letters: [LetterInput]
    /// Today's level-up or level-down suggestion per active habit (spec-suggestions.md).
    public var suggestions: [HabitID: Suggestion]
    /// "Not now" answers, so a letter's card can say so.
    public var dismissals: [HabitID: [SuggestionDismissal]]

    public init(note: NoteInput, stampDays: Int = 0, unlocks: [UnlockInfo] = [], settings: SettingsValues = SettingsValues(),
                unreadableHabits: [UnreadableHabit] = [], pendingDeletion: String? = nil, letters: [LetterInput] = [],
                suggestions: [HabitID: Suggestion] = [:], dismissals: [HabitID: [SuggestionDismissal]] = [:]) {
        self.note = note
        self.stampDays = stampDays
        self.unlocks = unlocks
        self.settings = settings
        self.unreadableHabits = unreadableHabits
        self.pendingDeletion = pendingDeletion
        self.letters = letters
        self.suggestions = suggestions
        self.dismissals = dismissals
    }

    public var today: DayKey { note.today }

    /// The tabs that carry a "1 new" marker: Reports while a letter is in the envelope, Stamp
    /// book for an unlock not seen yet.
    public var newMarkers: Set<NotebookTab> {
        var markers: Set<NotebookTab> = []
        if letters.contains(where: \.isInEnvelope) { markers.insert(.reports) }
        if unlocks.contains(where: \.isNew) { markers.insert(.stampBook) }
        return markers
    }

    /// The letter in the envelope (the newest new, unopened one).
    public var envelopeLetter: LetterInput? { letters.first(where: \.isInEnvelope) }
}

// MARK: - Calendar

nonisolated public enum CalendarMode: Hashable, Sendable {
    case month, year
}

/// One day in the Calendar tab's month: the note's cell plus the note tick.
nonisolated public struct CalendarCell: Hashable, Sendable, Identifiable {
    public let cell: NoteCell
    /// The day has a daily note: a small slanted pencil mark in the corner.
    public let hasNote: Bool

    public var id: DayKey { cell.day }
}

/// A day square in the year heatmap (spec-calendar-and-goal-detail.md, Year view).
nonisolated public enum HeatSquare: Hashable, Sendable, CaseIterable {
    /// All scheduled done (vermilion).
    case allDone
    /// Some done (light vermilion).
    case someDone
    /// Missed, none done (pencil outline).
    case missed
    /// Rest (moss).
    case rest
    /// Filtered to one habit: missed, then recovered (gold).
    case recovered
    /// Nothing scheduled, before any habit started, or today not decided yet (faint paper).
    case nothing
    /// After today (very faint, no border).
    case future

    /// The square for a day's mark. Today with nothing done yet isn't decided, so it stays faint
    /// (decided in the Phase 5 build).
    public init(_ mark: DayCellMark) {
        self = switch mark {
        case .fullSeal: .allDone
        case .slicedSeal(let inked): inked.contains(true) ? .someDone : .nothing
        case .pencilCircle: .missed
        case .restDash: .rest
        case .goldSeam: .recovered
        case .todayPending, .faint: .nothing
        case .future: .future
        }
    }

    /// The legend under the year view, in this order. Gold only applies to one habit.
    public static func legend(filtered: Bool) -> [HeatSquare] {
        filtered ? [.allDone, .missed, .recovered, .rest] : [.allDone, .someDone, .missed, .rest]
    }

    public var legendText: String {
        switch self {
        case .allDone: "All done"
        case .someDone: "Some done"
        case .missed: "Missed"
        case .rest: "Rest"
        case .recovered: "Recovered"
        case .nothing: "Nothing scheduled"
        case .future: "Ahead"
        }
    }
}

nonisolated public extension NoteInput {
    /// The earliest month the Calendar's arrows reach: the month the first habit started
    /// (today's month before any habit). The latest is today's month (decided in the Phase 5
    /// build: nothing to see in the future).
    var firstCalendarMonth: DayKey {
        (habits.map(\.history.createdDay).min().map { min($0, today) } ?? today).firstOfMonth
    }

    var lastCalendarMonth: DayKey { today.firstOfMonth }

    /// `month` kept between the first and last calendar months.
    func clampedCalendarMonth(_ month: DayKey) -> DayKey {
        min(max(month.firstOfMonth, firstCalendarMonth), lastCalendarMonth)
    }

    var calendarYears: ClosedRange<Int> { firstCalendarMonth.year...today.year }

    func calendarCell(for day: DayKey, filter: HabitID?) -> CalendarCell {
        CalendarCell(cell: cell(for: day, filter: filter), hasNote: notes[day] != nil)
    }

    func heatSquare(for day: DayKey, filter: HabitID?) -> HeatSquare {
        HeatSquare(cell(for: day, filter: filter).mark)
    }

    /// The year square's hover text: the date and what happened ("Nov 4 — Read: done").
    func heatTooltip(for day: DayKey, filter: HabitID?) -> String {
        cell(for: day, filter: filter).tooltip ?? DayText.shortDate(day)
    }

    /// "November · 92% consistency · 3 misses recovered", or nil until the month so far has at
    /// least 7 scheduled days (Insights.monthSummary). Filtered: that habit only.
    func monthSummary(for month: DayKey, filter: HabitID?) -> String? {
        let evaluations = filter.flatMap(habit).map { [$0.evaluation] } ?? habits.map(\.evaluation)
        guard let summary = Insights.monthSummary(evaluations, month: month, today: today),
              let percent = summary.consistency.percent else { return nil }
        var text = "\(DayText.monthName(month.month)) · \(percent)% consistency"
        let recovered = summary.missesRecovered
        if recovered > 0 { text += " · \(recovered) \(recovered == 1 ? "miss" : "misses") recovered" }
        return text
    }

    /// Calendar chips: All, then each active habit in list order.
    var chipHabits: [NoteHabit] { activeHabits }

    /// Inactive habits, newest first (the Calendar's Inactive ▾ menu and the Habits tab).
    var inactiveHabits: [NoteHabit] {
        habits.enumerated()
            .filter { !$0.element.history.isActiveNow }
            .sorted { a, b in
                let (dayA, dayB) = (a.element.history.inactiveSince!, b.element.history.inactiveSince!)
                return dayA != dayB ? dayA > dayB : a.offset < b.offset
            }
            .map(\.element)
    }
}

/// Month arithmetic for the calendar's arrows.
nonisolated public enum CalendarMath {
    /// The first of the month `months` after `month`'s.
    public static func month(_ month: DayKey, adding months: Int) -> DayKey {
        let index = month.year * 12 + (month.month - 1) + months
        return DayKey(year: index / 12, month: index % 12 + 1, day: 1)!
    }
}

// MARK: - Habits list

nonisolated public struct HabitListItem: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable {
        /// Moved to inactive after passing the day-66 check: "Graduated ✓66".
        case graduated
        case paused
    }

    public let id: HabitID
    public let name: String
    public let journey: Journey
    /// Nil while active.
    public let status: Status?

    public var dayText: String { "Day \(journey.count)" }

    public var statusText: String? {
        switch status {
        case .graduated: "Graduated ✓66"
        case .paused: "Paused"
        case nil: nil
        }
    }
}

nonisolated public extension NoteInput {
    /// "Active · 3 of 5"
    var activeTitle: String { "Active · \(activeHabits.count) of \(HabitRules.maxActiveHabits)" }

    var activeItems: [HabitListItem] { activeHabits.map { Self.item($0) } }
    var inactiveItems: [HabitListItem] { inactiveHabits.map { Self.item($0) } }

    static func item(_ habit: NoteHabit) -> HabitListItem {
        let status: HabitListItem.Status? = switch habit.history.inactiveReason {
        case .graduated: .graduated
        case .paused: .paused
        case nil: nil
        }
        return HabitListItem(id: habit.id, name: habit.name, journey: habit.evaluation.journey, status: status)
    }

    /// The habit the Habits tab shows: `current` while it exists, else the first active habit,
    /// else the newest inactive one.
    func habitSelection(keeping current: HabitID?) -> HabitID? {
        if let current, habit(current) != nil { return current }
        return activeHabits.first?.id ?? inactiveHabits.first?.id
    }

    /// The active list after Move up (-1) or Move down (+1), or nil if it can't move that way.
    func activeOrder(moving id: HabitID, by offset: Int) -> [HabitID]? {
        var ids = activeHabits.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return nil }
        ids.swapAt(index, index + offset)
        return ids
    }

    /// The active list after dragging `id` onto `target`'s row: it takes the target's place.
    /// Nil when nothing would change.
    func activeOrder(moving id: HabitID, onto target: HabitID) -> [HabitID]? {
        var ids = activeHabits.map(\.id)
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return nil }
        ids.remove(at: from)
        ids.insert(id, at: to)
        return ids
    }
}

// MARK: - Habit page

/// Change target (amount habits) or Change schedule (yes/no habits) in the page header.
nonisolated public enum PrimaryChange: Hashable, Sendable {
    case target(current: Int, unit: String)
    case schedule
}

/// One step of "How far you've come".
nonisolated public struct HistoryStep: Hashable, Sendable {
    /// "10 pages", or "4 days a week" for yes/no habits.
    public let value: String
    /// "Started Sep 29", "Oct 14 · suggested", "Nov 2 · changed by you · now"
    public let when: String
    public let isCurrent: Bool
}

nonisolated public enum TrendSpan: Hashable, Sendable, CaseIterable {
    case twelveWeeks, allTime

    public var title: String {
        switch self {
        case .twelveWeeks: "12 weeks"
        case .allTime: "All time"
        }
    }

    var weeks: Int {
        switch self {
        case .twelveWeeks: 12
        case .allTime: Int.max
        }
    }
}

/// One week of the weekly consistency graph.
nonisolated public struct TrendPoint: Hashable, Sendable, Identifiable {
    public let weekStart: DayKey
    /// Nil when nothing was scheduled that week (inactive, or all rest): a gap in the line.
    public let percent: Int?
    public let recoveredMisses: [DayKey]
    /// Misses that weren't recovered (they broke the streak).
    public let breakingMisses: [DayKey]

    public var id: DayKey { weekStart }

    /// The line under the graph: the hovered week's details, else the legend. An index left over
    /// from a longer span (12 weeks after All time, with no hover end) falls back to the legend
    /// instead of crashing (Phase 5 review).
    public static func caption(hovered: Int?, in points: [TrendPoint]) -> String {
        if let hovered, points.indices.contains(hovered) { return points[hovered].details }
        return legend
    }

    public static let legend = "Gold ring: a week with a missed day you recovered from. Dashed ring: a miss that broke the streak."

    /// The x-axis label, e.g. "Oct 5".
    public var label: String { DayText.shortDate(weekStart) }

    /// What hovering the week lists: "Week of Oct 5 · 86% · recovered Oct 7 · missed Oct 9, Oct 10".
    public var details: String {
        var parts = ["Week of \(DayText.shortDate(weekStart))", percent.map { "\($0)%" } ?? "nothing scheduled"]
        if !recoveredMisses.isEmpty { parts.append("recovered " + recoveredMisses.map(DayText.shortDate).joined(separator: ", ")) }
        if !breakingMisses.isEmpty { parts.append("missed " + breakingMisses.map(DayText.shortDate).joined(separator: ", ")) }
        if percent != nil, recoveredMisses.isEmpty, breakingMisses.isEmpty { parts.append("no misses") }
        return parts.joined(separator: " · ")
    }
}

/// The habit detail page (spec-calendar-and-goal-detail.md #6). Inactive habits show the same
/// page read-only, frozen at the day they became inactive (spec-goals-list.md).
nonisolated public struct HabitPage: Sendable {
    public let id: HabitID
    public let name: String
    /// "I’m a reader."
    public let identityLine: String?
    /// "10 pages · every day", or the schedule only for yes/no habits ("4 days a week").
    public let detailLine: String
    public let isActive: Bool
    /// "Paused since Nov 3" / "Graduated ✓66 on Nov 3"; nil while active.
    public let inactiveLine: String?
    public let primaryChange: PrimaryChange
    public let canMoveUp: Bool
    public let canMoveDown: Bool

    public let journey: Journey
    /// "25 more done days until your day-66 check-in."
    public let journeyLine: String

    public let streak: Int
    /// "days" or "day".
    public let streakUnit: String
    /// "2 never-miss-twice saves" (gold); nil with none.
    public let savesLine: String?
    /// "92%", or "–" when nothing was scheduled.
    public let consistency: String
    public let consistencyCaption: String

    /// "This habit's month": the month of `asOf`, filtered to this habit.
    public let monthTitle: String
    public let month: MonthGrid
    public let monthCells: [DayKey: NoteCell]

    public let history: [HistoryStep]
    /// Nil until there are 2 full weeks of data.
    public let trend: [TrendPoint]?
}

nonisolated public extension NoteInput {
    /// The detail page for `id`, or nil if the habit is gone.
    func habitPage(_ id: HabitID, trendSpan: TrendSpan = .twelveWeeks) -> HabitPage? {
        guard let habit = habit(id) else { return nil }
        let history = habit.history
        let evaluation = habit.evaluation
        let isActive = history.isActiveNow
        // Inactive habits are frozen at the day they became inactive.
        let asOf = history.inactiveSince.map { min($0, today) } ?? today

        let inactiveLine: String? = history.inactiveSince.map { day in
            history.inactiveReason == .graduated
                ? "Graduated ✓66 on \(DayText.date(day, today: today))"
                : "Paused since \(DayText.date(day, today: today))"
        }
        let primary: PrimaryChange = switch history.kind {
        case .amount(let unit): .target(current: history.target(on: asOf) ?? 1, unit: unit)
        case .yesNo: .schedule
        }
        let order = activeHabits.map(\.id)
        let index = order.firstIndex(of: id)

        let journey = evaluation.journey
        let consistency = evaluation.consistency(in: DayRange(asOf.adding(days: -29), asOf))
        let saves = evaluation.saves
        let grid = MonthGrid(containing: asOf)
        var cells: [DayKey: NoteCell] = [:]
        for day in grid.weeks.flatMap({ $0 }).compactMap({ $0 }) { cells[day] = cell(for: day, filter: id) }

        return HabitPage(
            id: id, name: habit.name,
            identityLine: habit.identity.map { "I’m \($0)." },
            detailLine: Self.detailLine(history, on: asOf),
            isActive: isActive, inactiveLine: inactiveLine, primaryChange: primary,
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < order.count - 1 } ?? false,
            journey: journey, journeyLine: Self.journeyLine(journey),
            streak: evaluation.currentStreak, streakUnit: evaluation.currentStreak == 1 ? "day" : "days",
            savesLine: saves > 0 ? "\(saves) never-miss-twice \(saves == 1 ? "save" : "saves")" : nil,
            consistency: consistency.percent.map { "\($0)%" } ?? "–",
            consistencyCaption: consistency.scheduled == 0 ? "nothing scheduled yet" : "last 30 days",
            monthTitle: DayText.monthName(asOf.month), month: grid, monthCells: cells,
            history: Self.historySteps(history, isActive: isActive, today: today),
            trend: Insights.weeklyTrend([evaluation], through: asOf, weeks: trendSpan.weeks)?.map {
                TrendPoint(weekStart: $0.week.start, percent: $0.consistency.percent,
                           recoveredMisses: $0.recoveredMisses, breakingMisses: $0.unrecoveredMisses)
            })
    }

    /// "10 pages · every day" / "10 pages · Mon, Wed, Fri"; yes/no habits: "every day" or
    /// "4 days a week".
    static func detailLine(_ history: HabitHistory, on day: DayKey) -> String {
        let schedule = history.schedule(on: day)
        switch history.kind {
        case .amount(let unit):
            return "\(history.target(on: day) ?? 1) \(unit) · \(DayText.schedule(schedule))"
        case .yesNo:
            return schedule.isEveryDay ? "every day" : DayText.daysAWeek(schedule.daysPerWeek)
        }
    }

    static func journeyLine(_ journey: Journey) -> String {
        func more(_ n: Int) -> String { n == 1 ? "1 more done day" : "\(n) more done days" }
        if !journey.hasReached66 {
            return "\(more(HabitRules.journeyLength - journey.count)) until your day-66 check-in."
        }
        if let next = journey.nextMilestone { return "\(more(next - journey.count)) to day \(next)." }
        return "Past every milestone. Keep going as long as you like."
    }

    /// Target changes for amount habits, schedule changes for yes/no habits, oldest first.
    static func historySteps(_ history: HabitHistory, isActive: Bool, today: DayKey) -> [HistoryStep] {
        let steps: [(value: String, day: DayKey, source: ChangeSource)] = switch history.kind {
        case .amount(let unit): history.targetChanges.map { ("\($0.amount) \(unit)", $0.day, $0.source) }
        case .yesNo: history.scheduleChanges.map {
            ($0.schedule.isEveryDay ? "every day" : DayText.daysAWeek($0.schedule.daysPerWeek), $0.day, $0.source)
        }
        }
        return steps.enumerated().map { index, step in
            let isLast = index == steps.count - 1
            var when = index == 0 ? "Started \(DayText.date(step.day, today: today))" : DayText.date(step.day, today: today)
            if index > 0 {
                switch step.source {
                case .suggested: when += " · suggested"
                case .manual: when += " · changed by you"
                case .initial: break
                }
            }
            if isLast, isActive { when += " · now" }
            return HistoryStep(value: step.value, when: when, isCurrent: isLast)
        }
    }
}

// MARK: - Delete

/// The Delete confirmation (spec-goals-list.md, Delete).
nonisolated public struct DeleteConfirmation: Hashable, Sendable {
    /// "Delete Read and all 41 days of history?"
    public let title: String
    public let message: String
    /// Active habits offer "Move to inactive" instead; inactive ones "Keep it".
    public let offersMoveToInactive: Bool
}

nonisolated public extension NoteInput {
    func deleteConfirmation(_ id: HabitID) -> DeleteConfirmation? {
        guard let habit = habit(id) else { return nil }
        let days = habit.evaluation.journey.count
        let title = switch days {
        case 0: "Delete \(habit.name)?"
        case 1: "Delete \(habit.name) and its 1 day of history?"
        default: "Delete \(habit.name) and all \(days) days of history?"
        }
        let active = habit.history.isActiveNow
        return DeleteConfirmation(
            title: title,
            message: active ? "To keep the history, move it to inactive instead."
                            : "To keep the history, leave it inactive instead.",
            offersMoveToInactive: active)
    }
}

// MARK: - Stamp book

nonisolated public extension Unlock {
    var title: String {
        switch self {
        case .darkMode: "Dark mode"
        }
    }

    var summary: String {
        switch self {
        case .darkMode: "Charcoal paper with light ink."
        }
    }
}

/// The "You found something" card on the note, right after an unlock (spec-stamp-book.md).
nonisolated public struct UnlockNotice: Hashable, Sendable {
    public let unlock: Unlock

    public init(unlock: Unlock) { self.unlock = unlock }

    /// "You found something: Dark mode."
    public var title: String { "You found something: \(unlock.title)." }
    /// "Charcoal paper with light ink. Choose it in the Stamp book."
    public var message: String { "\(unlock.summary) Choose it in the Stamp book." }
}

// MARK: - Settings

/// The Settings tab's values (spec-settings.md), mirrored from the stored settings so this
/// package doesn't depend on Persistence.
nonisolated public struct SettingsValues: Hashable, Sendable {
    public enum Appearance: String, Hashable, Sendable, CaseIterable {
        case light, dark, matchSystem

        public var title: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .matchSystem: "Match system"
            }
        }
    }

    public enum ReduceMotion: String, Hashable, Sendable, CaseIterable {
        case matchSystem, on, off

        public var title: String {
            switch self {
            case .matchSystem: "Match system"
            case .on: "On"
            case .off: "Off"
            }
        }
    }

    /// macOS "Open at Login" as it is now.
    public enum LoginState: Hashable, Sendable {
        case on, off
        /// Registered, but the user has to allow it in System Settings.
        case needsApproval
    }

    /// The chosen "My day ends at" hour.
    public var dayEndHour = 0
    /// The chosen hour starts tomorrow (a change never moves today backwards).
    public var dayEndStartsTomorrow = false
    public var reportWeekday: Weekday = .sunday
    public var reportHour = 18
    public var reportMinute = 0
    public var reminderEnabled = true
    public var reminderHour = 20
    public var reminderMinute = 0
    public var soundsEnabled = true
    public var reduceMotion: ReduceMotion = .matchSystem
    public var appearance: Appearance = .light
    /// Dark mode was found in the Stamp book, so the Appearance row shows (spec-stamp-book.md).
    public var appearanceUnlocked = false
    public var openAtLogin: LoginState = .off

    public init() {}

    /// "My day ends at": midnight through 4am.
    public static let dayEndHours = DayClock.allowedDayEndHours

    /// "Midnight", "1am" … "4am".
    public static func dayEndTitle(_ hour: Int) -> String { hour == 0 ? "Midnight" : time(hour: hour, minute: 0) }

    /// "6pm", "6:30pm", "12am", "12pm".
    public static func time(hour: Int, minute: Int) -> String {
        let suffix = hour < 12 ? "am" : "pm"
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(twelve)\(suffix)" : "\(twelve):\(minute < 10 ? "0" : "")\(minute)\(suffix)"
    }

    public var reportTime: String { Self.time(hour: reportHour, minute: reportMinute) }

    /// The caption under "My day ends at".
    public var dayEndCaption: String {
        dayEndStartsTomorrow
            ? "Starts tomorrow, so today stays as it is. Check-offs before this time count for the previous day."
            : "Check-offs before this time count for the previous day."
    }
    public var reminderTime: String { Self.time(hour: reminderHour, minute: reminderMinute) }

    /// "The monthly report replaces it on the last Sunday of the month."
    public var monthlyNote: String {
        "The monthly report replaces it on the last \(DayText.weekdayName(reportWeekday)) of the month."
    }
}

// MARK: - Text

nonisolated extension DayText {
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "Sunday"
    public static func weekdayName(_ weekday: Weekday) -> String { weekdayNames[weekday.rawValue] }

    /// "Nov 4", with the year when it isn't this year's: "Sep 29, 2025".
    public static func date(_ day: DayKey, today: DayKey) -> String {
        day.year == today.year ? shortDate(day) : "\(shortDate(day)), \(day.year)"
    }
}
