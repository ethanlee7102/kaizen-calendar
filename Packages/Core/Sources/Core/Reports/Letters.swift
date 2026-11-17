/// Report letters as plain values (spec-reports.md): what a letter is, what it says and what it
/// asks. Persistence stores them as frozen snapshots; the UI draws them.

/// The kinds of report letters.
public enum ReportKind: String, CaseIterable, Hashable, Sendable, Codable {
    case weekly, monthly, day66
    /// The automaticity re-check, about every 3 weeks after "Keep going" (decided in the
    /// Phase 6 build: its own letter, user's choice).
    case recheck

    /// The written questions this kind of letter asks (spec-reports.md, reflection budget).
    /// The automaticity answer and the decision are stored with the letter too, but only through
    /// their own writes, which also act on the habit.
    public var questions: [ReportQuestion] {
        switch self {
        case .weekly: [.obstacle]
        case .monthly: [.biggestWin, .nextFocus]
        case .day66, .recheck: []
        }
    }

    /// Day-66 and re-check letters end with the automaticity check and a decision.
    public var asksAutomaticity: Bool { self == .day66 || self == .recheck }
}

/// What a letter stores as answers (spec-reports.md). All are optional.
public enum ReportQuestion: String, CaseIterable, Hashable, Sendable, Codable {
    /// Weekly: "What might get in the way next week, and what will you do instead?"
    case obstacle
    /// Monthly: "What was your biggest win this month?"
    case biggestWin
    /// Monthly: "What will you focus on next month?"
    case nextFocus
    /// Day 66 and re-check: "I do this automatically.", stored as "1"…"5".
    case automaticity
    /// Day 66 and re-check: the `LetterDecision` chosen (its raw value).
    case decision
}

/// The decision at the end of a day-66 or re-check letter (spec-reports.md, Day-66 report).
public enum LetterDecision: String, CaseIterable, Hashable, Sendable, Codable {
    /// Move to inactive as Graduated ✓66.
    case graduate
    /// Keep going: the counter becomes "Day N ✓66", and the check returns in about 3 weeks.
    case keepGoing
    /// The target (amount habits) or schedule (yes/no habits) was changed from the letter.
    case changeTarget
    case changeSchedule
}

/// What a day-66 or re-check letter's decision does (`Repository.decide`).
public enum LetterChoice: Hashable, Sendable {
    /// Move to inactive as Graduated ✓66.
    case graduate
    case keepGoing
    /// Change the target from today (amount habits).
    case changeTarget(Int)
    /// Change the schedule from today (yes/no habits).
    case changeSchedule(Schedule)

    public var decision: LetterDecision {
        switch self {
        case .graduate: .graduate
        case .keepGoing: .keepGoing
        case .changeTarget: .changeTarget
        case .changeSchedule: .changeSchedule
        }
    }
}

/// A habit's name and kind as a letter was written (letters never change afterwards).
public struct ReportHabitLabel: Hashable, Sendable, Codable {
    public let name: String
    public let identity: String?
    public let kind: HabitKind

    public init(name: String, identity: String?, kind: HabitKind) {
        self.name = name
        self.identity = identity
        self.kind = kind
    }
}

/// What a letter says.
public enum ReportContent: Hashable, Sendable, Codable {
    case weekly(WeeklyReport)
    case monthly(MonthlyReport)
    case day66(Day66Report)
    case recheck(RecheckReport)

    public var kind: ReportKind {
        switch self {
        case .weekly: .weekly
        case .monthly: .monthly
        case .day66: .day66
        case .recheck: .recheck
        }
    }

    /// The days a weekly or monthly letter covers.
    public var period: DayRange? {
        switch self {
        case .weekly(let report): report.sections.period
        case .monthly(let report): report.sections.period
        case .day66, .recheck: nil
        }
    }

    /// The habit a day-66 or re-check letter is about.
    public var habitID: HabitID? {
        switch self {
        case .weekly, .monthly: nil
        case .day66(let report): report.habitID
        case .recheck(let report): report.habitID
        }
    }
}

/// The automaticity re-check letter: "Checking in: Read", the habit's day count and the answer
/// given last time, then the one question and the decision.
public struct RecheckReport: Hashable, Sendable, Codable {
    public let habitID: HabitID
    /// The journey as of delivery ("Day 87").
    public let dayCount: Int
    /// The last automaticity answer, if one was given.
    public let previousAnswer: Automaticity.Answer?

    public init(habitID: HabitID, dayCount: Int, previousAnswer: Automaticity.Answer?) {
        self.habitID = habitID
        self.dayCount = dayCount
        self.previousAnswer = previousAnswer
    }
}

public extension Automaticity {
    /// The day the next re-check letter is due, for an active habit past day 66: about 3 weeks
    /// after its latest day-66 or re-check letter, or after it became active again if that's
    /// later (a reactivated habit gets its 3 weeks first). Nil when there's no such letter yet:
    /// the day-66 letter comes first.
    static func recheckDay(lastLetterDay: DayKey?, history: HabitHistory) -> DayKey? {
        guard let lastLetterDay, history.isActiveNow else { return nil }
        return nextCheckDay(after: max(lastLetterDay, history.currentPeriodStart))
    }
}
