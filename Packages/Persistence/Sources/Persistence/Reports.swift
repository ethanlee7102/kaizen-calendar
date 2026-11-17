import Core
import Foundation
import SQLiteData
import Synchronization

/// A report letter exactly as it was written on its delivery day (spec-reports.md: archived
/// letters are read-only and never change). It carries the habits' names as they were then,
/// so renaming or deleting a habit later doesn't change it.
public struct ReportSnapshot: Hashable, Sendable, Codable {
    /// Bump when the stored JSON changes shape; old versions must stay readable.
    public static let currentVersion = 1

    public typealias Content = ReportContent
    /// A habit's name and kind as of delivery.
    public typealias HabitLabel = ReportHabitLabel

    public let version: Int
    public let deliveryDay: DayKey
    public let habits: [HabitID: HabitLabel]
    public let content: Content

    public var kind: ReportKind { content.kind }

    /// The days a weekly or monthly letter covers.
    public var period: DayRange? { content.period }

    // MARK: Writing a letter

    /// The weekly letter for `due`, as of its delivery day.
    public static func weekly(_ due: DueReport, data: AppData, previousObstacle: String?) -> ReportSnapshot {
        let (evaluations, labels) = asOf(due.deliveryDay, data)
        return ReportSnapshot(
            version: currentVersion, deliveryDay: due.deliveryDay, habits: labels,
            content: .weekly(WeeklyReport(period: due.period, evaluations: evaluations, notes: data.dayNotes,
                                          dismissals: dismissals(data, through: due.deliveryDay),
                                          previousObstacle: previousObstacle)))
    }

    /// The monthly letter for `due`, as of its delivery day.
    public static func monthly(_ due: DueReport, data: AppData) -> ReportSnapshot {
        let (evaluations, labels) = asOf(due.deliveryDay, data)
        return ReportSnapshot(
            version: currentVersion, deliveryDay: due.deliveryDay, habits: labels,
            content: .monthly(MonthlyReport(period: due.period, evaluations: evaluations, notes: data.dayNotes,
                                            dismissals: dismissals(data, through: due.deliveryDay))))
    }

    /// The day-66 letter for a habit, as of `deliveryDay`; nil if it hasn't reached day 66 by then.
    public static func day66(habit id: HabitID, deliveryDay: DayKey, data: AppData) -> ReportSnapshot? {
        let (evaluations, labels) = asOf(deliveryDay, data)
        let notes = data.dayNotes.filter { $0.day <= deliveryDay }
        guard let evaluation = evaluations.first(where: { $0.id == id }),
              let report = Day66Report(evaluation: evaluation, notes: notes),
              let label = labels[id]
        else { return nil }
        return ReportSnapshot(version: currentVersion, deliveryDay: deliveryDay, habits: [id: label], content: .day66(report))
    }

    /// The automaticity re-check letter for a habit, as of `deliveryDay` (decided in the Phase 6
    /// build: its own letter); nil if the habit didn't exist then.
    public static func recheck(habit id: HabitID, deliveryDay: DayKey, data: AppData,
                               previousAnswer: Automaticity.Answer?) -> ReportSnapshot? {
        let (evaluations, labels) = asOf(deliveryDay, data)
        guard let evaluation = evaluations.first(where: { $0.id == id }), let label = labels[id] else { return nil }
        let report = RecheckReport(habitID: id, dayCount: evaluation.journey.count, previousAnswer: previousAnswer)
        return ReportSnapshot(version: currentVersion, deliveryDay: deliveryDay, habits: [id: label], content: .recheck(report))
    }

    /// Readable habits that existed on `day`, evaluated as of that day, in list order.
    private static func asOf(_ day: DayKey, _ data: AppData) -> ([HabitEvaluation], [HabitID: HabitLabel]) {
        let habits = data.readableHabits.filter { $0.history.createdDay <= day }
        let evaluations = habits.map { HabitEvaluation(history: $0.history, today: day) }
        let labels = Dictionary(uniqueKeysWithValues: habits.map {
            ($0.habit.id, HabitLabel(name: $0.habit.name, identity: $0.habit.identity, kind: $0.history.kind))
        })
        return (evaluations, labels)
    }

