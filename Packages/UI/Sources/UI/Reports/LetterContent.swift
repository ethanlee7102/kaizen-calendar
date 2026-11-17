import Core
import Foundation

// What the Reports tab, the letters, the envelope, suggestion cards and milestone cards show,
// worked out from Core values with no SwiftUI involved, so every rule and line of copy is
// unit-tested (spec-reports.md, spec-suggestions.md, spec-celebrations.md). The views only draw it.

// MARK: - Input

/// A delivered letter as the notebook gets it (the app maps it from the stored letter).
nonisolated public struct LetterInput: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let kind: ReportKind
    public let deliveryDay: DayKey
    /// The days a weekly or monthly letter covers.
    public let period: DayRange?
    /// Never opened.
    public let isUnread: Bool
    /// Done was clicked, or a newer letter replaced it: read-only.
    public let isFiled: Bool
    /// What it says, as written on its delivery day; nil if it couldn't be read.
    public let content: ReportContent?
    /// The habits' names and kinds as of delivery.
    public let habits: [HabitID: ReportHabitLabel]
    public let answers: [ReportQuestion: String]

    public init(id: UUID, kind: ReportKind, deliveryDay: DayKey, period: DayRange?, isUnread: Bool, isFiled: Bool,
                content: ReportContent?, habits: [HabitID: ReportHabitLabel], answers: [ReportQuestion: String]) {
        self.id = id
        self.kind = kind
        self.deliveryDay = deliveryDay
        self.period = period
        self.isUnread = isUnread
        self.isFiled = isFiled
        self.content = content
        self.habits = habits
        self.answers = answers
    }

    /// The day-66 or re-check letter's habit, by its name in the letter.
    public var habitName: String? { content?.habitID.flatMap { habits[$0]?.name } }

    /// The handwritten greeting: "Your week, Nov 1–7", "Your November", "Day 66: Read",
    /// "Checking in: Read".
    public var title: String {
        switch kind {
        case .weekly: period.map { "Your week, \(DayText.range($0))" } ?? "Your week"
        case .monthly: "Your \(DayText.monthName(deliveryDay.month))"
        case .day66: habitName.map { "Day 66: \($0)" } ?? "Day 66"
        case .recheck: habitName.map { "Checking in: \($0)" } ?? "Checking in"
        }
    }

    /// The archive row's second line: the days covered, or the delivery day.
    public var archiveLine: String {
        switch kind {
        case .weekly: period.map(DayText.range) ?? DayText.shortDate(deliveryDay)
        case .monthly: period.map { "\(DayText.range($0)) · monthly" } ?? "Monthly"
        case .day66, .recheck: DayText.shortDate(deliveryDay)
        }
    }

    /// A letter still waiting in the envelope: new and never opened.
    public var isInEnvelope: Bool { !isFiled && isUnread }

    var automaticity: Automaticity.Answer? {
        answers[.automaticity].flatMap(Int.init).flatMap(Automaticity.Answer.init(rawValue:))
    }

    var decision: LetterDecision? { answers[.decision].flatMap(LetterDecision.init(rawValue:)) }
}

/// The sealed envelope in the note's header (decided in the Phase 6 build, user's choice).
nonisolated public struct NoteEnvelope: Hashable, Sendable {
    public let letterID: UUID
    /// Shown on hover: "Your week, Nov 1–7".
    public let title: String

    public init(letter: LetterInput) {
        letterID = letter.id
        title = letter.title
    }

    public var accessibilityLabel: String { "A new letter: \(title). Open it" }
}

// MARK: - Archive

