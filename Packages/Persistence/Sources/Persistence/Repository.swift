import Core
import Foundation
import SQLiteData

/// Every write to the app's data. Each method is one transaction: it either fully happens or
/// throws and changes nothing.
///
/// Habit rules stay in Core: a write loads the habit's `HabitHistory`, applies Core's mutation
/// (`setDone`, `changeTarget`, `deactivate`, …) and stores the result. Who may change what
/// (`EditRules`, the 5-habit limit, read-only inactive habits) is checked here, so the UI can't
/// get it wrong.
///
/// "Active" here means the habit has an open active period (`isActiveNow`), one definition for
/// the 5-habit limit, the read-only rule and the note's rows. It deliberately doesn't depend on
/// today: when today moves backwards (a later day-end time, flying west), a habit started
/// "tomorrow" stays active instead of disappearing (Phase 2 review).
public struct Repository: Sendable {
    public let database: any DatabaseWriter

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    public enum Failure: Error, Hashable, Sendable {
        case habitNotFound
        /// The habit's stored rows are corrupt; it can't be changed (it can be deleted).
        case unreadable(StoredDataError)
        /// "You're at 5 habits."
        case atHabitLimit
        case emptyName
        case missingUnit
        case invalidTarget
        case notAnAmountHabit
        /// Inactive habits are read-only until reactivated (spec-goals-list.md).
        case habitInactive
        /// Days after today can't be changed.
        case futureDay
        /// Days older than today and the 2 before need "Change anyway" (spec-collapsed-note.md §6).
        case olderDayNeedsConfirmation
        /// The habit doesn't count on that day (not scheduled, or not active then).
        case dayDoesNotCount
        /// Rest is only for today, on a scheduled habit that isn't done, and not on a danger day.
        case cannotRest
        /// A letter's suggestion no longer matches the current target or schedule.
        case suggestionNoLongerApplies
        case invalidSettings
        case reportNotFound
        /// Filed letters are read-only (spec-reports.md, Reports tab).
        case reportFiled
        /// That question isn't asked in that kind of letter.
        case questionNotInReport
    }

    // MARK: Reading

    public func appData() throws -> AppData {
        try database.read { try AppData.fetch($0) }
    }

    // MARK: Adding and editing habits

    /// Adds a habit that starts today, at the end of the list.
    @discardableResult
    public func addHabit(name: String, identity: String? = nil, kind: HabitKind, target: Int? = nil,
                         schedule: Schedule, today: DayKey) throws -> HabitID {
        let name = try Self.validName(name)
        var kind = kind
        if case .amount(let unit) = kind {
            kind = .amount(unit: try Self.validUnit(unit))
            guard let target, target >= 1 else { throw Failure.invalidTarget }
        }
        let history = HabitHistory.new(kind: kind, target: kind == .yesNo ? nil : target, schedule: schedule, on: today)
        try database.write { db in
            guard HabitRules.addHabitState(activeCount: try Self.activeCount(db)) != .atLimit else {
                throw Failure.atHabitLimit
            }
            let record = HabitRecord(id: history.id.key, name: name, identity: Self.trimmed(identity),
                                     kind: Self.storedKind(kind).rawValue, unit: Self.unit(kind),
                                     sortOrder: try Self.nextSortOrder(db), createdDay: "\(today)")
            try HabitRecord.insert { record }.execute(db)
            try Self.saveChanges(db, history)
        }
        return history.id
    }

    /// Renames a habit, or changes its identity line or unit.
    public func updateDetails(of id: HabitID, name: String, identity: String?, unit: String? = nil, today: DayKey) throws {
        let name = try Self.validName(name)
        try database.write { db in
            var (record, history) = try Self.load(db, id)
            guard history.isActiveNow else { throw Failure.habitInactive }
            record.name = name
            record.identity = Self.trimmed(identity)
            if case .amount = history.kind, let unit {
                record.unit = try Self.validUnit(unit)
            }
            try HabitRecord.update(record).execute(db)
        }
    }

    /// Changes the target from today on. A second change on the same day replaces the first
    /// (the typo-fix rule lives in Core's `changeTarget`).
    public func changeTarget(of id: HabitID, to amount: Int, today: DayKey, source: ChangeSource = .manual) throws {
        guard amount >= 1 else { throw Failure.invalidTarget }
        try modify(id, today: today) { history in
            guard case .amount = history.kind else { throw Failure.notAnAmountHabit }
            history.changeTarget(to: amount, on: today, source: source)
        }
    }