    private static func dismissals(_ data: AppData, through day: DayKey) -> [HabitID: [SuggestionDismissal]] {
        data.dismissals.mapValues { $0.filter { $0.day <= day } }
    }

    // MARK: JSON

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    static func decode(_ json: String) -> Result<ReportSnapshot, StoredDataError> {
        do {
            let snapshot = try JSONDecoder().decode(ReportSnapshot.self, from: Data(json.utf8))
            guard snapshot.version <= currentVersion else {
                return .failure(.badSnapshot("written by a newer version (\(snapshot.version))"))
            }
            return .success(snapshot)
        } catch {
            return .failure(.badSnapshot("\(error)"))
        }
    }
}

/// A delivered report letter and what happened to it.
public struct StoredReport: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let kind: ReportKind
    public let deliveryDay: DayKey
    public let deliveredAt: Date
    public let openedAt: Date?
    /// "Done" was clicked, or a newer letter replaced it in the envelope (unopened = unread).
    public let filedAt: Date?
    /// The days a weekly or monthly letter covers (stored beside the snapshot, so delivery can
    /// still tell which weeks are covered if a snapshot can't be read).
    public let period: DayRange?
    /// The habit a day-66 or re-check letter is about; nil once that habit is deleted.
    public let habitID: HabitID?
    public let snapshot: Result<ReportSnapshot, StoredDataError>
    public let answers: [ReportQuestion: String]

    public var isUnread: Bool { openedAt == nil }
    /// Still in the envelope (or open, not yet filed).
    public var isNew: Bool { filedAt == nil }

    /// The automaticity answer given in this letter.
    public var automaticity: Automaticity.Answer? {
        answers[.automaticity].flatMap(Int.init).flatMap(Automaticity.Answer.init(rawValue:))
    }

    /// The decision made in this letter.
    public var decision: LetterDecision? { answers[.decision].flatMap(LetterDecision.init(rawValue:)) }

    /// All letters, newest first. Rows that can't be read are skipped and returned as problems.
    /// With `cache`, a letter's JSON is decoded only the first time it's seen (letters never
    /// change, and this runs again on every answer typed: Phase 6 review).
    public static func fetchAll(_ db: Database, cache: SnapshotCache? = nil)
        throws -> (reports: [StoredReport], problems: [StoredDataProblem]) {
        var problems: [StoredDataProblem] = []
        var answers: [String: [ReportQuestion: String]] = [:]
        for row in try ReportAnswerRecord.all.fetchAll(db) {
            if let question = ReportQuestion(rawValue: row.question) {
                answers[row.reportID, default: [:]][question] = row.text
            } else {
                problems.append(StoredDataProblem(table: "reportAnswers", rowID: row.id,
                                                  error: .unknownValue(table: "reportAnswers", column: "question", value: row.question)))
            }
        }
        // Newest first by the day it was due: letters caught up together share a delivery moment.
        let rows = try ReportRecord.order { ($0.deliveryDay.desc(), $0.deliveredAt.desc(), $0.kind, $0.id) }.fetchAll(db)
        let reports = rows.compactMap { row -> StoredReport? in
            do throws(StoredDataError) {
                func date(_ text: String?, _ column: String) throws(StoredDataError) -> Date? {
                    guard let text else { return nil }
                    return try Mapping.date(text, in: "reports", column: column)
                }
                var period: DayRange?
                if let start = row.periodStart, let end = row.periodEnd {
                    let (first, last) = (try Mapping.day(start, in: "reports"), try Mapping.day(end, in: "reports"))
                    guard first <= last else { throw .badDay(table: "reports", value: "\(start)…\(end)") }
                    period = DayRange(first, last)
                }
                return StoredReport(
                    id: try Mapping.uuid(row.id, in: "reports", column: "id"),
                    kind: try Mapping.value(row.kind, in: "reports", column: "kind"),
                    deliveryDay: try Mapping.day(row.deliveryDay, in: "reports"),
                    deliveredAt: try Mapping.date(row.deliveredAt, in: "reports", column: "deliveredAt"),
                    openedAt: try date(row.openedAt, "openedAt"), filedAt: try date(row.filedAt, "filedAt"),
                    period: period,
                    habitID: try row.habitID.map { text throws(StoredDataError) in
                        HabitID(try Mapping.uuid(text, in: "reports", column: "habitID"))
                    },
                    snapshot: cache?.snapshot(row.id, json: row.snapshot) ?? ReportSnapshot.decode(row.snapshot),
                    answers: answers[row.id] ?? [:])
            } catch {
                problems.append(StoredDataProblem(table: "reports", rowID: row.id, error: error))
                return nil
            }
        }
        return (reports, problems)
    }
}

