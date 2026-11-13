import Core
import Foundation
import SQLiteData

/// A report letter exactly as it was written on its delivery day (spec-reports.md: archived
/// letters are read-only and never change). It carries the habits' names as they were then,
/// so renaming or deleting a habit later doesn't change it.
public struct ReportSnapshot: Hashable, Sendable, Codable {
    /// Bump when the stored JSON changes shape; old versions must stay readable.
    public static let currentVersion = 1

    public enum Content: Hashable, Sendable, Codable {
        case weekly(WeeklyReport)
        case monthly(MonthlyReport)
        case day66(Day66Report)
    }

    /// A habit's name and kind as of delivery.
    public struct HabitLabel: Hashable, Sendable, Codable {
        public let name: String
        public let identity: String?
        public let kind: HabitKind
    }

    public let version: Int
    public let deliveryDay: DayKey
    public let habits: [HabitID: HabitLabel]
    public let content: Content

    public var kind: ReportKind {
        switch content {
        case .weekly: .weekly
        case .monthly: .monthly
        case .day66: .day66
        }
    }

    /// The days a weekly or monthly letter covers.
    public var period: DayRange? {
        switch content {
        case .weekly(let report): report.sections.period
        case .monthly(let report): report.sections.period
        case .day66: nil
        }
    }

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
    public let snapshot: Result<ReportSnapshot, StoredDataError>
    public let answers: [ReportQuestion: String]

    public var isUnread: Bool { openedAt == nil }
    /// Still in the envelope (or open, not yet filed).
    public var isNew: Bool { filedAt == nil }

    /// All letters, newest first. Rows that can't be read are skipped and returned as problems.
    public static func fetchAll(_ db: Database) throws -> (reports: [StoredReport], problems: [StoredDataProblem]) {
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
                return StoredReport(
                    id: try Mapping.uuid(row.id, in: "reports", column: "id"),
                    kind: try Mapping.value(row.kind, in: "reports", column: "kind"),
                    deliveryDay: try Mapping.day(row.deliveryDay, in: "reports"),
                    deliveredAt: try Mapping.date(row.deliveredAt, in: "reports", column: "deliveredAt"),
                    openedAt: try date(row.openedAt, "openedAt"), filedAt: try date(row.filedAt, "filedAt"),
                    snapshot: ReportSnapshot.decode(row.snapshot), answers: answers[row.id] ?? [:])
            } catch {
                problems.append(StoredDataProblem(table: "reports", rowID: row.id, error: error))
                return nil
            }
        }
        return (reports, problems)
    }
}

extension Repository {
    /// Stores a letter at delivery. Delivering the same letter again (same week, or the same
    /// habit's day 66) does nothing, so a letter is never rewritten or duplicated.
    ///
    /// One envelope at a time (spec-reports.md): older letters still unopened go to the archive
    /// as unread, and a letter older than one already delivered goes straight to the archive.
    @discardableResult
    public func deliver(_ snapshot: ReportSnapshot, at now: Date) throws -> UUID {
        let id: String
        var habitID: String?
        switch snapshot.content {
        case .weekly(let report): id = RowID.report(.weekly, periodEnd: report.sections.period.end)
        case .monthly(let report): id = RowID.report(.monthly, periodEnd: report.sections.period.end)
        case .day66(let report):
            id = RowID.day66Report(report.habitID)
            habitID = report.habitID.key
        }
        let json = try snapshot.json()
        let day = "\(snapshot.deliveryDay)"
        let moment = Mapping.text(now)
        try database.write { db in
            guard try ReportRecord.find(id).fetchOne(db) == nil else { return }
            if let habit = habitID, try HabitRecord.find(habit).fetchOne(db) == nil { habitID = nil }
            let isOlder = try ReportRecord.where { $0.deliveryDay > day }.fetchCount(db) > 0
            if !isOlder {
                try ReportRecord.where { $0.deliveryDay <= day && $0.openedAt.is(nil) && $0.filedAt.is(nil) }
                    .update { $0.filedAt = #bind(moment) }.execute(db)
            }
            let row = ReportRecord(
                id: id, kind: snapshot.kind.rawValue, periodStart: snapshot.period.map { "\($0.start)" },
                periodEnd: snapshot.period.map { "\($0.end)" }, habitID: habitID, deliveryDay: day,
                deliveredAt: moment, openedAt: nil, filedAt: isOlder ? moment : nil, snapshot: json)
            try ReportRecord.insert { row }.execute(db)
        }
        return UUID(uuidString: id)! // always valid: made by StableID
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
            guard let report = try ReportRecord.find(id).fetchOne(db) else { throw Failure.reportNotFound }
            guard report.filedAt == nil else { throw Failure.reportFiled }
            guard ReportKind(rawValue: report.kind)?.questions.contains(question) == true else {
                throw Failure.questionNotInReport
            }
            let rowID = RowID.answer(id, question)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try ReportAnswerRecord.find(rowID).delete().execute(db)
            } else {
                try ReportAnswerRecord.upsert {
                    ReportAnswerRecord(id: rowID, reportID: id, question: question.rawValue, text: text)
                }.execute(db)
            }
        }
    }
}
