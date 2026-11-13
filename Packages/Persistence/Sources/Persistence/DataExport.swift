import Core
import Foundation
import SQLiteData

/// "Export my data" (spec-settings.md): a readable JSON file with everything the user made,
/// so the data is never locked in.
///
/// It's built from the stored rows directly, not from Core values, so a habit that can't be
/// read in the app is still exported (only values this version doesn't know, such as an
/// unknown check-off state, are left out). The format is versioned; a change that renames or
/// removes a field needs a new `version`.
public struct DataExport: Hashable, Sendable, Codable {
    public static let currentVersion = 1

    public var format = "66 Days export"
    public var version = DataExport.currentVersion
    public var exportedAt: Date
    public var settings: Settings
    public var habits: [Habit]
    public var notes: [Note]
    public var reports: [Report]

    public struct Settings: Hashable, Sendable, Codable {
        public var dayEndHour: Int
        /// "Sun 18:00".
        public var weeklyReport: String
        /// "20:00", or "off".
        public var reminder: String
        public var sounds: Bool
        public var reduceMotion: String
        public var appearance: String
    }

    public struct Habit: Hashable, Sendable, Codable {
        /// Lowercase UUID text, as stored.
        public var id: String
        public var name: String
        public var identity: String?
        /// "amount" or "yesNo".
        public var kind: String
        public var unit: String?
        public var createdDay: String
        public var schedules: [ScheduleEntry]
        public var targets: [TargetEntry]
        public var activePeriods: [Period]
        public var done: [String]
        public var rested: [String]
        public var automaticityChecks: [Check]
        public var suggestionsDismissed: [Dismissal]
    }

    public struct ScheduleEntry: Hashable, Sendable, Codable {
        public var from: String
        /// "Sun" … "Sat"; all seven for every day.
        public var days: [String]
        public var source: String
    }

    public struct TargetEntry: Hashable, Sendable, Codable {
        public var from: String
        public var amount: Int
        public var source: String
    }

    public struct Period: Hashable, Sendable, Codable {
        public var start: String
        public var end: String?
        public var endReason: String?
    }

    public struct Check: Hashable, Sendable, Codable {
        public var day: String
        /// 1 (Not at all) … 5 (Completely).
        public var answer: Int
    }

    public struct Dismissal: Hashable, Sendable, Codable {
        public var day: String
        public var kind: String
    }

    public struct Note: Hashable, Sendable, Codable {
        public var day: String
        public var text: String
    }

    public struct Report: Hashable, Sendable, Codable {
        public var kind: String
        public var deliveryDay: String
        public var periodStart: String?
        public var periodEnd: String?
        public var habit: String?
        public var answers: [String: String]
    }

    public static func make(_ db: Database, exportedAt: Date) throws -> DataExport {
        let schedules = Dictionary(grouping: try ScheduleChangeRecord.order(by: \.day).fetchAll(db), by: \.habitID)
        let targets = Dictionary(grouping: try TargetChangeRecord.order(by: \.day).fetchAll(db), by: \.habitID)
        let periods = Dictionary(grouping: try ActivePeriodRecord.order(by: \.start).fetchAll(db), by: \.habitID)
        let days = Dictionary(grouping: try HabitDayRecord.order(by: \.day).fetchAll(db), by: \.habitID)
        let checks = Dictionary(grouping: try AutomaticityCheckRecord.order(by: \.day).fetchAll(db), by: \.habitID)
        let dismissals = Dictionary(grouping: try SuggestionDismissalRecord.order(by: \.day).fetchAll(db), by: \.habitID)
        let habitRecords = try HabitRecord.order { ($0.sortOrder, $0.createdDay, $0.id) }.fetchAll(db)
        let names = Dictionary(uniqueKeysWithValues: habitRecords.map { ($0.id, $0.name) })

        let habits = habitRecords.map { row in
            Habit(
                id: row.id, name: row.name, identity: row.identity.isEmpty ? nil : row.identity, kind: row.kind,
                unit: row.unit.isEmpty ? nil : row.unit, createdDay: row.createdDay,
                schedules: (schedules[row.id] ?? []).map {
                    ScheduleEntry(from: $0.day, days: WeekdaySet(rawValue: UInt8(clamping: $0.weekdays)).weekdays.map(\.shortName),
                                  source: $0.source)
                },
                targets: (targets[row.id] ?? []).map { TargetEntry(from: $0.day, amount: $0.amount, source: $0.source) },
                activePeriods: (periods[row.id] ?? []).map { Period(start: $0.start, end: $0.end, endReason: $0.endReason) },
                done: (days[row.id] ?? []).filter { $0.state == StoredDayState.done.rawValue }.map(\.day),
                rested: (days[row.id] ?? []).filter { $0.state == StoredDayState.rested.rawValue }.map(\.day),
                automaticityChecks: (checks[row.id] ?? []).map { Check(day: $0.day, answer: $0.answer) },
                suggestionsDismissed: (dismissals[row.id] ?? []).map { Dismissal(day: $0.day, kind: $0.kind) })
        }

        let answers = Dictionary(grouping: try ReportAnswerRecord.all.fetchAll(db), by: \.reportID)
        let reports = try ReportRecord.order { ($0.deliveryDay, $0.deliveredAt, $0.id) }.fetchAll(db).map { row in
            Report(kind: row.kind, deliveryDay: row.deliveryDay, periodStart: row.periodStart, periodEnd: row.periodEnd,
                   habit: row.habitID.flatMap { names[$0] } ?? day66HabitName(row),
                   answers: Dictionary((answers[row.id] ?? []).map { ($0.question, $0.text) }, uniquingKeysWith: { a, _ in a }))
        }

        let (settings, _) = Mapping.settings(try AppSettingsRecord.find(RowID.settings).fetchOne(db))
        func time(_ hour: Int, _ minute: Int) -> String {
            String(format: "%02d:%02d", hour, minute)
        }
        return DataExport(
            exportedAt: exportedAt,
            settings: Settings(
                dayEndHour: settings.dayEndHour,
                weeklyReport: "\(settings.report.weekday.shortName) \(time(settings.report.hour, settings.report.minute))",
                reminder: settings.reminderEnabled ? time(settings.reminderHour, settings.reminderMinute) : "off",
                sounds: settings.soundsEnabled, reduceMotion: settings.reduceMotion.rawValue,
                appearance: settings.appearance.rawValue),
            habits: habits,
            notes: try DayNoteRecord.order(by: \.day).fetchAll(db).map { Note(day: $0.day, text: $0.text) },
            reports: reports)
    }

    /// A deleted habit's day-66 letter still names it (its snapshot keeps the name).
    private static func day66HabitName(_ row: ReportRecord) -> String? {
        guard row.kind == ReportKind.day66.rawValue, case .success(let snapshot) = ReportSnapshot.decode(row.snapshot),
              case .day66(let report) = snapshot.content
        else { return nil }
        return snapshot.habits[report.habitID]?.name
    }

    /// Pretty-printed JSON with stable key order.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

extension Repository {
    /// Everything, ready to save as a .json file.
    public func export(at now: Date) throws -> Data {
        try database.read { try DataExport.make($0, exportedAt: now) }.jsonData()
    }
}