/// The Reports tab's list (spec-reports.md, Reports tab): new letters at the top, then the
/// archive grouped by the month each letter arrived in, newest first.
nonisolated public struct LetterArchive: Hashable, Sendable {
    public struct Month: Hashable, Sendable, Identifiable {
        /// "November 2026"
        public let title: String
        public let letters: [LetterInput]
        public var id: String { title }
    }

    public let new: [LetterInput]
    public let months: [Month]

    public var isEmpty: Bool { new.isEmpty && months.isEmpty }

    /// `letters` newest first, as stored.
    public init(letters: [LetterInput]) {
        new = letters.filter { !$0.isFiled }
        var months: [Month] = []
        for letter in letters where letter.isFiled {
            let title = "\(DayText.monthName(letter.deliveryDay.month)) \(letter.deliveryDay.year)"
            if months.last?.title == title {
                months[months.count - 1] = Month(title: title, letters: months[months.count - 1].letters + [letter])
            } else {
                months.append(Month(title: title, letters: [letter]))
            }
        }
        self.months = months
    }

    /// Shown before the first letter.
    public static let emptyLine = "Your first letter arrives on your report day, sealed like an envelope."
}

// MARK: - Suggestion cards

/// A level-up or level-down card (spec-suggestions.md): on the habit's page, and in weekly and
/// monthly letters.
nonisolated public struct SuggestionCard: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// Accept / Choose my own / Not now.
        case open
        /// The change is in place (accepted here, or made another way).
        case accepted
        /// "Not now" was chosen after the letter arrived.
        case notNow
        /// The target or schedule changed since, or the habit isn't active: "This no longer applies."
        case noLongerApplies
    }

    public let suggestion: Suggestion
    public let habitName: String
    /// "Two steady weeks. Ready for a little more?"
    public let title: String
    /// "11 pages instead of 10, from today."
    public let change: String
    public let state: State

    public var topic: ScienceTopic { suggestion.kind == .levelUp ? .levelUp : .levelDown }

    /// What the card says instead of its buttons.
    public var stateLine: String? {
        switch state {
        case .open: nil
        case .accepted: "Done. \(Self.capitalized(change.replacingOccurrences(of: ", from today.", with: ""))) from now on."
        case .notNow: "Not now. It may come back in a couple of weeks."
        case .noLongerApplies: "This no longer applies."
        }
    }

    public init(suggestion: Suggestion, habitName: String, kind: HabitKind, state: State) {
        self.suggestion = suggestion
        self.habitName = habitName
        self.state = state
        title = suggestion.kind == .levelUp
            ? "Two steady weeks. Ready for a little more?"
            : "Make it smaller so it’s easy to start again."
        change = Self.changeText(suggestion.change, kind: kind)
    }

    /// "11 pages instead of 10, from today." / "Add Thursday: 4 days a week instead of 3, from
    /// today." / "Drop Tuesday and Saturday: 5 days a week instead of every day, from today."
    static func changeText(_ change: SuggestedChange, kind: HabitKind) -> String {
        switch change {
        case .target(let from, let to):
            let unit = if case .amount(let unit) = kind { " \(unit)" } else { "" }
            return "\(to)\(unit) instead of \(from), from today."
        case .schedule(let from, let to):
            let added = to.days.weekdays.filter { !from.days.contains($0) }
            let removed = from.days.weekdays.filter { !to.days.contains($0) }
            let verb = added.isEmpty ? "Drop" : "Add"
            let days = (added.isEmpty ? removed : added).map(DayText.weekdayName)
            let list = days.count <= 2 ? days.joined(separator: " and ")
                                       : days.dropLast().joined(separator: ", ") + " and " + days.last!
            // "4 days a week instead of 3", but "5 days a week instead of every day".
            let before = from.isEveryDay || to.isEveryDay ? scheduleWords(from) : String(from.daysPerWeek)
            return "\(verb) \(list): \(scheduleWords(to)) instead of \(before), from today."
        }
    }

    static func scheduleWords(_ schedule: Schedule) -> String {
        schedule.isEveryDay ? "every day" : DayText.daysAWeek(schedule.daysPerWeek)
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}