    /// Changes the schedule from today on; past days keep the schedule they had.
    public func changeSchedule(of id: HabitID, to schedule: Schedule, today: DayKey, source: ChangeSource = .manual) throws {
        try modify(id, today: today) { history in
            history.changeSchedule(to: schedule, on: today, source: source)
        }
    }

    /// Sets the list order. Habits not listed keep their relative order after the listed ones.
    public func reorder(_ ids: [HabitID]) throws {
        try database.write { db in
            let records = try HabitRecord.order { ($0.sortOrder, $0.createdDay, $0.id) }.fetchAll(db)
            let listed = ids.map(\.key)
            let ordered = listed.compactMap { id in records.first { $0.id == id } }
                + records.filter { !listed.contains($0.id) }
            for (index, record) in ordered.enumerated() where record.sortOrder != index {
                try HabitRecord.find(record.id).update { $0.sortOrder = index }.execute(db)
            }
        }
    }

    // MARK: Inactive

    /// Moves a habit to inactive from today on (Paused, or Graduated ✓66 from the day-66 report).
    public func deactivate(_ id: HabitID, today: DayKey, reason: InactiveReason = .paused) throws {
        try database.write { db in
            let (_, history) = try Self.load(db, id)
            var updated = history
            updated.deactivate(on: today, reason: reason)
            try Self.saveChanges(db, updated)
        }
    }

    /// Brings an inactive habit back from today on, at the end of the list. Streak and journey
    /// continue where they left off.
    public func reactivate(_ id: HabitID, today: DayKey) throws {
        try database.write { db in
            let (_, history) = try Self.load(db, id)
            guard !history.isActiveNow else { return }
            guard HabitRules.addHabitState(activeCount: try Self.activeCount(db)) != .atLimit else {
                throw Failure.atHabitLimit
            }
            var updated = history
            updated.reactivate(on: today)
            try Self.saveChanges(db, updated)
            let order = try Self.nextSortOrder(db)
            try HabitRecord.find(id.key).update { $0.sortOrder = order }.execute(db)
        }
    }

    // MARK: Delete and undo

    /// Deletes a habit and all its history. Keep the result for the 10-second Undo
    /// (`restore`); after that, drop it and the deletion is final. Report letters that mention
    /// the habit stay as written (decided 2026-11-13).
    public func deleteHabit(_ id: HabitID) throws -> DeletedHabit {
        try database.write { db in
            let habit = id.key
            guard let record = try HabitRecord.find(habit).fetchOne(db) else { throw Failure.habitNotFound }
            let deleted = DeletedHabit(
                id: id, habit: record,
                schedules: try ScheduleChangeRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                targets: try TargetChangeRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                periods: try ActivePeriodRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                days: try HabitDayRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                automaticityChecks: try AutomaticityCheckRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                dismissals: try SuggestionDismissalRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                milestones: try MilestoneSeenRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                reportIDs: try ReportRecord.where { $0.habitID.eq(habit) }.select(\.id).fetchAll(db))
            // Child rows cascade; the habit's day-66 letter keeps its snapshot (habitID → NULL).
            try HabitRecord.find(habit).delete().execute(db)
            return deleted
        }
    }

