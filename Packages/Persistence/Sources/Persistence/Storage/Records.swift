import Foundation
import SQLiteData

// Rows exactly as stored. Every column is a plain String, Int or Bool: IDs are lowercase UUID
// text, days are "yyyy-MM-dd", moments are ISO 8601 text, enums are their raw text. The tables
// are STRICT, so decoding a row can't fail; `Mapping.swift` parses each value and turns it
// into Core types, so one bad value only skips its row (or marks its habit unreadable)
// instead of failing the whole load (build plan, Phase 2; Phase 2 review).
//
// CloudKit-ready (SQLiteData sync, later): UUID primary keys, no UNIQUE constraints (rows
// that must be unique use `StableID`), and no reserved CloudKit names. Never rename or drop a
// column; new columns must be nullable or `NOT NULL ON CONFLICT REPLACE DEFAULT …`.

@Table("habits")
struct HabitRecord: Hashable, Sendable {
    let id: String
    var name: String
    /// "" when there's no identity line.
    var identity: String
    /// `StoredKind`.
    var kind: String
    /// "" for yes/no habits.
    var unit: String
    var sortOrder: Int
    var createdDay: String
}

@Table("scheduleChanges")
struct ScheduleChangeRecord: Hashable, Sendable {
    let id: String
    var habitID: String
    var day: String
    /// `WeekdaySet` bits, 1...127 (bit 0 = Sunday).
    var weekdays: Int
    /// `ChangeSource`.
    var source: String
}

@Table("targetChanges")
struct TargetChangeRecord: Hashable, Sendable {
    let id: String
    var habitID: String
    var day: String
    var amount: Int
    var source: String
}

@Table("activePeriods")
struct ActivePeriodRecord: Hashable, Sendable {
    let id: String
    var habitID: String
    var start: String
    var end: String?
    /// `InactiveReason`, set together with `end`.
    var endReason: String?
}

/// A check-off or a rest. A day with neither has no row.
@Table("habitDays")
struct HabitDayRecord: Hashable, Sendable {
    let id: String
    var habitID: String
    var day: String
    /// `StoredDayState`.
    var state: String
}

@Table("dayNotes")
struct DayNoteRecord: Hashable, Sendable {
    let id: String
    var day: String
    var text: String
}

@Table("reports")
struct ReportRecord: Hashable, Sendable {
    let id: String
    /// `ReportKind`.
    var kind: String
    /// Weekly and monthly reports only.
    var periodStart: String?
    var periodEnd: String?
    /// Day-66 reports only. Set to NULL when the habit is deleted: the letter stays.
    var habitID: String?
    var deliveryDay: String
    var deliveredAt: String
    var openedAt: String?
    var filedAt: String?
    /// `ReportSnapshot` as JSON, frozen at delivery.
    var snapshot: String
}

@Table("reportAnswers")
struct ReportAnswerRecord: Hashable, Sendable {
    let id: String
    var reportID: String
    /// `ReportQuestion`.
    var question: String
    var text: String
}

@Table("automaticityChecks")
struct AutomaticityCheckRecord: Hashable, Sendable {
    let id: String
    var habitID: String
    var day: String
    /// 1...5 (`Automaticity.Answer`).
    var answer: Int
}

@Table("suggestionDismissals")
struct SuggestionDismissalRecord: Hashable, Sendable {
    let id: String
    var habitID: String
    /// `SuggestionKind`.
    var kind: String
    var day: String
}

/// Milestone cards (100 / 254 / 365) already shown and dismissed.
@Table("milestonesSeen")
struct MilestoneSeenRecord: Hashable, Sendable {
    let id: String
    var habitID: String
    var milestone: Int
}

/// First-time explanation notes already shown (spec-celebrations.md).
@Table("firstTimeNotesSeen")
struct FirstTimeNoteSeenRecord: Hashable, Sendable {
    let id: String
    var note: String
}

/// Stamp book unlocks. Never removed once earned (spec-stamp-book.md).
@Table("unlocks")
struct UnlockRecord: Hashable, Sendable {
    let id: String
    /// `Unlock`.
    var unlock: String
    var unlockedAt: String
    /// The "You found something" card on the note was dismissed.
    var noticeDismissedAt: String?
    /// The Stamp book tab was visited since ("1 new" marker cleared).
    var seenAt: String?
}

/// One row (id = `StableID.make("settings")`); missing means all defaults.
@Table("appSettings")
struct AppSettingsRecord: Hashable, Sendable {
    let id: String
    var dayEndHour: Int
    /// `Weekday` raw value, 0 = Sunday.
    var reportWeekday: Int
    var reportHour: Int
    var reportMinute: Int
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var soundsEnabled: Bool
    /// `ReduceMotion`.
    var reduceMotion: String
    /// `Appearance`.
    var appearance: String
}
