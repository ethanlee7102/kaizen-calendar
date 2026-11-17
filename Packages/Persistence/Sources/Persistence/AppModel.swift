import Core
import Foundation
import GRDB
import Observation

/// The app's live data for SwiftUI (MV pattern, D6): always the latest `AppData` from the
/// database, plus the Core evaluations computed from it.
///
/// Evaluations are cached per (data version, today), so views can read them freely without
/// recomputing streaks in every body (build plan, from the Phase 1 review). Writes go through
/// `repository`; the database observation then delivers the new data, including changes that
/// didn't come from this model (later, CloudKit sync).
@MainActor
@Observable
public final class AppModel {
    public let repository: Repository
    /// The latest data. Updated after every committed write.
    public private(set) var data: AppData
    /// The day check-offs belong to now (with the day-end time). Call `refreshToday()` at the
    /// day boundary, on wake, and when the clock or time zone changes.
    public private(set) var today: DayKey
    /// Every report letter, newest first (observed separately from `data`: letters change on
    /// their own, as answers are typed, and habit writes don't touch them).
    public private(set) var reports: [StoredReport] = []
    /// Why the last load failed, if it did. `data` keeps the last good value meanwhile, and
    /// the model keeps retrying.
    public private(set) var failure: String?

    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var reportObservation: AnyDatabaseCancellable?
    @ObservationIgnored private let snapshots = SnapshotCache()
    @ObservationIgnored private var dataVersion = 0
    @ObservationIgnored private var cache: (version: Int, today: DayKey, evaluations: [HabitEvaluation])?
    @ObservationIgnored private var stampCache: (version: Int, today: DayKey, book: StampBook)?
    /// How many times evaluations were computed (tests check the cache with it).
    @ObservationIgnored private(set) var evaluationRuns = 0

    /// The app's "now" (a fixed or shifted clock in UI tests and Debug time travel).
    public var currentDate: Date { now() }

    /// Starts observing the database; `data` is loaded before this returns.
    public init(repository: Repository, now: @escaping @MainActor () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
        data = AppData()
        today = AppSettings().dayEnd.day(for: now())
        observe()
        observeReports()
    }

    private func observeReports() {
        let snapshots = snapshots
        reportObservation = ValueObservation.tracking { try StoredReport.fetchAll($0, cache: snapshots).reports }.start(
            in: repository.database,
            scheduling: .immediate,
            onError: { [weak self] error in
                self?.failure = "\(error)"
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.observeReports()
                }
            },
            onChange: { [weak self] reports in
                if self?.reports != reports { self?.reports = reports }
            })
    }

    /// The letter in the envelope: the newest one that's neither opened nor filed
    /// (spec-reports.md: one envelope at a time).
    public var envelope: StoredReport? {
        reports.first { $0.isNew && $0.isUnread }
    }

    /// Delivers whatever letters are due now (launch, wake, the report time, any change).
    public func deliverDueReports() throws {
        try repository.deliverDueReports(now: now(), today: today)
    }

    /// GRDB stops an observation after an error, so it's started again after a pause instead
    /// of leaving the app frozen on old data (Phase 2 review).
    private func observe() {
        observation = ValueObservation.tracking(AppData.fetch).start(
            in: repository.database,
            scheduling: .immediate,
            onError: { [weak self] error in
                self?.failure = "\(error)"
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.observe()
                }
            },
            onChange: { [weak self] data in self?.apply(data) })
    }

    private func apply(_ data: AppData) {
        if failure != nil { failure = nil }
        self.data = data
        dataVersion += 1
        refreshToday() // the day-end setting may have changed
    }

    /// Recomputes today from the clock and the day-end setting.
    public func refreshToday() {
        let day = data.settings.dayEnd.day(for: now())
        if day != today { today = day }
    }

    /// Readable habits (active and inactive) evaluated as of today, in list order.
    public var evaluations: [HabitEvaluation] {
        let data = data, today = today // read through observation, so views update
        if let cache, cache.version == dataVersion, cache.today == today { return cache.evaluations }
        let evaluations = data.readableHabits.map { HabitEvaluation(history: $0.history, today: today) }
        evaluationRuns += 1
        cache = (dataVersion, today, evaluations)
        return evaluations
    }

    /// Active habits in list order (the note's rows). Active means an open active period, the
    /// same rule the repository uses, so a habit doesn't vanish if today moves backwards.
    public var activeEvaluations: [HabitEvaluation] {
        evaluations.filter(\.history.isActiveNow)
    }

    /// Stamp days so far (spec-stamp-book.md), cached like `evaluations`: it scans every day
    /// since the first habit started.
    public var stampBook: StampBook {
        let evaluations = evaluations // also reads data and today through observation
        if let stampCache, stampCache.version == dataVersion, stampCache.today == today { return stampCache.book }
        let book = StampBook(evaluations: evaluations, today: today)
        stampCache = (dataVersion, today, book)
        return book
    }

    /// Unlocks the current stamp count has earned that aren't stored yet. Store them with
    /// `Repository.recordUnlocks`; they're never taken back.
    public var newUnlocks: [Unlock] {
        stampBook.newUnlocks(alreadyUnlocked: Set(data.unlocks.map(\.unlock)))
    }

    public func evaluation(of id: HabitID) -> HabitEvaluation? {
        evaluations.first { $0.id == id }
    }
}