    /// Undo for `deleteHabit`: puts everything back exactly as it was. If that would make a
    /// 6th active habit, it comes back Paused from today instead (decided 2026-11-13).
    public func restore(_ deleted: DeletedHabit, today: DayKey) throws {
        try database.write { db in
            guard try HabitRecord.find(deleted.habit.id).fetchOne(db) == nil else { return } // already restored
            let activeBefore = try Self.activeCount(db)
            // Back in its old place: habits at or after it move down one.
            let position = deleted.habit.sortOrder
            if try HabitRecord.where({ $0.sortOrder.eq(position) }).fetchCount(db) > 0 {
                try HabitRecord.where { $0.sortOrder >= position }.update { $0.sortOrder += 1 }.execute(db)
            }
            try HabitRecord.insert { deleted.habit }.execute(db)
            if !deleted.schedules.isEmpty { try ScheduleChangeRecord.insert { deleted.schedules }.execute(db) }
            if !deleted.targets.isEmpty { try TargetChangeRecord.insert { deleted.targets }.execute(db) }
            if !deleted.periods.isEmpty { try ActivePeriodRecord.insert { deleted.periods }.execute(db) }
            if !deleted.days.isEmpty { try HabitDayRecord.insert { deleted.days }.execute(db) }
            if !deleted.automaticityChecks.isEmpty { try AutomaticityCheckRecord.insert { deleted.automaticityChecks }.execute(db) }
            if !deleted.dismissals.isEmpty { try SuggestionDismissalRecord.insert { deleted.dismissals }.execute(db) }
            if !deleted.milestones.isEmpty { try MilestoneSeenRecord.insert { deleted.milestones }.execute(db) }
            if !deleted.reportIDs.isEmpty {
                try ReportRecord.where { $0.id.in(deleted.reportIDs) }.update { $0.habitID = #bind(deleted.habit.id) }.execute(db)
            }

            if case .success(let history) = Self.history(db, deleted.habit), history.isActiveNow,
               activeBefore >= HabitRules.maxActiveHabits {
                var paused = history
                paused.deactivate(on: today, reason: .paused)
                try Self.saveChanges(db, paused)
            }
        }
    }

    // MARK: Check-offs, rests, notes

    /// Checks a habit off (or unchecks it) on `day`. Today and the 2 days before are
    /// editable; older days need `changeAnyway` (the user confirmed "Change anyway").
    public func setDone(_ done: Bool, habit id: HabitID, on day: DayKey, today: DayKey, changeAnyway: Bool = false) throws {
        try Self.checkAccess(to: day, today: today, changeAnyway: changeAnyway)
        try modify(id, today: today, onlyDays: [day, today]) { history in
            guard history.isScheduled(on: day) || history.counts(on: day) else { throw Failure.dayDoesNotCount }
            history.setDone(done, on: day)
            // Unchecking an earlier day can make today a danger day; a rest today would then
            // dodge never-miss-twice, so it's cleared (decided 2026-11-13, Phase 2 review).
            if day < today, history.rests.contains(today) {
                var unrested = history
                unrested.setRested(false, on: today)
                if HabitEvaluation(history: unrested, today: today).recovery == .danger {
                    history = unrested
                }
            }
        }
    }

    /// Rests a habit today (or undoes the rest). Only today, only when it's scheduled and not
    /// done, and never on a danger day (`EditRules.canRest`).
    public func setRested(_ rested: Bool, habit id: HabitID, today: DayKey) throws {
        try modify(id, today: today, onlyDays: [today]) { history in
            if rested {
                guard EditRules.canRest(HabitEvaluation(history: history, today: today), on: today) else {
                    throw Failure.cannotRest
                }
            }
            history.setRested(rested, on: today)
        }
    }

    /// Accept on a suggestion card. Report letters are frozen, so a card can be out of date:
    /// it applies only if the target or schedule is still what it changes from (decided
    /// 2026-11-13); otherwise it fails and the card shows "This no longer applies."
    public func acceptSuggestion(_ suggestion: Suggestion, today: DayKey) throws {
        try modify(suggestion.habitID, today: today) { history in
            switch suggestion.change {
            case .target(let from, let to):
                guard history.target(on: today) == from else { throw Failure.suggestionNoLongerApplies }
                history.changeTarget(to: to, on: today, source: .suggested)
            case .schedule(let from, let to):
                guard history.schedule(on: today) == from else { throw Failure.suggestionNoLongerApplies }
                history.changeSchedule(to: to, on: today, source: .suggested)
            }
        }
    }

    /// Sets the daily note for `day` (same edit window as check-offs). Blank text removes it.
    public func setNote(_ text: String, on day: DayKey, today: DayKey, changeAnyway: Bool = false) throws {
        try Self.checkAccess(to: day, today: today, changeAnyway: changeAnyway)
        try database.write { db in
            let id = RowID.note(day)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try DayNoteRecord.where { $0.day.eq("\(day)") }.delete().execute(db)
            } else {
                try DayNoteRecord.upsert { DayNoteRecord(id: id, day: "\(day)", text: text) }.execute(db)
            }
        }
    }

    // MARK: Suggestions, automaticity, milestones, first-time notes

    /// "Not now" on a suggestion.
    public func dismissSuggestion(_ kind: SuggestionKind, habit id: HabitID, today: DayKey) throws {
        try database.write { db in
            let rowID = RowID.dismissal(id, kind, today)
            guard try SuggestionDismissalRecord.find(rowID).fetchOne(db) == nil else { return }
            try SuggestionDismissalRecord.insert {
                SuggestionDismissalRecord(id: rowID, habitID: id.key, kind: kind.rawValue, day: "\(today)")
            }.execute(db)
        }
    }

