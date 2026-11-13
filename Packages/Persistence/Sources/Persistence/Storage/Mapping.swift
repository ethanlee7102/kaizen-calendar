import Core
import Foundation

/// Stored text values for Core types that have no raw value of their own.
enum StoredKind: String { case amount, yesNo }
enum StoredDayState: String { case done, rested }

/// The deterministic ID of each row that must be unique (see `StableID`), as stored text.
enum RowID {
    static func schedule(_ habit: HabitID, _ day: DayKey) -> String { make("schedule", habit.key, "\(day)") }
    static func target(_ habit: HabitID, _ day: DayKey) -> String { make("target", habit.key, "\(day)") }
    static func period(_ habit: HabitID, _ start: DayKey) -> String { make("period", habit.key, "\(start)") }
    static func habitDay(_ habit: HabitID, _ day: DayKey) -> String { make("day", habit.key, "\(day)") }
    static func note(_ day: DayKey) -> String { make("note", "\(day)") }
    static func automaticity(_ habit: HabitID, _ day: DayKey) -> String { make("automaticity", habit.key, "\(day)") }
    static func dismissal(_ habit: HabitID, _ kind: SuggestionKind, _ day: DayKey) -> String {
        make("dismissal", habit.key, kind.rawValue, "\(day)")
    }
    static func milestone(_ habit: HabitID, _ milestone: Int) -> String { make("milestone", habit.key, "\(milestone)") }
    static func firstTimeNote(_ note: FirstTimeNote) -> String { make("firstTimeNote", note.rawValue) }
    static func unlock(_ unlock: Unlock) -> String { make("unlock", unlock.rawValue) }
    static let settings = make("settings")
    /// One weekly or monthly letter per period; one day-66 letter per habit.
    static func report(_ kind: ReportKind, periodEnd: DayKey) -> String { make("report", kind.rawValue, "\(periodEnd)") }
    static func day66Report(_ habit: HabitID) -> String { make("report", ReportKind.day66.rawValue, habit.key) }
    static func answer(_ report: String, _ question: ReportQuestion) -> String { make("answer", report, question.rawValue) }

    private static func make(_ parts: String...) -> String { StableID.key(StableID.make(parts)) }
}

extension HabitID {
    /// The stored form: lowercase UUID text.
    var key: String { StableID.key(rawValue) }
}

/// Rows → Core values (throwing on anything invalid) and Core values → rows.
enum Mapping {
    static func day(_ text: String, in table: String) throws(StoredDataError) -> DayKey {
        guard let day = DayKey(text) else { throw .badDay(table: table, value: text) }
        return day
    }

    static func uuid(_ text: String, in table: String, column: String) throws(StoredDataError) -> UUID {
        guard let uuid = UUID(uuidString: text) else { throw .unknownValue(table: table, column: column, value: text) }
        return uuid
    }

    /// Moments are stored as ISO 8601 text in UTC, with milliseconds.
    static func date(_ text: String, in table: String, column: String) throws(StoredDataError) -> Date {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
        throw .unknownValue(table: table, column: column, value: text)
    }

