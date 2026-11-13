import Core
import Foundation
@testable import Persistence
import Testing

@MainActor
@Suite struct AppModelTests {
    /// 1:30am on Saturday Nov 14, 2026, in the Mac's time zone.
    static let lateNight: Date = DayClock().date(on: d("2026-11-14"), hour: 1, minute: 30)

    /// Waits (briefly) for the database observation to deliver a change.
    func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }

    @Test func loadsBeforeInitReturns() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13"))
        let model = AppModel(repository: repo, now: { Self.lateNight })
        #expect(model.data.habits.map(\.id) == [id])
        #expect(model.failure == nil)
    }

    @Test func followsWritesAndRecomputesEvaluations() async throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13"))
        let model = AppModel(repository: repo, now: { Self.lateNight })
        #expect(model.today == d("2026-11-14"))
        #expect(model.evaluation(of: id)?.isOpenToday == true)

        try model.repository.setDone(true, habit: id, on: d("2026-11-14"), today: model.today)
        try await eventually { model.evaluation(of: id)?.status(on: d("2026-11-14")) == .done }
        #expect(model.evaluation(of: id)?.currentStreak == 1)
    }

    /// "My day ends at 2am": at 1:30am it's still Friday.
    @Test func dayEndSettingMovesToday() async throws {
        let repo = try makeRepository()
        let model = AppModel(repository: repo, now: { Self.lateNight })
        #expect(model.today == d("2026-11-14"))
        try repo.updateSettings { $0.dayEndHour = 2 }
        try await eventually { model.today == d("2026-11-13") }
    }

    @Test func evaluationsAreCachedUntilDataOrTodayChanges() async throws {
        let repo = try makeRepository()
        try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-10"))
        var now = Self.lateNight
        let model = AppModel(repository: repo, now: { now })
        #expect(model.evaluations.map(\.today) == [d("2026-11-14")])
        _ = model.evaluations
        _ = model.activeEvaluations
        #expect(model.evaluationRuns == 1)

        // A new day recomputes once.
        now = DayClock().date(on: d("2026-11-15"), hour: 9, minute: 0)
        model.refreshToday()
        #expect(model.evaluations.map(\.today) == [d("2026-11-15")])
        _ = model.evaluations
        #expect(model.evaluationRuns == 2)

        // So does new data.
        try repo.setNote("hi", on: d("2026-11-15"), today: d("2026-11-15"))
        try await eventually { model.data.notes[d("2026-11-15")] == "hi" }
        _ = model.evaluations
        _ = model.evaluations
        #expect(model.evaluationRuns == 3)
    }

    @Test func activeEvaluationsSkipInactiveAndUnreadableHabits() async throws {
        let repo = try makeRepository()
        let read = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        let walk = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        let gym = try repo.addHabit(name: "Gym", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        try repo.deactivate(walk, today: d("2026-11-10"))
        try repo.execute("UPDATE habits SET createdDay = 'bad' WHERE name = 'Gym'")

        let model = AppModel(repository: repo, now: { Self.lateNight })
        #expect(model.evaluations.map(\.id) == [read, walk])
        #expect(model.activeEvaluations.map(\.id) == [read])
        #expect(model.data.habit(gym)?.history == .failure(.badDay(table: "habits", value: "bad")))
    }
}