/// Decoded letters by row, so the letters observation doesn't decode every letter's JSON again
/// on each change. Keyed by the JSON too, so a letter that did change (sync) is decoded afresh.
public final class SnapshotCache: Sendable {
    private let entries = Mutex<[String: (json: String, snapshot: Result<ReportSnapshot, StoredDataError>)]>([:])

    public init() {}

    func snapshot(_ id: String, json: String) -> Result<ReportSnapshot, StoredDataError> {
        if let entry = entries.withLock({ $0[id] }), entry.json == json { return entry.snapshot }
        let snapshot = ReportSnapshot.decode(json)
        entries.withLock { $0[id] = (json, snapshot) }
        return snapshot
    }
}

/// What delivery needs to know about a letter already delivered: no JSON is decoded (delivery
/// runs after every write: Phase 6 review).
public struct DeliveredLetter: Hashable, Sendable {
    public let kind: ReportKind
    public let deliveryDay: DayKey
    public let deliveredAt: Date
    public let period: DayRange?
    public let habitID: HabitID?
    public let obstacle: String?

    public init(kind: ReportKind, deliveryDay: DayKey, deliveredAt: Date, period: DayRange?, habitID: HabitID?,
                obstacle: String?) {
        self.kind = kind
        self.deliveryDay = deliveryDay
        self.deliveredAt = deliveredAt
        self.period = period
        self.habitID = habitID
        self.obstacle = obstacle
    }

    /// Rows that can't be read are skipped (they're reported by `StoredReport.fetchAll`).
    static func fetchAll(_ db: Database) throws -> [DeliveredLetter] {
        var obstacles: [String: String] = [:]
        for row in try ReportAnswerRecord.where({ $0.question.eq(ReportQuestion.obstacle.rawValue) }).fetchAll(db) {
            obstacles[row.reportID] = row.text
        }
        return try ReportRecord.all.fetchAll(db).compactMap { row in
            guard let kind = ReportKind(rawValue: row.kind), let day = DayKey(row.deliveryDay),
                  let at = try? Mapping.date(row.deliveredAt, in: "reports", column: "deliveredAt") else { return nil }
            let period = row.periodStart.flatMap(DayKey.init).flatMap { start in
                row.periodEnd.flatMap(DayKey.init).flatMap { start <= $0 ? DayRange(start, $0) : nil }
            }
            return DeliveredLetter(kind: kind, deliveryDay: day, deliveredAt: at, period: period,
                                   habitID: row.habitID.flatMap(UUID.init(uuidString:)).map(HabitID.init),
                                   obstacle: obstacles[row.id])
        }
    }
}