nonisolated public extension NoteInput {
    /// A letter's suggestion as it stands today. Letters never change, but their buttons act on
    /// today's data (spec-reports.md): Accept works only while the target or schedule is still
    /// what the card changes from.
    func letterSuggestionState(_ suggestion: Suggestion, deliveredOn day: DayKey,
                               dismissals: [SuggestionDismissal]) -> SuggestionCard.State {
        guard let habit = habit(suggestion.habitID), habit.history.isActiveNow else { return .noLongerApplies }
        let history = habit.history
        let (from, to): (AnyHashable, AnyHashable)
        let current: AnyHashable
        switch suggestion.change {
        case .target(let a, let b):
            (from, to) = (a, b)
            current = history.target(on: today)
        case .schedule(let a, let b):
            (from, to) = (a, b)
            current = history.schedule(on: today)
        }
        if current == to { return .accepted }
        guard current == from else { return .noLongerApplies }
        if dismissals.contains(where: { $0.kind == suggestion.kind && $0.day >= day }) { return .notNow }
        return .open
    }
}

// MARK: - Milestones

/// The small card on the note at day 100, 254 and 365 (spec-celebrations.md). Dismissed with
/// ×, it never comes back.
nonisolated public struct MilestoneNotice: Hashable, Sendable {
    public let habitID: HabitID
    public let habitName: String
    public let milestone: Int
    /// Every milestone this card stands for (the reached ones not seen yet); × marks them all.
    public let milestones: [Int]

    /// "Day 100 · Read"
    public var title: String { "Day \(milestone) · \(habitName)" }

    public var line: String {
        switch milestone {
        case 100: "Triple digits."
        case 254: "You’ve passed even the slowest habit in the 66-day study."
        case 365: "A full year."
        default: "Keep going."
        }
    }

    public var topic: ScienceTopic { milestone == 254 ? .day254 : .journeyCountsDoneDays }

    /// The milestones after 66 that get a card (66 has its letter).
    static let cardMilestones = HabitRules.milestones.filter { $0 > HabitRules.journeyLength }
}

nonisolated public extension NoteInput {
    /// The first active habit (in list order) with a milestone card waiting: the highest one it
    /// reached that wasn't dismissed.
    var milestoneNotice: MilestoneNotice? {
        for habit in activeHabits {
            let seen = milestonesSeen[habit.id] ?? []
            let waiting = habit.evaluation.journey.reachedMilestones
                .filter { MilestoneNotice.cardMilestones.contains($0) && !seen.contains($0) }
            if let highest = waiting.last {
                return MilestoneNotice(habitID: habit.id, habitName: habit.name, milestone: highest, milestones: waiting)
            }
        }
        return nil
    }
}

// MARK: - Letter page

/// One day's dot in "The week at a glance".
nonisolated public struct GlanceDot: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case done, recovered, missed, rest
        /// Not scheduled (or before the habit started, or inactive): a faint dot.
        case none
    }

    public let day: DayKey
    public let kind: Kind

    init(day: DayKey, status: HabitDayStatus) {
        self.day = day
        kind = switch status {
        case .done: .done
        case .missedRecovered: .recovered
        case .missed: .missed
        case .rest: .rest
        case .notScheduled, .beforeStart, .inactive, .future, .pending: .none
        }
    }

    var word: String {
        switch kind {
        case .done: "done"
        case .recovered: "missed, recovered"
        case .missed: "missed"
        case .rest: "rest"
        case .none: "not scheduled"
        }
    }
}

nonisolated public struct GlanceRow: Hashable, Sendable, Identifiable {
    public let id: HabitID
    public let name: String
    public let dots: [GlanceDot]
    /// "86%", or "–" with nothing scheduled.
    public let percent: String

    public var accessibilityLabel: String {
        "\(name), \(percent == "–" ? "nothing scheduled" : percent): "
            + dots.filter { $0.kind != .none }.map { "\(DayText.weekdayDate($0.day)) \($0.word)" }.joined(separator: ", ")
    }
}

nonisolated public struct LetterLine: Hashable, Sendable {
    public let label: String
    public let text: String
}

