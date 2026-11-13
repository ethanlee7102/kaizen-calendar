import Core
import Foundation
@testable import Persistence
import SQLiteData
import Testing

@Suite struct ReportStorageTests {
    let deliveredAt = Date(timeIntervalSince1970: 1_794_150_000)

    /// Read since Oct 4 (done every day but Nov 3), Walk since Nov 10 (after the Nov 8 delivery).
    func seeded() throws -> (Repository, read: HabitID, walk: HabitID) {
        let repo = try makeRepository()
        let read = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: d("2026-10-04"))
        for day in d("2026-10-04")...d("2026-11-12") where day != d("2026-11-03") {
            try repo.setDone(true, habit: read, on: day, today: day)
        }
        let walk = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-11-10"))
        try repo.setNote("Read before bed", on: d("2026-11-05"), today: d("2026-11-05"))
        return (repo, read, walk)
    }

    /// Due reports come from Core's schedule, as in the app.
    func due(lastCoveredWeekEnd: String?, lastMonthlyEnd: String? = nil, at day: String) -> [DueReport] {
        let clock = DayClock(timeZone: TimeZone(identifier: "America/New_York")!)
        return ReportSchedule(clock: clock).dueReports(
            lastCoveredWeekEnd: lastCoveredWeekEnd.map(d), lastMonthlyPeriodEnd: lastMonthlyEnd.map(d),
            firstUseDay: d("2026-10-04"), now: clock.date(on: d(day), hour: 19, minute: 0))
    }

    var nov8: DueReport { due(lastCoveredWeekEnd: "2026-10-31", at: "2026-11-08").last! }

    @Test func aLetterIsWrittenAsOfItsDeliveryDay() throws {
        let (repo, read, walk) = try seeded()
        let snapshot = ReportSnapshot.weekly(nov8, data: try repo.appData(), previousObstacle: "Late meetings")
        guard case .weekly(let report) = snapshot.content else { Issue.record("not weekly"); return }
        // Walk didn't exist on Nov 8.
        #expect(Set(snapshot.habits.keys) == [read])
        #expect(snapshot.habits[walk] == nil)
        #expect(report.sections.journeys[read]?.count == 35) // Oct 4 – Nov 8 (36 days), minus Nov 3
        #expect(nov8.period == DayRange(d("2026-11-01"), d("2026-11-07")))
        #expect(report.sections.saves.misses == 1 && report.sections.saves.recovered == 1)
        #expect(report.sections.notes == [DayNote(day: d("2026-11-05"), text: "Read before bed")])
        #expect(report.previousObstacle == "Late meetings")
    }

    @Test func storedLettersNeverChange() throws {
        let (repo, read, _) = try seeded()
        let snapshot = ReportSnapshot.weekly(nov8, data: try repo.appData(), previousObstacle: nil)
        let id = try repo.deliver(snapshot, at: deliveredAt)

        // Later edits: backfill the missed day, rename, change the target, add a note.
        try repo.setDone(true, habit: read, on: d("2026-11-03"), today: d("2026-11-13"), changeAnyway: true)
        try repo.updateDetails(of: read, name: "Read books", identity: nil, today: d("2026-11-13"))
        try repo.changeTarget(of: read, to: 20, today: d("2026-11-13"))
        try repo.setNote("Later", on: d("2026-11-04"), today: d("2026-11-13"), changeAnyway: true)
        // Delivering the same week again doesn't rewrite it.
        let rewritten = ReportSnapshot.weekly(nov8, data: try repo.appData(), previousObstacle: "changed")
        #expect(try repo.deliver(rewritten, at: deliveredAt.addingTimeInterval(3600)) == id)

        let stored = try #require(try repo.reports().first)
        #expect(try repo.reports().count == 1)
        #expect(try stored.snapshot.get() == snapshot)
        #expect(try stored.snapshot.get().habits[read]?.name == "Read")
        #expect(stored.deliveredAt == deliveredAt)
        #expect(stored.isUnread && stored.isNew)
    }

    @Test func monthlyAndDay66Letters() throws {
        let (repo, read, _) = try seeded()
        let data = try repo.appData()
        // Oct 25 is October's last Sunday: the first monthly letter.
        let october = try #require(due(lastCoveredWeekEnd: "2026-10-17", at: "2026-10-25").last)
        #expect(october.kind == .monthly)
        let monthly = ReportSnapshot.monthly(october, data: data)
        #expect(monthly.kind == .monthly && monthly.period == DayRange(d("2026-10-04"), d("2026-10-24")))
        #expect(ReportSnapshot.day66(habit: read, deliveryDay: d("2026-11-12"), data: data) == nil) // 39 done days

        for day in d("2026-11-13")...d("2026-12-10") { try repo.setDone(true, habit: read, on: day, today: day) }
        let day66 = try #require(ReportSnapshot.day66(habit: read, deliveryDay: d("2026-12-10"), data: try repo.appData()))
        guard case .day66(let report) = day66.content else { Issue.record("not day 66"); return }
        #expect(report.reachedOn == d("2026-12-09"))
        #expect(day66.habits.keys.map { $0 } == [read])

        try repo.deliver(monthly, at: deliveredAt)
        try repo.deliver(day66, at: deliveredAt.addingTimeInterval(60))
        #expect(try repo.reports().map(\.kind) == [.day66, .monthly]) // newest first
    }

    /// Deleting a habit keeps its letters as written (decided 2026-11-13); Undo re-links them.
    @Test func deletingAHabitKeepsItsLetters() throws {
        let (repo, read, _) = try seeded()
        for day in d("2026-11-13")...d("2026-12-10") { try repo.setDone(true, habit: read, on: day, today: day) }
        let day66 = try #require(ReportSnapshot.day66(habit: read, deliveryDay: d("2026-12-10"), data: try repo.appData()))
        let id = try repo.deliver(day66, at: deliveredAt)

        let deleted = try repo.deleteHabit(read)
        let stored = try #require(try repo.reports().first)
        #expect(try stored.snapshot.get() == day66)
        #expect(try repo.database.read { try ReportRecord.find(StableID.key(id)).fetchOne($0)?.habitID } == String?.none)

        try repo.restore(deleted, today: d("2026-12-10"))
        #expect(try repo.database.read { try ReportRecord.find(StableID.key(id)).fetchOne($0)?.habitID } == read.key)
    }

    @Test func openedFiledAndAnswers() throws {
        let (repo, _, _) = try seeded()
        let id = try repo.deliver(ReportSnapshot.weekly(nov8, data: try repo.appData(), previousObstacle: nil), at: deliveredAt)
        let opened = deliveredAt.addingTimeInterval(60)
        try repo.markReportOpened(id, at: opened)
        try repo.markReportOpened(id, at: opened.addingTimeInterval(60)) // only the first time counts
        try repo.setAnswer("Travel. I'll read on the plane.", to: .obstacle, report: id)
        try repo.setAnswer("Travel. Read on the plane.", to: .obstacle, report: id) // saves as you type
        try repo.setAnswer("Draft", to: .obstacle, report: id)
        try repo.setAnswer(" ", to: .obstacle, report: id) // blank removes it
        #expect(try repo.reports().first?.answers.isEmpty == true)
        try repo.setAnswer("Travel. Read on the plane.", to: .obstacle, report: id)
        try repo.fileReport(id, at: opened)

        let stored = try #require(try repo.reports().first)
        #expect(stored.openedAt == opened && stored.filedAt == opened)
        #expect(!stored.isUnread && !stored.isNew)
        #expect(stored.answers == [.obstacle: "Travel. Read on the plane."])
        #expect(throws: Repository.Failure.reportNotFound) { try repo.setAnswer("x", to: .obstacle, report: UUID()) }
    }

    @Test func dismissalsAfterTheDeliveryDayDontCount() throws {
        let (repo, read, _) = try seeded()
        try repo.dismissSuggestion(.levelUp, habit: read, today: d("2026-11-12"))
        let snapshot = ReportSnapshot.weekly(nov8, data: try repo.appData(), previousObstacle: nil)
        guard case .weekly(let report) = snapshot.content else { Issue.record("not weekly"); return }
        // As of Nov 8, Read (36 days at 97%) earned a level-up; the Nov 12 "Not now" came later.
        #expect(report.sections.suggestions.map(\.kind) == [.levelUp])
    }

    @Test func unreadableSnapshotsAreReportedNotCrashed() throws {
        let (repo, _, _) = try seeded()
        let id = try repo.deliver(ReportSnapshot.weekly(nov8, data: try repo.appData(), previousObstacle: nil), at: deliveredAt)
        // A letter from a newer app version (e.g. synced from another Mac) isn't misread.
        try repo.execute(#"UPDATE reports SET snapshot = replace(snapshot, '"version":1', '"version":99')"#)
        var stored = try #require(try repo.reports().first { $0.id == id })
        #expect(stored.snapshot == .failure(.badSnapshot("written by a newer version (99)")))
        // Garbage is reported, and the letter's other details still load.
        try repo.execute("UPDATE reports SET snapshot = 'not json'")
        stored = try #require(try repo.reports().first { $0.id == id })
        guard case .failure(.badSnapshot) = stored.snapshot else { Issue.record("expected badSnapshot"); return }
        #expect(stored.deliveryDay == d("2026-11-08"))
    }
}