    /// An answer to "I do this automatically." (a second answer the same day replaces it).
    public func recordAutomaticityCheck(_ answer: Automaticity.Answer, habit id: HabitID, today: DayKey) throws {
        try database.write { db in
            try AutomaticityCheckRecord.upsert {
                AutomaticityCheckRecord(id: RowID.automaticity(id, today), habitID: id.key, day: "\(today)",
                                        answer: answer.rawValue)
            }.execute(db)
        }
    }

    public func markMilestoneSeen(_ milestone: Int, habit id: HabitID) throws {
        try database.write { db in
            let rowID = RowID.milestone(id, milestone)
            guard try MilestoneSeenRecord.find(rowID).fetchOne(db) == nil else { return }
            try MilestoneSeenRecord.insert { MilestoneSeenRecord(id: rowID, habitID: id.key, milestone: milestone) }.execute(db)
        }
    }

    public func markFirstTimeNoteSeen(_ note: FirstTimeNote) throws {
        try database.write { db in
            let rowID = RowID.firstTimeNote(note)
            guard try FirstTimeNoteSeenRecord.find(rowID).fetchOne(db) == nil else { return }
            try FirstTimeNoteSeenRecord.insert { FirstTimeNoteSeenRecord(id: rowID, note: note.rawValue) }.execute(db)
        }
    }

    // MARK: Unlocks

    /// Stores newly earned unlocks. Unlocks are never removed (spec-stamp-book.md).
    public func recordUnlocks(_ unlocks: [Unlock], at now: Date) throws {
        try database.write { db in
            for unlock in unlocks {
                let rowID = RowID.unlock(unlock)
                guard try UnlockRecord.find(rowID).fetchOne(db) == nil else { continue }
                try UnlockRecord.insert {
                    UnlockRecord(id: rowID, unlock: unlock.rawValue, unlockedAt: Mapping.text(now), noticeDismissedAt: nil, seenAt: nil)
                }.execute(db)
            }
        }
    }