/// A written question in a letter (obstacle, biggest win, next month's focus).
nonisolated public struct LetterQuestion: Hashable, Sendable {
    public let question: ReportQuestion
    public let prompt: String
    public let answer: String

    public static func prompt(_ question: ReportQuestion) -> String {
        switch question {
        case .obstacle: "What might get in the way next week, and what will you do instead?"
        case .biggestWin: "What was your biggest win this month?"
        case .nextFocus: "What will you focus on next month?"
        case .automaticity: "I do this automatically."
        case .decision: "What’s next?"
        }
    }
}

/// The weekly obstacle loop (spec-reports.md, Weekly report 7).
nonisolated public struct ObstacleSection: Hashable, Sendable {
    /// The last obstacle answer, shown with "How did it go?" (no input, no judgment).
    public let previous: String?
    public let question: LetterQuestion
    /// "Keep the same" copies the previous answer, while nothing new is written.
    public let canKeepSame: Bool

    public static let previousLabel = "Last time you wrote:"
    public static let howDidItGo = "How did it go?"
}

/// "Not keeping up with a past habit?" in the monthly letter (spec-goals-list.md).
nonisolated public struct ReactivateSection: Hashable, Sendable {
    public struct Item: Hashable, Sendable, Identifiable {
        public enum State: Hashable, Sendable {
            case canReactivate
            /// At 5 active habits: no button.
            case atLimit
            case activeAgain
            case deleted
        }

        public let id: HabitID
        public let name: String
        public let state: State

        public var stateLine: String? {
            switch state {
            case .canReactivate, .atLimit: nil
            case .activeAgain: "Active again"
            case .deleted: "Deleted"
            }
        }
    }

    public let items: [Item]
    public var atLimit: Bool { items.contains { $0.state == .atLimit } }

    public static let statement = "Not keeping up with a past habit? You can bring back any inactive habit."
    public static let atLimitLine = "You’re at 5 habits. Graduate one that feels automatic to make room."
}

/// The day-66 letter's journey recap (spec-reports.md, Day-66 report 1–2).
nonisolated public struct Day66Recap: Hashable, Sendable {
    /// "66 done days in 80 days"
    public let doneLine: String
    /// "Longest streak 30 days · 2 streak breaks · 5 never-miss-twice saves"
    public let streakLine: String
    /// "5 → 8 → 10 pages", or "10 pages the whole way."
    public let historyLine: String
    /// The mini heatmap: one column per week (Sunday first); nil cells are outside the journey.
    public let weeks: [[Bool?]]
    public let firstNote: LetterLine?
    public let latestNote: LetterLine?
}

/// The automaticity check and the decision (day-66 and re-check letters).
nonisolated public struct AutomaticitySection: Hashable, Sendable {
    public let habitID: HabitID?
    public let answer: Automaticity.Answer?
    public let decision: LetterDecision?
    /// Change target (amount habits) or Change schedule (yes/no habits), as of today.
    public let primaryChange: PrimaryChange?
    /// The habit isn't active or is gone, so nothing can be decided (and no decision was made).
    public let unavailableLine: String?
    public let isFiled: Bool

    public static let question = LetterQuestion.prompt(.automaticity)
    public static let hint = "Just one question here. Researchers ask it four slightly different ways and average the answers."

    /// The buttons show while the habit is active and nothing was decided, even in a filed
    /// letter: a newer letter can replace it in the envelope before it's opened (user's choice
    /// after the Phase 6 review).
    public var canDecide: Bool { decision == nil && unavailableLine == nil }
    /// The answer can change until the decision is made.
    public var canAnswer: Bool { canDecide }

    public var recommendation: Automaticity.Recommendation? { answer.map(Automaticity.recommendation(for:)) }

    public var recommendationLine: String? {
        switch recommendation {
        case .graduate: "That sounds automatic. Graduating is a good fit, and you can bring it back anytime."
        case .keepGoing: "Not automatic yet, and that’s normal. Keep going, and we’ll ask again in about 3 weeks."
        case nil: nil
        }
    }

    public var decisionLine: String? {
        switch decision {
        case .graduate: "You chose: Graduate ✓66."
        case .keepGoing: "You chose: Keep going. This check comes back in about 3 weeks."
        case .changeTarget: "You chose: a new target."
        case .changeSchedule: "You chose: a new schedule."
        case nil: nil
        }
    }
}

