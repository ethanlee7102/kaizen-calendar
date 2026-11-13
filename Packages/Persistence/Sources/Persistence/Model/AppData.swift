import Core
import Foundation
import SQLiteData

/// Everything the note and the expanded view read, loaded in one transaction so it's always
/// consistent. Report letters load separately (`StoredReport.fetchAll`), since they're only
/// needed in the Reports tab.
public struct AppData: Hashable, Sendable {
    /// All habits, active and inactive, in list order.
    public var habits: [StoredHabit] = []
    /// Daily notes by day (empty notes aren't stored).
    public var notes: [DayKey: String] = [:]
    public var settings = AppSettings()
    /// "Not now" answers to suggestions.
    public var dismissals: [HabitID: [SuggestionDismissal]] = [:]
    /// Automaticity answers, oldest first.
    public var automaticityChecks: [HabitID: [AutomaticityCheck]] = [:]
    /// Milestone cards (100 / 254 / 365) already dismissed.
    public var milestonesSeen: [HabitID: Set<Int>] = [:]
    public var firstTimeNotesSeen: Set<FirstTimeNote> = []
    public var unlocks: [UnlockState] = []
    /// Rows that couldn't be read and were skipped (unreadable habits are in `habits`).
    public var problems: [StoredDataProblem] = []

    public init() {}

    /// Habits whose history loaded, in list order.
    public var readableHabits: [(habit: StoredHabit, history: HabitHistory)] {
        habits.compactMap { habit in (try? habit.history.get()).map { (habit, $0) } }
    }

    public func habit(_ id: HabitID) -> StoredHabit? { habits.first { $0.id == id } }

    /// Notes as Core values, oldest first.
    public var dayNotes: [DayNote] {
        notes.map { DayNote(day: $0.key, text: $0.value) }.sorted { $0.day < $1.day }
    }

    public static func fetch(_ db: Database) throws -> AppData {
        var data = AppData()

        let schedules = Dictionary(grouping: try ScheduleChangeRecord.all.fetchAll(db), by: \.habitID)
        let targets = Dictionary(grouping: try TargetChangeRecord.all.fetchAll(db), by: \.habitID)
        let periods = Dictionary(grouping: try ActivePeriodRecord.all.fetchAll(db), by: \.habitID)
        let days = Dictionary(grouping: try HabitDayRecord.all.fetchAll(db), by: \.habitID)
        func read<Row, Value>(_ rows: [Row], table: String, id: (Row) -> String,
                              _ transform: (Row) throws(StoredDataError) -> Value) -> [Value] {
            rows.compactMap { row in
                do throws(StoredDataError) {
                    _ = try Mapping.uuid(id(row), in: table, column: "id")
                    return try transform(row)
                } catch {
                    data.problems.append(StoredDataProblem(table: table, rowID: id(row), error: error))
                    return nil
                }
            }
        }
        func habitID(_ text: String, _ table: String) throws(StoredDataError) -> HabitID {
            HabitID(try Mapping.uuid(text, in: table, column: "habitID"))
        }

        // A habit whose ID isn't a UUID can't be shown or changed; it's reported instead.
        data.habits = read(try HabitRecord.order { ($0.sortOrder, $0.createdDay, $0.id) }.fetchAll(db), table: "habits",
                           id: \.id, { row throws(StoredDataError) in
            StoredHabit(
                id: try habitID(row.id, "habits"), name: row.name, identity: row.identity.isEmpty ? nil : row.identity,
                sortOrder: row.sortOrder,
                history: Mapping.history(row, schedules: schedules[row.id] ?? [], targets: targets[row.id] ?? [],
                                         periods: periods[row.id] ?? [], days: days[row.id] ?? []))
        })

        for (day, text) in read(try DayNoteRecord.all.fetchAll(db), table: "dayNotes", id: \.id, { row throws(StoredDataError) in
            (try Mapping.day(row.day, in: "dayNotes"), row.text)
        }) where !text.isEmpty {
            data.notes[day] = text
        }

        let (settings, settingsProblems) = Mapping.settings(try AppSettingsRecord.find(RowID.settings).fetchOne(db))
        data.settings = settings
        data.problems += settingsProblems.map { StoredDataProblem(table: "appSettings", rowID: RowID.settings, error: $0) }

        for (habit, dismissal) in read(try SuggestionDismissalRecord.all.fetchAll(db), table: "suggestionDismissals",
                                       id: \.id, { row throws(StoredDataError) in
            (try habitID(row.habitID, "suggestionDismissals"),
             SuggestionDismissal(kind: try Mapping.value(row.kind, in: "suggestionDismissals", column: "kind"),
                                 day: try Mapping.day(row.day, in: "suggestionDismissals")))
        }) {
            data.dismissals[habit, default: []].append(dismissal)
        }
        for key in data.dismissals.keys { data.dismissals[key]!.sort { $0.day < $1.day } }

        for (habit, check) in read(try AutomaticityCheckRecord.all.fetchAll(db), table: "automaticityChecks",
                                   id: \.id, { row throws(StoredDataError) in
            guard let answer = Automaticity.Answer(rawValue: row.answer) else {
                throw .outOfRange(table: "automaticityChecks", column: "answer", value: row.answer)
            }
            return (try habitID(row.habitID, "automaticityChecks"),
                    AutomaticityCheck(day: try Mapping.day(row.day, in: "automaticityChecks"), answer: answer))
        }) {
            data.automaticityChecks[habit, default: []].append(check)
        }
        for key in data.automaticityChecks.keys { data.automaticityChecks[key]!.sort { $0.day < $1.day } }

        for (habit, milestone) in read(try MilestoneSeenRecord.all.fetchAll(db), table: "milestonesSeen",
                                       id: \.id, { row throws(StoredDataError) in
            (try habitID(row.habitID, "milestonesSeen"), row.milestone)
        }) {
            data.milestonesSeen[habit, default: []].insert(milestone)
        }
        data.firstTimeNotesSeen = Set(read(try FirstTimeNoteSeenRecord.all.fetchAll(db), table: "firstTimeNotesSeen",
                                           id: \.id, { row throws(StoredDataError) in
            try Mapping.value(row.note, in: "firstTimeNotesSeen", column: "note") as FirstTimeNote
        }))
        data.unlocks = read(try UnlockRecord.all.fetchAll(db), table: "unlocks", id: \.id, { row throws(StoredDataError) in
            UnlockState(unlock: try Mapping.value(row.unlock, in: "unlocks", column: "unlock"),
                        unlockedAt: try Mapping.date(row.unlockedAt, in: "unlocks", column: "unlockedAt"),
                        noticeDismissed: try row.noticeDismissedAt.map { text throws(StoredDataError) in
                            try Mapping.date(text, in: "unlocks", column: "noticeDismissedAt")
                        } != nil,
                        seen: try row.seenAt.map { text throws(StoredDataError) in
                            try Mapping.date(text, in: "unlocks", column: "seenAt")
                        } != nil)
        }).sorted { $0.unlockedAt < $1.unlockedAt }
        return data
    }
}