    static func text(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func value<T: RawRepresentable<String>>(_ text: String, in table: String, column: String) throws(StoredDataError) -> T {
        guard let value = T(rawValue: text) else { throw .unknownValue(table: table, column: column, value: text) }
        return value
    }

    // MARK: Habits

    static func kind(_ habit: HabitRecord) throws(StoredDataError) -> HabitKind {
        switch try value(habit.kind, in: "habits", column: "kind") as StoredKind {
        case .amount: .amount(unit: habit.unit)
        case .yesNo: .yesNo
        }
    }

    static func history(
        _ habit: HabitRecord,
        schedules: [ScheduleChangeRecord],
        targets: [TargetChangeRecord],
        periods: [ActivePeriodRecord],
        days: [HabitDayRecord]
    ) -> Result<HabitHistory, StoredDataError> {
        Result { () throws(StoredDataError) -> HabitHistory in
            let scheduleChanges = try schedules.map { row throws(StoredDataError) in
                guard let schedule = Schedule(days: WeekdaySet(rawValue: UInt8(clamping: row.weekdays))),
                      (1...127).contains(row.weekdays)
                else { throw .outOfRange(table: "scheduleChanges", column: "weekdays", value: row.weekdays) }
                return ScheduleChange(day: try day(row.day, in: "scheduleChanges"), schedule: schedule,
                                      source: try value(row.source, in: "scheduleChanges", column: "source"))
            }
            let targetChanges = try targets.map { row throws(StoredDataError) in
                guard row.amount >= 1 else { throw .outOfRange(table: "targetChanges", column: "amount", value: row.amount) }
                return TargetChange(day: try day(row.day, in: "targetChanges"), amount: row.amount,
                                    source: try value(row.source, in: "targetChanges", column: "source"))
            }
            let activePeriods = try periods.map { row throws(StoredDataError) in
                let start = try day(row.start, in: "activePeriods")
                let end = try row.end.map { text throws(StoredDataError) in try day(text, in: "activePeriods") }
                let reason: InactiveReason? = try row.endReason.map { text throws(StoredDataError) in
                    try value(text, in: "activePeriods", column: "endReason")
                }
                guard (end == nil) == (reason == nil), end.map({ $0 >= start }) ?? true else {
                    throw .invalidHistory(.periodsOverlapOrOpenInMiddle)
                }
                return ActivePeriod(start: start, end: end, endReason: reason)
            }
            var completions: Set<DayKey> = []
            var rests: Set<DayKey> = []
            for row in days {
                let day = try day(row.day, in: "habitDays")
                switch try value(row.state, in: "habitDays", column: "state") as StoredDayState {
                case .done: completions.insert(day)
                case .rested: rests.insert(day)
                }
            }
            let id = HabitID(try uuid(habit.id, in: "habits", column: "id"))
            let kind = try kind(habit)
            let createdDay = try day(habit.createdDay, in: "habits")
            do throws(HabitHistory.InvalidData) {
                // Every habit stores at least one period; none at all is corrupt, so this
                // passes the empty list instead of letting Core default to one.
                return try HabitHistory(
                    id: id, kind: kind, createdDay: createdDay,
                    scheduleChanges: scheduleChanges, targetChanges: targetChanges,
                    activePeriods: activePeriods, completions: completions, rests: rests)
            } catch {
                throw .invalidHistory(error)
            }
        }
    }

    /// The change and period rows that store `history` (check-offs and rests are separate).
    static func changeRecords(for history: HabitHistory) -> (
        schedules: [ScheduleChangeRecord], targets: [TargetChangeRecord], periods: [ActivePeriodRecord]
    ) {
        let habit = history.id.key
        return (
            history.scheduleChanges.map {
                ScheduleChangeRecord(id: RowID.schedule(history.id, $0.day), habitID: habit, day: "\($0.day)",
                                     weekdays: Int($0.schedule.days.rawValue), source: $0.source.rawValue)
            },
            history.targetChanges.map {
                TargetChangeRecord(id: RowID.target(history.id, $0.day), habitID: habit, day: "\($0.day)",
                                   amount: $0.amount, source: $0.source.rawValue)
            },
            history.activePeriods.map {
                ActivePeriodRecord(id: RowID.period(history.id, $0.start), habitID: habit, start: "\($0.start)",
                                   end: $0.end.map { "\($0)" }, endReason: $0.endReason?.rawValue)
            }
        )
    }

    /// The row for `day`: done, rested, or nil (no fact).
    static func dayRecord(for history: HabitHistory, on day: DayKey) -> HabitDayRecord? {
        let state: StoredDayState? = if history.completions.contains(day) {
            .done
        } else if history.rests.contains(day) {
            .rested
        } else {
            nil
        }
        return state.map {
            HabitDayRecord(id: RowID.habitDay(history.id, day), habitID: history.id.key, day: "\(day)", state: $0.rawValue)
        }
    }

    static func dayRecords(for history: HabitHistory) -> [HabitDayRecord] {
        history.completions.union(history.rests).sorted().compactMap { dayRecord(for: history, on: $0) }
    }

    // MARK: Settings

    /// Reads settings; any invalid value falls back to its default and is reported.
    static func settings(_ row: AppSettingsRecord?) -> (AppSettings, [StoredDataError]) {
        var settings = AppSettings()
        guard let row else { return (settings, []) }
        var problems: [StoredDataError] = []
        func int(_ value: Int, _ range: ClosedRange<Int>, _ column: String, _ apply: (Int) -> Void) {
            if range.contains(value) { apply(value) } else {
                problems.append(.outOfRange(table: "appSettings", column: column, value: value))
            }
        }
        int(row.dayEndHour, DayClock.allowedDayEndHours, "dayEndHour") { settings.dayEndHour = $0 }
        int(row.reportWeekday, 0...6, "reportWeekday") { settings.report.weekday = Weekday(rawValue: $0)! }
        int(row.reportHour, 0...23, "reportHour") { settings.report.hour = $0 }
        int(row.reportMinute, 0...59, "reportMinute") { settings.report.minute = $0 }
        int(row.reminderHour, 0...23, "reminderHour") { settings.reminderHour = $0 }
        int(row.reminderMinute, 0...59, "reminderMinute") { settings.reminderMinute = $0 }
        settings.reminderEnabled = row.reminderEnabled
        settings.soundsEnabled = row.soundsEnabled
        do { settings.reduceMotion = try value(row.reduceMotion, in: "appSettings", column: "reduceMotion") }
        catch { problems.append(error) }
        do { settings.appearance = try value(row.appearance, in: "appSettings", column: "appearance") }
        catch { problems.append(error) }
        return (settings, problems)
    }

    static func record(_ settings: AppSettings) -> AppSettingsRecord {
        AppSettingsRecord(
            id: RowID.settings, dayEndHour: settings.dayEndHour, reportWeekday: settings.report.weekday.rawValue,
            reportHour: settings.report.hour, reportMinute: settings.report.minute,
            reminderEnabled: settings.reminderEnabled, reminderHour: settings.reminderHour,
            reminderMinute: settings.reminderMinute, soundsEnabled: settings.soundsEnabled,
            reduceMotion: settings.reduceMotion.rawValue, appearance: settings.appearance.rawValue)
    }
}