/// A letter laid out for the page (spec-reports.md). Sections that don't apply are nil or
/// empty, and the view skips them.
nonisolated public struct LetterPage: Sendable {
    public let id: UUID
    public let kind: ReportKind
    public let title: String
    /// "Arrived Sunday, Nov 8"
    public let arrivedLine: String
    public let isFiled: Bool
    /// The letter couldn't be read (made by a newer version, or damaged).
    public let isUnreadable: Bool

    /// "Your first week. Patterns show up once there's more to look at."
    public let firstWeekLine: String?
    /// Weekly letters label the dots S M T W T F S.
    public let showsWeekdayLetters: Bool
    public let glance: [GlanceRow]
    public let savesLine: String?
    public let journeys: [LetterLine]
    public let weakestWeekdays: [String]
    public let suggestions: [SuggestionCard]
    /// "Your notes this week" / "this month"
    public let notesTitle: String
    public let notes: [LetterLine]
    public let obstacle: ObstacleSection?

    public let trend: [TrendPoint]?
    public let reactivate: ReactivateSection?
    public let questions: [LetterQuestion]

    /// Re-check letters: "Day 87. Last time you answered “Somewhat”."
    public let checkInLine: String?
    public let recap: Day66Recap?
    public let automaticity: AutomaticitySection?

    /// "This week" / "This month", for headings.
    var periodWord: String { kind == .monthly ? "month" : "week" }
}