/// Which letters are due (spec-reports.md, Delivery; decided in the Phase 6 build):
/// - weekly and monthly letters at the report time (Core's `ReportSchedule`), caught up after
///   the Mac was off, oldest first;
/// - a day-66 letter as soon as an active habit has 66 done days and none was written for it;
/// - a re-check letter about 3 weeks after a habit's latest day-66 or re-check letter, while
///   it's active (`Automaticity.recheckDay`), whatever was decided (user's choice);
/// - no weekly or monthly letter for a period when no habit was active (user's choice after the
///   Phase 6 review).
///
/// Day-66 and re-check letters are dated the later of today and the calendar day, so with a
/// day-end time after midnight they're never older than a weekly letter delivered at 12:30am
/// (which would send them straight to the archive: Phase 6 review).
///
/// Pure: the repository delivers what this returns, in this order, so the newest letter ends up
/// in the envelope (a day-66 or re-check letter wins over a weekly one due the same day).
public enum ReportDelivery {
    public static func due(data: AppData, reports: [DeliveredLetter], now: Date, today: DayKey,
                           timeZone: TimeZone = .autoupdatingCurrent) -> [ReportSnapshot] {
        var due: [ReportSnapshot] = []
        let habits = data.readableHabits
        let clock = DayClock(timeZone: timeZone)

        // Weekly and monthly.
        if let firstUseDay = habits.map(\.history.createdDay).min() {
            let periodic = reports.filter { $0.kind == .weekly || $0.kind == .monthly }
            let schedule = ReportSchedule(settings: data.settings.report, clock: clock)
            let reportsDue = schedule.dueReports(
                lastCoveredWeekEnd: periodic.compactMap(\.period?.end).max(),
                lastMonthlyPeriodEnd: periodic.filter { $0.kind == .monthly }.compactMap(\.period?.end).max(),
                firstUseDay: firstUseDay, now: now)
            for report in reportsDue where habits.contains(where: { _, history in
                report.period.contains { history.isActive(on: $0) }
            }) {
                switch report.kind {
                case .weekly:
                    due.append(.weekly(report, data: data,
                                       previousObstacle: lastObstacle(before: report.deliveryDay, in: reports)))
                case .monthly:
                    due.append(.monthly(report, data: data))
                }
            }
        }

        // Day 66 and re-checks, for habits active now.
        let letterDay = max(today, clock.calendarDay(for: now))
        for (_, history) in habits where history.isActiveNow {
            let journey = HabitEvaluation(history: history, today: today).journey
            guard journey.hasReached66 else { continue }
            let letters = reports.filter { $0.habitID == history.id && $0.kind.asksAutomaticity }
            if !letters.contains(where: { $0.kind == .day66 }) {
                if let letter = ReportSnapshot.day66(habit: history.id, deliveryDay: letterDay, data: data) { due.append(letter) }
            } else if let day = Automaticity.recheckDay(lastLetterDay: letters.map(\.deliveryDay).max(), history: history),
                      day <= today,
                      let letter = ReportSnapshot.recheck(habit: history.id, deliveryDay: letterDay, data: data,
                                                          previousAnswer: data.automaticityChecks[history.id]?.last?.answer) {
                due.append(letter)
            }
        }
        return due
    }

    /// "The next weekly report shows the last obstacle answer the user wrote, even if that was
    /// from 2 weeks before" (spec-reports.md).
    static func lastObstacle(before day: DayKey, in reports: [DeliveredLetter]) -> String? {
        reports
            .filter { $0.deliveryDay < day && $0.obstacle != nil }
            .max { ($0.deliveryDay, $0.deliveredAt) < ($1.deliveryDay, $1.deliveredAt) }?
            .obstacle
    }
}

extension Repository {
    /// Delivers every letter that's due now (`ReportDelivery`), in one transaction. Safe to call
    /// often (launch, wake, the report time, any change): a letter is written only once.
    /// Returns how many were delivered.
    @discardableResult
    public func deliverDueReports(now: Date, today: DayKey, timeZone: TimeZone = .autoupdatingCurrent) throws -> Int {
        try database.write { db in
            let data = try AppData.fetch(db)
            let reports = try DeliveredLetter.fetchAll(db)
            let due = ReportDelivery.due(data: data, reports: reports, now: now, today: today, timeZone: timeZone)
            var delivered = 0
            for snapshot in due where try Self.insert(snapshot, at: now, db) { delivered += 1 }
            return delivered
        }
    }

