import Core
import Foundation

/// A habit as stored: its details plus its history. A habit whose rows can't make a valid
/// history (a corrupt or hand-edited database) loads as `.failure` instead of crashing, so
/// the app can show it as unreadable while every other habit keeps working.
public struct StoredHabit: Hashable, Sendable, Identifiable {
    public let id: HabitID
    public var name: String
    /// The optional "I'm ___" line; nil when empty.
    public var identity: String?
    /// Position in the habit list (note rows, seal slices, chips).
    public var sortOrder: Int
    public var history: Result<HabitHistory, StoredDataError>
}

/// Why stored rows couldn't be read.
public enum StoredDataError: Error, Hashable, Sendable, CustomStringConvertible {
    case badDay(table: String, value: String)
    case unknownValue(table: String, column: String, value: String)
    case outOfRange(table: String, column: String, value: Int)
    case invalidHistory(HabitHistory.InvalidData)
    case badSnapshot(String)

    public var description: String {
        switch self {
        case let .badDay(table, value): "\(table): not a day: \(value)"
        case let .unknownValue(table, column, value): "\(table).\(column): invalid value \(value)"
        case let .outOfRange(table, column, value): "\(table).\(column): out of range: \(value)"
        case let .invalidHistory(reason): "habit history: \(reason)"
        case let .badSnapshot(reason): "report snapshot: \(reason)"
        }
    }
}

/// A stored row that couldn't be read and was skipped.
public struct StoredDataProblem: Hashable, Sendable {
    public let table: String
    /// The row's stored ID text.
    public let rowID: String
    public let error: StoredDataError
}

/// A day-66 (or re-check) automaticity answer.
public struct AutomaticityCheck: Hashable, Sendable {
    public let day: DayKey
    public let answer: Automaticity.Answer
}

/// A Stamp book unlock and whether it has been noticed yet.
public struct UnlockState: Hashable, Sendable {
    public let unlock: Unlock
    public let unlockedAt: Date
    /// The "You found something" card on the note was dismissed (it shows once).
    public let noticeDismissed: Bool
    /// The Stamp book was visited since (clears its "1 new" marker).
    public let seen: Bool
}

/// The first-time explanation notes (spec-celebrations.md), each shown once.
public enum FirstTimeNote: String, CaseIterable, Hashable, Sendable, Codable {
    case checkOff, recovery, rest, firstReport, day66
}

/// The kinds of report letters.
public enum ReportKind: String, CaseIterable, Hashable, Sendable, Codable {
    case weekly, monthly, day66

    /// The questions this kind of letter asks (spec-reports.md, reflection budget).
    public var questions: [ReportQuestion] {
        switch self {
        case .weekly: [.obstacle]
        case .monthly: [.biggestWin, .nextFocus]
        case .day66: []
        }
    }
}

/// The questions report letters ask (spec-reports.md). All answers are optional.
public enum ReportQuestion: String, CaseIterable, Hashable, Sendable, Codable {
    /// Weekly: "What might get in the way next week, and what will you do instead?"
    case obstacle
    /// Monthly: "What was your biggest win this month?"
    case biggestWin
    /// Monthly: "What will you focus on next month?"
    case nextFocus
}