    /// The "You found something" card on the note was dismissed.
    public func dismissUnlockNotice(_ unlock: Unlock, at now: Date) throws {
        try database.write { db in
            try UnlockRecord.find(RowID.unlock(unlock)).where { $0.noticeDismissedAt.is(nil) }
                .update { $0.noticeDismissedAt = #bind(Mapping.text(now)) }.execute(db)
        }
    }

    /// The Stamp book tab was visited: clears every "new" marker.
    public func markUnlocksSeen(at now: Date) throws {
        try database.write { db in
            try UnlockRecord.where { $0.seenAt.is(nil) }.update { $0.seenAt = #bind(Mapping.text(now)) }.execute(db)
        }
    }

    // MARK: Settings

    /// Changes settings (they save instantly, spec-settings.md).
    public func updateSettings(_ change: (inout AppSettings) -> Void) throws {
        try database.write { db in
            var (settings, _) = Mapping.settings(try AppSettingsRecord.find(RowID.settings).fetchOne(db))
            change(&settings)
            guard settings.isValid else { throw Failure.invalidSettings }
            try AppSettingsRecord.upsert { Mapping.record(settings) }.execute(db)
        }
    }
}

/// Everything a deleted habit had, kept in memory for the 10-second Undo.
public struct DeletedHabit: Hashable, Sendable {
    public let id: HabitID
    let habit: HabitRecord
    let schedules: [ScheduleChangeRecord]
    let targets: [TargetChangeRecord]
    let periods: [ActivePeriodRecord]
    let days: [HabitDayRecord]
    let automaticityChecks: [AutomaticityCheckRecord]
    let dismissals: [SuggestionDismissalRecord]
    let milestones: [MilestoneSeenRecord]
    /// Letters that pointed at the habit (re-linked on Undo).
    let reportIDs: [String]

    public var name: String { habit.name }
}

// MARK: - Helpers

extension Repository {
    /// Loads a habit, applies `change` to its history and stores the result. Inactive habits
    /// are read-only. With `onlyDays`, only those days' check-off/rest rows are written.
    func modify(_ id: HabitID, today: DayKey, onlyDays: [DayKey]? = nil,
                _ change: (inout HabitHistory) throws -> Void) throws {
        try database.write { db in
            let (_, history) = try Self.load(db, id)
            guard history.isActiveNow else { throw Failure.habitInactive }
            var updated = history
            try change(&updated)
            if let days = onlyDays {
                for day in Set(days) { try Self.saveDay(db, updated, day) }
            } else {
                try Self.saveChanges(db, updated)
            }
        }
    }

    static func checkAccess(to day: DayKey, today: DayKey, changeAnyway: Bool) throws {
        switch EditRules.access(to: day, today: today) {
        case .editable: break
        case .readOnly: guard changeAnyway else { throw Failure.olderDayNeedsConfirmation }
        case .future: throw Failure.futureDay
        }
    }

    static func load(_ db: Database, _ id: HabitID) throws -> (HabitRecord, HabitHistory) {
        guard let record = try HabitRecord.find(id.key).fetchOne(db) else { throw Failure.habitNotFound }
        switch history(db, record) {
        case .success(let history): return (record, history)
        case .failure(let error): throw Failure.unreadable(error)
        }
    }

    static func history(_ db: Database, _ record: HabitRecord) -> Result<HabitHistory, StoredDataError> {
        let habit = record.id
        do {
            return Mapping.history(
                record,
                schedules: try ScheduleChangeRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                targets: try TargetChangeRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                periods: try ActivePeriodRecord.where { $0.habitID.eq(habit) }.fetchAll(db),
                days: try HabitDayRecord.where { $0.habitID.eq(habit) }.fetchAll(db))
        } catch {
            return .failure(.badSnapshot("\(error)")) // unreachable for a valid schema
        }
    }

    /// Writes the schedule, target and period rows so they match `history` exactly.
    static func saveChanges(_ db: Database, _ history: HabitHistory) throws {
        let habit = history.id.key
        let rows = Mapping.changeRecords(for: history)

        let schedules = try ScheduleChangeRecord.where { $0.habitID.eq(habit) }.fetchAll(db)
        let scheduleIDs = rows.schedules.map(\.id)
        try ScheduleChangeRecord.where { $0.habitID.eq(habit) && !$0.id.in(scheduleIDs) }.delete().execute(db)
        for row in rows.schedules where !schedules.contains(row) {
            try ScheduleChangeRecord.upsert { row }.execute(db)
        }

        let targets = try TargetChangeRecord.where { $0.habitID.eq(habit) }.fetchAll(db)
        let targetIDs = rows.targets.map(\.id)
        try TargetChangeRecord.where { $0.habitID.eq(habit) && !$0.id.in(targetIDs) }.delete().execute(db)
        for row in rows.targets where !targets.contains(row) {
            try TargetChangeRecord.upsert { row }.execute(db)
        }

        let periods = try ActivePeriodRecord.where { $0.habitID.eq(habit) }.fetchAll(db)
        let periodIDs = rows.periods.map(\.id)
        try ActivePeriodRecord.where { $0.habitID.eq(habit) && !$0.id.in(periodIDs) }.delete().execute(db)
        for row in rows.periods where !periods.contains(row) {
            try ActivePeriodRecord.upsert { row }.execute(db)
        }
    }

    /// Writes `day`'s check-off/rest row so it matches `history`.
    static func saveDay(_ db: Database, _ history: HabitHistory, _ day: DayKey) throws {
        let habit = history.id.key
        let text = "\(day)"
        if let row = Mapping.dayRecord(for: history, on: day) {
            try HabitDayRecord.where { $0.habitID.eq(habit) && $0.day.eq(text) && $0.id.neq(row.id) }.delete().execute(db)
            try HabitDayRecord.upsert { row }.execute(db)
        } else {
            try HabitDayRecord.where { $0.habitID.eq(habit) && $0.day.eq(text) }.delete().execute(db)
        }
    }

    /// Habits with an open active period.
    static func activeCount(_ db: Database) throws -> Int {
        try ActivePeriodRecord.where { $0.end.is(nil) }.select { $0.habitID.count(distinct: true) }.fetchOne(db) ?? 0
    }

    static func nextSortOrder(_ db: Database) throws -> Int {
        (try HabitRecord.select { $0.sortOrder.max() }.fetchOne(db) ?? nil).map { $0 + 1 } ?? 0
    }

    static func validName(_ name: String) throws -> String {
        let name = trimmed(name)
        guard !name.isEmpty else { throw Failure.emptyName }
        return name
    }

    static func validUnit(_ unit: String) throws -> String {
        let unit = trimmed(unit)
        guard !unit.isEmpty else { throw Failure.missingUnit }
        return unit
    }

    static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func storedKind(_ kind: HabitKind) -> StoredKind {
        switch kind {
        case .amount: .amount
        case .yesNo: .yesNo
        }
    }

    static func unit(_ kind: HabitKind) -> String {
        if case .amount(let unit) = kind { unit } else { "" }
    }
}
