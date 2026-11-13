import Core
import Foundation
@testable import Persistence
import SQLiteData
import Testing

/// Regression tests for the Phase 2 code review (2026-11-13). Each one reproduced its bug
/// before the fix and was mutation-checked after it.
@Suite struct ReviewRegressionTests {
    // MARK: 1. Rest, then uncheck yesterday

    /// Resting today and then unchecking yesterday made yesterday a miss while today stayed
    /// rested, pushing the second miss a day later (dodging never-miss-twice). The rest is now
    /// cleared in the same step (decided 2026-11-13).
    @Test func uncheckingYesterdayClearsARestThatWouldDodgeTheDangerDay() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        for day in d("2026-11-01")...d("2026-11-04") { try repo.setDone(true, habit: id, on: day, today: day) }
        let today = d("2026-11-05")
        try repo.setRested(true, habit: id, today: today)

        try repo.setDone(false, habit: id, on: d("2026-11-04"), today: today)
        let history = try repo.history(id)
        #expect(history.rests.isEmpty)
        #expect(HabitEvaluation(history: history, today: today).recovery == .danger)
    }

    @Test func uncheckingAnOlderDayKeepsARestThatIsStillAllowed() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        for day in d("2026-11-01")...d("2026-11-04") { try repo.setDone(true, habit: id, on: day, today: day) }
        let today = d("2026-11-05")
        try repo.setRested(true, habit: id, today: today)
        // Nov 3 becomes a miss recovered by Nov 4: today isn't a danger day, the rest stays.
        try repo.setDone(false, habit: id, on: d("2026-11-03"), today: today)
        #expect(try repo.history(id).rests == [today])
    }

    // MARK: 2. One malformed UUID or date blanked everything

    @Test func aMalformedDateOrIDSkipsOnlyThatRow() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        try repo.recordUnlocks([.darkMode], at: Date(timeIntervalSince1970: 1_800_000_000))
        try repo.markFirstTimeNoteSeen(.rest)
        try repo.markFirstTimeNoteSeen(.recovery)
        try repo.execute("UPDATE unlocks SET unlockedAt = 'not a date'")
        try repo.execute("UPDATE firstTimeNotesSeen SET id = 'xyz' WHERE note = 'rest'")

        let data = try repo.appData()
        #expect(data.habits.map(\.id) == [id])
        #expect(data.unlocks.isEmpty)
        #expect(data.firstTimeNotesSeen == [.recovery])
        #expect(Set(data.problems.map(\.table)) == ["unlocks", "firstTimeNotesSeen"])
    }

    @Test func aMalformedReportRowSkipsOnlyThatLetter() throws {
        let repo = try makeRepository()
        try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-10-04"))
        let data = try repo.appData()
        let clock = DayClock(timeZone: TimeZone(identifier: "UTC")!)
        let due = ReportSchedule(clock: clock).dueReports(lastCoveredWeekEnd: nil, lastMonthlyPeriodEnd: nil, firstUseDay: d("2026-10-04"),
                                                          now: clock.date(on: d("2026-10-18"), hour: 19, minute: 0))
        for report in due { try repo.deliver(ReportSnapshot.weekly(report, data: data, previousObstacle: nil), at: Date()) }
        try repo.execute("UPDATE reports SET deliveredAt = 'yesterday' WHERE deliveryDay = '2026-10-11'")
        #expect(try repo.reports().map(\.deliveryDay) == [d("2026-10-18")])
    }

    @MainActor
    @Test func theModelKeepsUpdatingAfterACorruptRowAppears() async throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13"))
        let model = AppModel(repository: repo, now: { DayClock().date(on: d("2026-11-13"), hour: 9, minute: 0) })
        try repo.recordUnlocks([.darkMode], at: Date())
        try repo.execute("UPDATE unlocks SET seenAt = 'garbage'")
        try repo.setDone(true, habit: id, on: d("2026-11-13"), today: d("2026-11-13"))
        for _ in 0..<200 where model.evaluation(of: id)?.status(on: d("2026-11-13")) != .done {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.evaluation(of: id)?.status(on: d("2026-11-13")) == .done)
        #expect(model.data.problems.map(\.table) == ["unlocks"])
        #expect(model.failure == nil)
    }

    /// If loading fails outright (here: a table goes missing), the model keeps its last data,
    /// reports the failure, and recovers once loading works again. GRDB stops an observation
    /// after an error, so before the fix the model froze for good.
    @MainActor
    @Test func theModelRecoversAfterALoadError() async throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13"))
        let model = AppModel(repository: repo, now: { DayClock().date(on: d("2026-11-13"), hour: 9, minute: 0) })
        try repo.execute("ALTER TABLE firstTimeNotesSeen RENAME TO hidden")
        try repo.setNote("Triggers a reload", on: d("2026-11-13"), today: d("2026-11-13"))
        for _ in 0..<200 where model.failure == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.failure != nil)
        #expect(model.data.habits.map(\.id) == [id]) // last good data kept

        try repo.execute("ALTER TABLE hidden RENAME TO firstTimeNotesSeen")
        try repo.setDone(true, habit: id, on: d("2026-11-13"), today: d("2026-11-13"))
        for _ in 0..<600 where model.evaluation(of: id)?.status(on: d("2026-11-13")) != .done {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.evaluation(of: id)?.status(on: d("2026-11-13")) == .done)
        #expect(model.failure == nil)
    }

    // MARK: 3. "Today" moved backwards (day-end change at 1am, flying west)

    @MainActor
    @Test func aHabitStartingTomorrowStaysActiveWhenTodayMovesBack() throws {
        let repo = try makeRepository()
        var ids: [HabitID] = []
        for n in 1...4 { ids.append(try repo.addHabit(name: "H\(n)", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))) }
        ids.append(try repo.addHabit(name: "H5", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13")))
        let yesterday = d("2026-11-12")

        let model = AppModel(repository: repo, now: { DayClock().date(on: yesterday, hour: 9, minute: 0) })
        #expect(model.activeEvaluations.map(\.id) == ids)
        // Still editable, and still counted toward the limit.
        try repo.updateDetails(of: ids[4], name: "Five", identity: nil, today: yesterday)
        #expect(throws: Repository.Failure.atHabitLimit) {
            try repo.addHabit(name: "H6", kind: .yesNo, schedule: .everyDay, today: yesterday)
        }
        // Reactivating an active habit does nothing, not even a move to the end.
        try repo.reactivate(ids[4], today: yesterday)
        try repo.reactivate(ids[0], today: yesterday)
        #expect(try repo.appData().habits.map(\.id) == ids)
    }

    // MARK: 4. One envelope at a time, newest first

    func weeklies(_ repo: Repository, through day: String) throws -> [DueReport] {
        let clock = DayClock(timeZone: TimeZone(identifier: "UTC")!)
        return ReportSchedule(clock: clock).dueReports(lastCoveredWeekEnd: nil, lastMonthlyPeriodEnd: nil, firstUseDay: d("2026-10-04"),
                                                       now: clock.date(on: d(day), hour: 19, minute: 0))
    }

    @Test func aNewLetterFilesTheUnopenedOneAsUnread() throws {
        let repo = try makeRepository()
        try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-10-04"))
        let data = try repo.appData()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Caught up after the Mac was off: all delivered at the same moment.
        for due in try weeklies(repo, through: "2026-11-08") {
            let snapshot = due.kind == .monthly ? ReportSnapshot.monthly(due, data: data)
                : ReportSnapshot.weekly(due, data: data, previousObstacle: nil)
            try repo.deliver(snapshot, at: now)
        }
        let reports = try repo.reports()
        #expect(reports.map(\.deliveryDay) == [d("2026-11-08"), d("2026-11-01"), d("2026-10-25"), d("2026-10-18"), d("2026-10-11")])
        #expect(reports.map(\.isNew) == [true, false, false, false, false])
        #expect(reports.allSatisfy { $0.isUnread })
    }

    @Test func anOpenedLetterIsNotFiledAndAnOlderLetterArrivesFiled() throws {
        let repo = try makeRepository()
        try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-10-04"))
        let data = try repo.appData()
        let due = try weeklies(repo, through: "2026-10-25")
        let first = try repo.deliver(ReportSnapshot.weekly(due[0], data: data, previousObstacle: nil), at: Date())
        try repo.markReportOpened(first, at: Date())
        try repo.deliver(ReportSnapshot.weekly(due[1], data: data, previousObstacle: nil), at: Date())
        // Opened but not Done yet: it stays new (only unopened letters leave the envelope).
        #expect(try repo.reports().map(\.isNew) == [true, true])

        // An older letter delivered late goes straight to the archive.
        let repo2 = try makeRepository()
        try repo2.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-10-04"))
        let data2 = try repo2.appData()
        try repo2.deliver(ReportSnapshot.weekly(due[1], data: data2, previousObstacle: nil), at: Date())
        try repo2.deliver(ReportSnapshot.weekly(due[0], data: data2, previousObstacle: nil), at: Date())
        #expect(try repo2.reports().map(\.isNew) == [true, false])
    }

    // MARK: 5. Archived letters are read-only

    @Test func answersOnlyOnAnUnfiledLetterAndOnlyItsOwnQuestions() throws {
        let repo = try makeRepository()
        try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-10-04"))
        let data = try repo.appData()
        let due = try weeklies(repo, through: "2026-10-11")
        let id = try repo.deliver(ReportSnapshot.weekly(due[0], data: data, previousObstacle: nil), at: Date())
        #expect(throws: Repository.Failure.questionNotInReport) { try repo.setAnswer("A win", to: .biggestWin, report: id) }
        try repo.setAnswer("Travel", to: .obstacle, report: id)
        try repo.fileReport(id, at: Date())
        #expect(throws: Repository.Failure.reportFiled) { try repo.setAnswer("Changed", to: .obstacle, report: id) }
        #expect(try repo.reports().first?.answers == [.obstacle: "Travel"])
    }

    // MARK: 6. Buttons in old letters work only while still true

    @Test func acceptingASuggestionChecksItStillApplies() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: d("2026-10-01"))
        for day in d("2026-10-01")...d("2026-10-20") { try repo.setDone(true, habit: id, on: day, today: day) }
        let today = d("2026-10-20")
        let suggestion = try #require(Suggestions.suggestion(for: HabitEvaluation(history: try repo.history(id), today: today)))
        #expect(suggestion.change == .target(from: 10, to: 11))

        try repo.changeTarget(of: id, to: 15, today: d("2026-10-21"))
        #expect(throws: Repository.Failure.suggestionNoLongerApplies) { try repo.acceptSuggestion(suggestion, today: d("2026-10-22")) }
        #expect(try repo.history(id).target(on: d("2026-10-22")) == 15)

        try repo.changeTarget(of: id, to: 10, today: d("2026-10-23"))
        try repo.acceptSuggestion(suggestion, today: d("2026-10-24"))
        #expect(try repo.history(id).targetChanges.last == TargetChange(day: d("2026-10-24"), amount: 11, source: .suggested))
    }

    // MARK: 9. Undo kept a list position someone else now had

    @Test func undoPutsTheHabitBackInItsPlace() throws {
        let repo = try makeRepository()
        let today = d("2026-11-13")
        let a = try repo.addHabit(name: "A", kind: .yesNo, schedule: .everyDay, today: today)
        let b = try repo.addHabit(name: "B", kind: .yesNo, schedule: .everyDay, today: today)
        let deleted = try repo.deleteHabit(b)
        let c = try repo.addHabit(name: "C", kind: .yesNo, schedule: .everyDay, today: today)
        try repo.restore(deleted, today: today)
        let habits = try repo.appData().habits
        #expect(habits.map(\.id) == [a, b, c])
        #expect(Set(habits.map(\.sortOrder)).count == 3)
    }
}
