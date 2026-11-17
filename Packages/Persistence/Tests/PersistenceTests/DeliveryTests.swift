import Core
import Foundation
@testable import Persistence
import Testing

/// Letter delivery (Phase 6): `ReportDelivery` + `Repository.deliverDueReports`, the day-66 and
/// re-check letters, and their automaticity answer and decision.
@Suite struct DeliveryTests {
    let zone = TimeZone(identifier: "America/New_York")!

    func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        DayClock(timeZone: zone).date(on: d(day), hour: hour, minute: minute)
    }

    @discardableResult
    func deliver(_ repo: Repository, _ day: String, hour: Int = 19) throws -> Int {
        try repo.deliverDueReports(now: at(day, hour), today: d(day), timeZone: zone)
    }

    /// Read since Sun Oct 4, done every day through `through`.
    func reading(through last: String = "2026-11-12") throws -> (Repository, HabitID) {
        let repo = try makeRepository()
        let read = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: d("2026-10-04"))
        for day in d("2026-10-04")...d(last) { try repo.setDone(true, habit: read, on: day, today: day) }
        return (repo, read)
    }

    // MARK: Weekly and monthly

    @Test func lettersArriveAtTheReportTimeCaughtUpOldestFirst() throws {
        let (repo, _) = try reading()
        // Sunday Nov 8 before 6pm: Oct 11, Oct 18, Oct 25 (October's monthly) and Nov 1 are due.
        #expect(try deliver(repo, "2026-11-08", hour: 17) == 4)
        #expect(try deliver(repo, "2026-11-08", hour: 18) == 1) // Nov 8 at 6pm
        #expect(try deliver(repo, "2026-11-08", hour: 21) == 0) // never twice

        let reports = try repo.reports()
        #expect(reports.map(\.kind) == [.weekly, .weekly, .monthly, .weekly, .weekly])
        #expect(reports.map(\.period) == [
            DayRange(d("2026-11-01"), d("2026-11-07")), DayRange(d("2026-10-25"), d("2026-10-31")),
            DayRange(d("2026-10-04"), d("2026-10-24")), DayRange(d("2026-10-11"), d("2026-10-17")),
            DayRange(d("2026-10-04"), d("2026-10-10")),
        ])
        // One envelope: the newest; the others are filed unread.
        #expect(reports.filter(\.isNew).map(\.deliveryDay) == [d("2026-11-08")])
        #expect(reports.allSatisfy { $0.isUnread })
    }

    @Test func noHabitsNoLetters() throws {
        let repo = try makeRepository()
        #expect(try deliver(repo, "2026-11-08") == 0)
    }

    @Test func theLastObstacleAnswerComesBackEvenWeeksLater() throws {
        let (repo, _) = try reading(through: "2026-11-20")
        try deliver(repo, "2026-11-01")
        let nov1 = try #require(try repo.reports().first)
        try repo.setAnswer("Late meetings. Read at lunch.", to: .obstacle, report: nov1.id)

        try deliver(repo, "2026-11-08")
        try deliver(repo, "2026-11-15") // Nov 8's letter had no answer: Nov 1's still shows
        let letters = try repo.reports()
        func obstacle(_ day: String) throws -> String? {
            let letter = try #require(letters.first { $0.deliveryDay == d(day) })
            guard case .weekly(let report) = try letter.snapshot.get().content else { return nil }
            return report.previousObstacle
        }
        #expect(try obstacle("2026-11-08") == "Late meetings. Read at lunch.")
        #expect(try obstacle("2026-11-15") == "Late meetings. Read at lunch.")
    }

    // MARK: Day 66

    @Test func theDay66LetterArrivesWithThe66thDoneDay() throws {
        // Oct 4 + 64 days = Dec 7: 65 done days.
        let (repo, read) = try reading(through: "2026-12-07")
        try deliver(repo, "2026-12-08", hour: 9)
        #expect(try repo.reports().contains { $0.kind == .day66 } == false)

        try repo.setDone(true, habit: read, on: d("2026-12-08"), today: d("2026-12-08"))
        #expect(try deliver(repo, "2026-12-08", hour: 9) == 1)
        let letter = try #require(try repo.reports().first)
        #expect(letter.kind == .day66 && letter.habitID == read && letter.isNew)
        guard case .day66(let report) = try letter.snapshot.get().content else { Issue.record("not day 66"); return }
        #expect(report.reachedOn == d("2026-12-08"))

        // Undoing the check-off doesn't take the letter back, and it never comes twice.
        try repo.setDone(false, habit: read, on: d("2026-12-08"), today: d("2026-12-08"))
        try repo.setDone(true, habit: read, on: d("2026-12-08"), today: d("2026-12-08"))
        #expect(try deliver(repo, "2026-12-08", hour: 9) == 0)
    }

    @Test func pausedHabitsGetNoDay66Letter() throws {
        let (repo, read) = try reading(through: "2026-12-10")
        try repo.deactivate(read, today: d("2026-12-10"))
        try deliver(repo, "2026-12-10", hour: 9)
        #expect(try repo.reports().contains { $0.kind == .day66 } == false)
    }

    // MARK: Re-checks

    @Test func theRecheckComesAbout3WeeksAfterTheLastLetter() throws {
        let (repo, read) = try reading(through: "2027-01-10")
        try deliver(repo, "2026-12-08", hour: 9) // the day-66 letter (and older weeklies)
        let day66 = try #require(try repo.reports().first { $0.kind == .day66 })
        try repo.answerAutomaticity(.somewhat, report: day66.id, today: d("2026-12-08"))
        try repo.decide(.keepGoing, report: day66.id, today: d("2026-12-08"))

        try deliver(repo, "2026-12-28", hour: 9) // 20 days later: not yet
        #expect(try repo.reports().contains { $0.kind == .recheck } == false)
        try deliver(repo, "2026-12-29", hour: 9) // 21 days
        let recheck = try #require(try repo.reports().first { $0.kind == .recheck })
        #expect(recheck.habitID == read && recheck.deliveryDay == d("2026-12-29"))
        guard case .recheck(let report) = try recheck.snapshot.get().content else { Issue.record("not a re-check"); return }
        #expect(report.previousAnswer == .somewhat)
        #expect(report.dayCount == 87) // Oct 4 – Dec 29

        // The next one counts from this letter.
        try deliver(repo, "2027-01-18", hour: 9)
        #expect(try repo.reports().count { $0.kind == .recheck } == 1)
        try deliver(repo, "2027-01-19", hour: 9)
        #expect(try repo.reports().count { $0.kind == .recheck } == 2)
    }

    @Test func graduatingStopsRechecksAndReactivatingWaits3Weeks() throws {
        let (repo, read) = try reading(through: "2026-12-08")
        try deliver(repo, "2026-12-08", hour: 9)
        let day66 = try #require(try repo.reports().first { $0.kind == .day66 })
        try repo.decide(.graduate, report: day66.id, today: d("2026-12-08"))
        let history = try #require(try repo.appData().habit(read)?.history.get())
        #expect(history.inactiveReason == .graduated)

        try deliver(repo, "2027-01-20", hour: 9)
        #expect(try repo.reports().contains { $0.kind == .recheck } == false)

        try repo.reactivate(read, today: d("2027-02-01"))
        try deliver(repo, "2027-02-21", hour: 9)
        #expect(try repo.reports().contains { $0.kind == .recheck } == false)
        try deliver(repo, "2027-02-22", hour: 9)
        #expect(try repo.reports().contains { $0.kind == .recheck })
    }

    // MARK: Answer and decision

    @Test func theAutomaticityAnswerIsKeptWithTheLetterAndTheHabit() throws {
        let (repo, read) = try reading(through: "2026-12-08")
        try deliver(repo, "2026-12-08", hour: 9)
        let letter = try #require(try repo.reports().first { $0.kind == .day66 })
        try repo.answerAutomaticity(.mostly, report: letter.id, today: d("2026-12-08"))
        try repo.answerAutomaticity(.completely, report: letter.id, today: d("2026-12-08")) // can change

        #expect(try repo.reports().first { $0.id == letter.id }?.automaticity == .completely)
        #expect(try repo.appData().automaticityChecks[read]?.map(\.answer) == [.completely])

    }

    @Test func onlyDay66AndRecheckLettersAskIt() throws {
        let (repo, _) = try reading()
        try deliver(repo, "2026-11-08")
        let weekly = try #require(try repo.reports().first { $0.isNew })
        #expect(throws: Repository.Failure.questionNotInReport) {
            try repo.answerAutomaticity(.mostly, report: weekly.id, today: d("2026-11-08"))
        }
        #expect(throws: Repository.Failure.questionNotInReport) {
            try repo.decide(.keepGoing, report: weekly.id, today: d("2026-11-08"))
        }
        #expect(throws: Repository.Failure.questionNotInReport) {
            try repo.setAnswer("4", to: .automaticity, report: weekly.id)
        }
    }

    @Test func oneDecisionPerOpenLetter() throws {
        let (repo, read) = try reading(through: "2026-12-08")
        try deliver(repo, "2026-12-08", hour: 9)
        let letter = try #require(try repo.reports().first { $0.kind == .day66 })

        try repo.decide(.changeTarget(15), report: letter.id, today: d("2026-12-08"))
        let history = try #require(try repo.appData().habit(read)?.history.get())
        #expect(history.target(on: d("2026-12-08")) == 15)
        #expect(history.targetChanges.last?.source == .manual)
        #expect(try repo.reports().first { $0.id == letter.id }?.decision == .changeTarget)

        #expect(throws: Repository.Failure.alreadyDecided) {
            try repo.decide(.graduate, report: letter.id, today: d("2026-12-08"))
        }
        // The failed second decision changed nothing.
        #expect(try repo.appData().habit(read)?.history.get().isActiveNow == true)

        // After the decision the answer is settled too (Phase 6 review).
        #expect(throws: Repository.Failure.alreadyDecided) {
            try repo.answerAutomaticity(.mostly, report: letter.id, today: d("2026-12-08"))
        }
    }

    @Test func aDecisionNeedsAnActiveHabit() throws {
        let (repo, read) = try reading(through: "2026-12-08")
        try deliver(repo, "2026-12-08", hour: 9)
        let letter = try #require(try repo.reports().first { $0.kind == .day66 })
        try repo.deactivate(read, today: d("2026-12-09"))
        #expect(throws: Repository.Failure.habitInactive) {
            try repo.decide(.keepGoing, report: letter.id, today: d("2026-12-09"))
        }
        #expect(try repo.reports().first { $0.id == letter.id }?.decision == nil)
    }

    @Test func aYesNoHabitChangesItsScheduleFromTheLetter() throws {
        let repo = try makeRepository()
        let walk = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-10-04"))
        for day in d("2026-10-04")...d("2026-12-08") { try repo.setDone(true, habit: walk, on: day, today: day) }
        try deliver(repo, "2026-12-08", hour: 9)
        let letter = try #require(try repo.reports().first { $0.kind == .day66 })
        let weekdays = try #require(Schedule([.monday, .wednesday, .friday]))
        #expect(throws: Repository.Failure.notAnAmountHabit) {
            try repo.decide(.changeTarget(3), report: letter.id, today: d("2026-12-08"))
        }
        try repo.decide(.changeSchedule(weekdays), report: letter.id, today: d("2026-12-08"))
        #expect(try repo.appData().habit(walk)?.history.get().schedule(on: d("2026-12-08")) == weekdays)
    }

    // MARK: Phase 6 review

    /// A weekly letter that replaces an unopened day-66 letter in the envelope must not lose the
    /// day-66 decision (user's choice: it stays decidable while filed).
    @Test func aDay66LetterReplacedInTheEnvelopeCanStillBeDecided() throws {
        let (repo, read) = try reading(through: "2026-12-14")
        try deliver(repo, "2026-12-08", hour: 9) // day 66
        try deliver(repo, "2026-12-13") // Sunday's weekly arrives; the day-66 letter is filed unread
        let letter = try #require(try repo.reports().first { $0.kind == .day66 })
        #expect(!letter.isNew && letter.isUnread)
        #expect(try repo.reports().first?.kind == .weekly)

        try repo.answerAutomaticity(.mostly, report: letter.id, today: d("2026-12-14"))
        try repo.decide(.graduate, report: letter.id, today: d("2026-12-14"))
        #expect(try repo.appData().habit(read)?.history.get().inactiveReason == .graduated)
        // Written answers on filed letters stay read-only.
        let weekly = try #require(try repo.reports().first { $0.kind == .weekly && !$0.isNew })
        #expect(throws: Repository.Failure.reportFiled) { try repo.setAnswer("x", to: .obstacle, report: weekly.id) }
    }

    @Test func twoHabitsReachingDay66TogetherCanBothBeDecided() throws {
        let (repo, read) = try reading(through: "2026-12-08")
        let walk = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-10-04"))
        for day in d("2026-10-04")...d("2026-12-08") { try repo.setDone(true, habit: walk, on: day, today: day) }
        try deliver(repo, "2026-12-08", hour: 9)
        let letters = try repo.reports().filter { $0.kind == .day66 }
        #expect(Set(letters.compactMap(\.habitID)) == [read, walk])
        for letter in letters { try repo.decide(.keepGoing, report: letter.id, today: d("2026-12-08")) }
        #expect(try repo.reports().filter { $0.kind == .day66 }.allSatisfy { $0.decision == .keepGoing })
    }

    /// No weekly letter for a week with no active habit (user's choice); letters resume after a
    /// reactivation, and the next monthly letter still arrives.
    @Test func noLetterForWeeksWithNoActiveHabit() throws {
        let (repo, read) = try reading(through: "2026-11-07")
        try deliver(repo, "2026-11-08")
        try repo.deactivate(read, today: d("2026-11-09")) // Monday: Nov 8–14 still has Nov 8
        try deliver(repo, "2026-12-06")
        let weeks = try repo.reports().compactMap(\.period?.start)
        #expect(weeks.contains(d("2026-11-08")))  // active on Nov 8
        #expect(!weeks.contains(d("2026-11-15")) && !weeks.contains(d("2026-11-22")))

        try repo.reactivate(read, today: d("2026-12-07"))
        try repo.setDone(true, habit: read, on: d("2026-12-07"), today: d("2026-12-07"))
        #expect(try deliver(repo, "2026-12-13") == 1)
        #expect(try repo.reports().first?.period == DayRange(d("2026-12-06"), d("2026-12-12")))
    }

    /// With the day ending at 3am and letters at Monday 12:30am, a day-66 letter checked off for
    /// Sunday at 1am is dated Monday, so it isn't older than that weekly and goes in the envelope.
    @Test func aDay66LetterAfterMidnightStillGoesInTheEnvelope() throws {
        let repo = try makeRepository()
        try repo.updateSettings {
            $0.dayEndHour = 3
            $0.report = ReportSettings(weekday: .monday, hour: 0, minute: 30)
        }
        let read = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: d("2026-10-02"))
        for day in d("2026-10-02")...d("2026-12-05") { try repo.setDone(true, habit: read, on: day, today: day) } // 65 days
        let monday1am = at("2026-12-07", 1)
        try repo.deliverDueReports(now: monday1am, today: d("2026-12-06"), timeZone: zone)
        #expect(try repo.reports().first?.deliveryDay == d("2026-12-07")) // Monday's weekly

        try repo.setDone(true, habit: read, on: d("2026-12-06"), today: d("2026-12-06")) // still Sunday
        try repo.deliverDueReports(now: monday1am.addingTimeInterval(600), today: d("2026-12-06"), timeZone: zone)
        let letter = try #require(try repo.reports().first { $0.kind == .day66 })
        #expect(letter.isNew && letter.deliveryDay == d("2026-12-07"))
    }

    @Test func aReversedStoredPeriodIsReportedNotCrashed() throws {
        let (repo, _) = try reading()
        try deliver(repo, "2026-11-08")
        try repo.execute(#"UPDATE reports SET periodStart = '2026-12-31'"#)
        let (reports, problems) = try repo.database.read { try StoredReport.fetchAll($0) }
        #expect(reports.isEmpty && !problems.isEmpty)
        #expect(try deliver(repo, "2026-11-08") >= 0) // delivery skips the bad rows too
    }

    // MARK: Stored form

    /// Letters are stored as JSON and must stay readable after the types moved to Core
    /// (Phase 6). This is a weekly letter written by Phase 2's code.
    @Test func aPhase2LetterStillDecodes() throws {
        let json = #"""
        {"content":{"weekly":{"_0":{"isFirstWeek":true,"previousObstacle":null,"sections":{"journeys":{},"notes":[],"period":{"end":"2026-11-07","start":"2026-11-01"},"rows":[],"saves":{"misses":0,"recovered":0},"suggestions":[],"weakestWeekdays":[]}}}},"deliveryDay":"2026-11-08","habits":{},"version":1}
        """#
        let snapshot = try ReportSnapshot.decode(json).get()
        #expect(snapshot.kind == .weekly && snapshot.period == DayRange(d("2026-11-01"), d("2026-11-07")))
    }
}