nonisolated public extension NotebookInput {
    /// Letters for the Reports tab.
    var letterArchive: LetterArchive { LetterArchive(letters: letters) }

    func letter(_ id: UUID) -> LetterInput? { letters.first { $0.id == id } }

    /// The letter page for `id`, with its buttons' state worked out from today's data.
    func letterPage(_ id: UUID) -> LetterPage? {
        guard let letter = letter(id) else { return nil }
        let note = note
        let arrived = "Arrived \(DayText.weekdayName(letter.deliveryDay.weekday)), \(DayText.date(letter.deliveryDay, today: today))"

        var firstWeek: String?
        var sections: PeriodSections?
        var previousObstacle: String?
        var trend: [TrendPoint]?
        var reactivate: ReactivateSection?
        var recap: Day66Recap?
        var checkIn: String?
        var automaticity: AutomaticitySection?

        switch letter.content {
        case .weekly(let report):
            sections = report.sections
            previousObstacle = report.previousObstacle
            if report.isFirstWeek { firstWeek = "Your first week. Patterns show up once there’s more to look at." }
        case .monthly(let report):
            sections = report.sections
            trend = report.trend?.map(TrendPoint.init)
            if !report.inactiveHabits.isEmpty {
                reactivate = ReactivateSection(items: report.inactiveHabits.map { id in
                    let name = letter.habits[id]?.name ?? "A habit"
                    let state: ReactivateSection.Item.State = if let habit = note.habit(id) {
                        habit.history.isActiveNow ? .activeAgain
                            : note.addHabitState == .atLimit ? .atLimit : .canReactivate
                    } else {
                        .deleted
                    }
                    return ReactivateSection.Item(id: id, name: name, state: state)
                })
            }
        case .day66(let report):
            recap = Self.recap(report, label: letter.habits[report.habitID], today: today)
            automaticity = automaticitySection(letter, habit: report.habitID)
        case .recheck(let report):
            var line = "Day \(report.dayCount)."
            if let previous = report.previousAnswer { line += " Last time you answered “\(previous.label)”." }
            checkIn = line
            automaticity = automaticitySection(letter, habit: report.habitID)
        case nil:
            break
        }

        let name = { (id: HabitID) in letter.habits[id]?.name ?? "A habit" }
        let rows = sections?.rows ?? []
        let journeyOrder = rows.map(\.habitID)
            + (sections?.journeys.keys.filter { !rows.map(\.habitID).contains($0) }.sorted { name($0) < name($1) } ?? [])
        let period = letter.kind == .monthly ? "month" : "week"

        return LetterPage(
            id: letter.id, kind: letter.kind, title: letter.title, arrivedLine: arrived, isFiled: letter.isFiled,
            isUnreadable: letter.content == nil,
            firstWeekLine: firstWeek,
            showsWeekdayLetters: letter.kind == .weekly,
            glance: rows.map { row in
                GlanceRow(id: row.habitID, name: name(row.habitID),
                          dots: row.days.map { GlanceDot(day: $0.day, status: $0.status) },
                          percent: row.consistency.percent.map { "\($0)%" } ?? "–")
            },
            savesLine: sections.map { Self.savesLine($0.saves, period: period) },
            journeys: journeyOrder.compactMap { id in
                sections?.journeys[id].map { LetterLine(label: name(id), text: Self.journeyText($0)) }
            },
            weakestWeekdays: sections?.weakestWeekdays.map {
                "\(DayText.weekdayName($0.weekday))s have been the hardest for \(name($0.habitID)) lately."
            } ?? [],
            suggestions: sections?.suggestions.map { suggestion in
                SuggestionCard(
                    suggestion: suggestion, habitName: name(suggestion.habitID),
                    kind: letter.habits[suggestion.habitID]?.kind ?? .yesNo,
                    state: note.letterSuggestionState(suggestion, deliveredOn: letter.deliveryDay,
                                                      dismissals: dismissals[suggestion.habitID] ?? []))
            } ?? [],
            notesTitle: "Your notes this \(period)",
            notes: sections?.notes.map { LetterLine(label: DayText.weekdayDate($0.day), text: $0.text) } ?? [],
            obstacle: letter.kind == .weekly && letter.content != nil
                ? ObstacleSection(previous: previousObstacle,
                                  question: Self.question(.obstacle, letter),
                                  canKeepSame: previousObstacle != nil && (letter.answers[.obstacle] ?? "").isEmpty
                                      && !letter.isFiled)
                : nil,
            trend: trend, reactivate: reactivate,
            questions: letter.kind == .monthly && letter.content != nil
                ? [Self.question(.biggestWin, letter), Self.question(.nextFocus, letter)] : [],
            checkInLine: checkIn, recap: recap, automaticity: automaticity)
    }

    internal func automaticitySection(_ letter: LetterInput, habit id: HabitID) -> AutomaticitySection {
        let habit = note.habit(id)
        let name = letter.habits[id]?.name ?? "This habit"
        var unavailable: String?
        if letter.decision == nil {
            if habit == nil {
                unavailable = "\(name) was deleted, so there’s nothing to decide here."
            } else if habit?.history.isActiveNow == false {
                unavailable = "\(name) isn’t active right now, so there’s nothing to decide here."
            }
        }
        let primary: PrimaryChange? = habit.map { habit in
            switch habit.history.kind {
            case .amount(let unit): .target(current: habit.history.target(on: today) ?? 1, unit: unit)
            case .yesNo: .schedule
            }
        }
        return AutomaticitySection(habitID: id, answer: letter.automaticity, decision: letter.decision,
                                   primaryChange: primary, unavailableLine: unavailable, isFiled: letter.isFiled)
    }

    internal static func question(_ question: ReportQuestion, _ letter: LetterInput) -> LetterQuestion {
        LetterQuestion(question: question, prompt: LetterQuestion.prompt(question), answer: letter.answers[question] ?? "")
    }

    /// "No misses this week." / "Missed 3 times, recovered every time." / "Missed once, and
    /// recovered." / "Missed 3 times, recovered 2 of them." / "Missed twice. The next day is
    /// always a fresh start."
    internal static func savesLine(_ saves: Insights.Saves, period: String) -> String {
        if saves.noMisses { return "No misses this \(period)." }
        let missed = switch saves.misses {
        case 1: "Missed once"
        case 2: "Missed twice"
        default: "Missed \(saves.misses) times"
        }
        if saves.recoveredEveryTime { return saves.misses == 1 ? "\(missed), and recovered." : "\(missed), recovered every time." }
        if saves.recovered == 0 { return "\(missed). The next day is always a fresh start." }
        return "\(missed), recovered \(saves.recovered) of them."
    }

    /// "Day 41 of 66" / "Day 87 ✓66"
    internal static func journeyText(_ journey: Journey) -> String {
        journey.hasReached66 ? "Day \(journey.count) ✓66" : "Day \(journey.count) of \(HabitRules.journeyLength)"
    }

    internal static func recap(_ report: Day66Report, label: ReportHabitLabel?, today: DayKey) -> Day66Recap {
        let done = Set(report.doneDays)
        let firstDay = report.reachedOn.adding(days: -(report.calendarDays - 1))
        var weeks: [[Bool?]] = []
        var weekStart = firstDay.startOfWeek
        while weekStart <= report.reachedOn {
            weeks.append((0..<7).map { offset in
                let day = weekStart.adding(days: offset)
                return day < firstDay || day > report.reachedOn ? nil : done.contains(day)
            })
            weekStart = weekStart.adding(days: 7)
        }

        var streak = ["Longest streak \(report.longestStreak) \(report.longestStreak == 1 ? "day" : "days")"]
        let breaks = switch report.streakBreaks {
        case 0: "no streak breaks"
        case 1: "1 streak break"
        default: "\(report.streakBreaks) streak breaks"
        }
        streak.append(breaks)
        if report.saves > 0 { streak.append("\(report.saves) never-miss-twice \(report.saves == 1 ? "save" : "saves")") }

        let history: String
        switch label?.kind {
        case .amount(let unit):
            let amounts = report.targetHistory.map(\.amount)
            history = amounts.count > 1 ? amounts.map(String.init).joined(separator: " → ") + " \(unit)"
                                        : "\(amounts.first ?? 1) \(unit) the whole way."
        case .yesNo, nil:
            let schedules = report.scheduleHistory.map { SuggestionCard.scheduleWords($0.schedule) }
            history = schedules.count > 1 ? schedules.joined(separator: " → ")
                                          : "\(SuggestionCard.capitalized(schedules.first ?? "every day")) the whole way."
        }

        func line(_ note: DayNote?, _ label: String) -> LetterLine? {
            note.map { LetterLine(label: "\(label) (\(DayText.date($0.day, today: today)))", text: $0.text) }
        }
        return Day66Recap(
            doneLine: "\(HabitRules.journeyLength) done days in \(report.calendarDays) days",
            streakLine: streak.joined(separator: " · "), historyLine: history, weeks: weeks,
            firstNote: line(report.firstNote, "Your first note"), latestNote: line(report.latestNote, "Your latest note"))
    }
}

nonisolated extension TrendPoint {
    init(_ week: Insights.TrendWeek) {
        self.init(weekStart: week.week.start, percent: week.consistency.percent,
                  recoveredMisses: week.recoveredMisses, breakingMisses: week.unrecoveredMisses)
    }
}

// MARK: - Habit page suggestion

nonisolated public extension NotebookInput {
    /// The suggestion card at the bottom of a habit's page, when one applies today.
    func suggestionCard(for id: HabitID) -> SuggestionCard? {
        guard let suggestion = suggestions[id], let habit = note.habit(id), habit.history.isActiveNow else { return nil }
        return SuggestionCard(suggestion: suggestion, habitName: habit.name, kind: habit.history.kind, state: .open)
    }
}

// MARK: - Text

nonisolated extension DayText {
    /// "Nov 1–7", "Oct 25–Nov 1", "Dec 27, 2026–Jan 2, 2027".
    public static func range(_ range: DayRange) -> String {
        let (start, end) = (range.start, range.end)
        if start.year != end.year { return "\(shortDate(start)), \(start.year)–\(shortDate(end)), \(end.year)" }
        if start.month == end.month { return "\(shortDate(start))–\(end.day)" }
        return "\(shortDate(start))–\(shortDate(end))"
    }
}
