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
    /// Why the last load failed, if it did. `data` keeps the last good value meanwhile, and
    /// the model keeps retrying.
    public private(set) var failure: String?

    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var dataVersion = 0
    @ObservationIgnored private var cache: (version: Int, today: DayKey, evaluations: [HabitEvaluation])?
    /// How many times evaluations were computed (tests check the cache with it).
    @ObservationIgnored private(set) var evaluationRuns = 0

    /// Starts observing the database; `data` is loaded before this returns.
    public init(repository: Repository, now: @escaping @MainActor () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
        data = AppData()
        today = AppSettings().dayClock.day(for: now())
        observe()
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
        let day = data.settings.dayClock.day(for: now())
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

    public func evaluation(of id: HabitID) -> HabitEvaluation? {
        evaluations.first { $0.id == id }
    }
}