    /// Stores a letter at delivery. Delivering the same letter again (same week, the same
    /// habit's day 66, or its re-check on the same day) does nothing, so a letter is never
    /// rewritten or duplicated.
    ///
    /// One envelope at a time (spec-reports.md): older letters still unopened go to the archive
    /// as unread, and a letter older than one already delivered goes straight to the archive.
    @discardableResult
    public func deliver(_ snapshot: ReportSnapshot, at now: Date) throws -> UUID {
        try database.write { db in _ = try Self.insert(snapshot, at: now, db) }
        return UUID(uuidString: Self.rowID(snapshot))! // always valid: made by StableID
    }

    static func rowID(_ snapshot: ReportSnapshot) -> String {
        switch snapshot.content {
        case .weekly(let report): RowID.report(.weekly, periodEnd: report.sections.period.end)
        case .monthly(let report): RowID.report(.monthly, periodEnd: report.sections.period.end)
        case .day66(let report): RowID.day66Report(report.habitID)
        case .recheck(let report): RowID.recheckReport(report.habitID, snapshot.deliveryDay)
        }
    }

    /// Inserts the letter unless it exists. Returns whether it was inserted.
    static func insert(_ snapshot: ReportSnapshot, at now: Date, _ db: Database) throws -> Bool {
        let id = rowID(snapshot)
        guard try ReportRecord.find(id).fetchOne(db) == nil else { return false }
        var habitID = snapshot.content.habitID?.key
        if let habit = habitID, try HabitRecord.find(habit).fetchOne(db) == nil { habitID = nil }
        let day = "\(snapshot.deliveryDay)"
        let moment = Mapping.text(now)
        let isOlder = try ReportRecord.where { $0.deliveryDay > day }.fetchCount(db) > 0
        if !isOlder {
            try ReportRecord.where { $0.deliveryDay <= day && $0.openedAt.is(nil) && $0.filedAt.is(nil) }
                .update { $0.filedAt = #bind(moment) }.execute(db)
        }
        let row = ReportRecord(
            id: id, kind: snapshot.kind.rawValue, periodStart: snapshot.period.map { "\($0.start)" },
            periodEnd: snapshot.period.map { "\($0.end)" }, habitID: habitID, deliveryDay: day,
            deliveredAt: moment, openedAt: nil, filedAt: isOlder ? moment : nil, snapshot: try snapshot.json())
        try ReportRecord.insert { row }.execute(db)
        return true
    }

    public func reports() throws -> [StoredReport] {
        try database.read { try StoredReport.fetchAll($0).reports }
    }

    /// The letter was opened (clears "unread"). Only the first time counts.
    public func markReportOpened(_ id: UUID, at now: Date) throws {
        let id = StableID.key(id)
        try database.write { db in
            guard try ReportRecord.find(id).fetchOne(db) != nil else { throw Failure.reportNotFound }
            try ReportRecord.find(id).where { $0.openedAt.is(nil) }.update { $0.openedAt = #bind(Mapping.text(now)) }.execute(db)
        }
    }

    /// "Done", or replaced in the envelope by a newer letter: moves it to the archive.
    public func fileReport(_ id: UUID, at now: Date) throws {
        let id = StableID.key(id)
        try database.write { db in
            guard try ReportRecord.find(id).fetchOne(db) != nil else { throw Failure.reportNotFound }
            try ReportRecord.find(id).where { $0.filedAt.is(nil) }.update { $0.filedAt = #bind(Mapping.text(now)) }.execute(db)
        }
    }

    /// Saves an answer as it's typed. Blank text removes it. Only while the letter isn't filed
    /// (archived letters are read-only), and only to a question that kind of letter asks.
    public func setAnswer(_ text: String, to question: ReportQuestion, report id: UUID) throws {
        let id = StableID.key(id)
        try database.write { db in
            let report = try Self.openLetter(id, db)
            guard ReportKind(rawValue: report.kind)?.questions.contains(question) == true else {
                throw Failure.questionNotInReport
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try ReportAnswerRecord.find(RowID.answer(id, question)).delete().execute(db)
            } else {
                try Self.saveAnswer(text, question, report: id, db)
            }
        }
    }

    /// "I do this automatically." in a day-66 or re-check letter: kept with the letter and in the
    /// habit's automaticity history (a second answer the same day replaces it). It can change
    /// until the decision is made (`undecidedLetter`).
    public func answerAutomaticity(_ answer: Automaticity.Answer, report id: UUID, today: DayKey) throws {
        let id = StableID.key(id)
        try database.write { db in
            let (_, habit) = try Self.undecidedLetter(id, db)
            try Self.saveAnswer(String(answer.rawValue), .automaticity, report: id, db)
            try AutomaticityCheckRecord.upsert {
                AutomaticityCheckRecord(id: RowID.automaticity(habit.id, today), habitID: habit.id.key,
                                        day: "\(today)", answer: answer.rawValue)
            }.execute(db)
        }
    }

    /// The decision at the end of a day-66 or re-check letter: Graduate (inactive as Graduated
    /// ✓66), Keep going, or a new target or schedule from today. One decision per letter, on a
    /// habit that's still active (`undecidedLetter`); it's applied and recorded together.
    public func decide(_ choice: LetterChoice, report id: UUID, today: DayKey) throws {
        let id = StableID.key(id)
        try database.write { db in
            let (_, history) = try Self.undecidedLetter(id, db)
            var updated = history
            switch choice {
            case .graduate:
                updated.deactivate(on: today, reason: .graduated)
            case .keepGoing:
                break
            case .changeTarget(let amount):
                guard case .amount = history.kind else { throw Failure.notAnAmountHabit }
                guard amount >= 1 else { throw Failure.invalidTarget }
                updated.changeTarget(to: amount, on: today, source: .manual)
            case .changeSchedule(let schedule):
                updated.changeSchedule(to: schedule, on: today, source: .manual)
            }
            try Self.saveChanges(db, updated)
            try Self.saveAnswer(choice.decision.rawValue, .decision, report: id, db)
        }
    }

    /// A day-66 or re-check letter whose decision isn't made yet, and its habit (active). It may
    /// be filed: a newer letter can replace it in the envelope before it's opened, and the
    /// decision must not be lost (user's choice after the Phase 6 review).
    private static func undecidedLetter(_ id: String, _ db: Database) throws -> (ReportRecord, HabitHistory) {
        guard let report = try ReportRecord.find(id).fetchOne(db) else { throw Failure.reportNotFound }
        guard ReportKind(rawValue: report.kind)?.asksAutomaticity == true else { throw Failure.questionNotInReport }
        guard try ReportAnswerRecord.find(RowID.answer(id, .decision)).fetchOne(db) == nil else {
            throw Failure.alreadyDecided
        }
        guard let habit = report.habitID.flatMap(UUID.init(uuidString:)).map(HabitID.init) else {
            throw Failure.habitNotFound
        }
        let (_, history) = try load(db, habit)
        guard history.isActiveNow else { throw Failure.habitInactive }
        return (report, history)
    }

    /// A letter that isn't filed yet (filed letters are read-only).
    private static func openLetter(_ id: String, _ db: Database) throws -> ReportRecord {
        guard let report = try ReportRecord.find(id).fetchOne(db) else { throw Failure.reportNotFound }
        guard report.filedAt == nil else { throw Failure.reportFiled }
        return report
    }

    private static func saveAnswer(_ text: String, _ question: ReportQuestion, report id: String, _ db: Database) throws {
        try ReportAnswerRecord.upsert {
            ReportAnswerRecord(id: RowID.answer(id, question), reportID: id, question: question.rawValue, text: text)
        }.execute(db)
    }
}
