import Foundation
import Testing
@testable import Core

/// One test per bug found in the Phase 1 code review (2026-11-12), using the reviewer's
/// reproduction. Each failed before its fix.
@Suite struct RegressionTests {
    // 1. Graduating (or pausing) on a day already done kept that day out of streak and journey.
    @Test func deactivatingOnADoneDayKeepsThatDay() {
        var history = habit(from: "2026-01-01", String(repeating: "x", count: 66))
        let day66 = d("2026-01-01").adding(days: 65)
        history.deactivate(on: day66, reason: .graduated)
        let e = HabitEvaluation(history: history, today: day66)
        #expect(e.journey.count == 66)
        #expect(e.currentStreak == 66)
        #expect(e.status(on: day66) == .done)
        #expect(Day66Report(evaluation: e, notes: []) != nil)
        // Later days are inactive.
        #expect(HabitEvaluation(history: history, today: day66.adding(days: 5)).status(on: day66.adding(days: 1)) == .inactive)
    }

    @Test func deactivatingBeforeCheckingOffDoesNotCountAMiss() {
        var history = habit(from: "2026-11-01", "xxx")
        history.deactivate(on: d("2026-11-03"), reason: .paused)
        history.setDone(false, on: d("2026-11-03"))
        let e = HabitEvaluation(history: history, today: d("2026-11-05"))
        #expect(e.status(on: d("2026-11-03")) == .inactive)
        #expect(e.decidedDays.count == 2)
        #expect(e.breakDays.isEmpty)
    }

    // 2. Where DST starts at midnight, a day came out 0 hours long.
    @Test(arguments: [("America/Santiago", "2026-09-06"), ("America/Havana", "2026-03-08"), ("Asia/Beirut", "2026-03-29")])
    func midnightDSTGap(_ zone: String, _ day: String) {
        let clock = DayClock(timeZone: TimeZone(identifier: zone)!, dayEndHour: 0)
        let start = clock.start(of: d(day))
        #expect(clock.day(for: start) == d(day))
        #expect(clock.end(of: d(day)).timeIntervalSince(start) == 23 * 3600)
        #expect(clock.end(of: d(day).adding(days: -1)).timeIntervalSince(clock.start(of: d(day).adding(days: -1))) == 24 * 3600)
    }

    // 3. Changing the delivery weekday re-sent an already covered week.
    @Test func changingTheDeliveryDayDoesNotRepeatAWeek() {
        let clock = DayClock(timeZone: TimeZone(identifier: "America/New_York")!)
        // Sunday Nov 8's report covered Nov 1–7, then the day changed to Wednesday.
        let wednesday = ReportSchedule(settings: ReportSettings(weekday: .wednesday), clock: clock)
        let first = wednesday.dueReports(lastCoveredWeekEnd: d("2026-11-07"), lastMonthlyPeriodEnd: d("2026-10-24"),
                                         firstUseDay: d("2026-09-01"), now: clock.date(on: d("2026-11-11"), hour: 19, minute: 0))
        #expect(first.isEmpty)
        let next = wednesday.dueReports(lastCoveredWeekEnd: d("2026-11-07"), lastMonthlyPeriodEnd: d("2026-10-24"),
                                        firstUseDay: d("2026-09-01"), now: clock.date(on: d("2026-11-18"), hour: 19, minute: 0))
        #expect(next.map(\.period) == [DayRange(d("2026-11-08"), d("2026-11-14"))])
        // Monday the next day doesn't repeat it either.
        let monday = ReportSchedule(settings: ReportSettings(weekday: .monday), clock: clock)
        #expect(monday.dueReports(lastCoveredWeekEnd: d("2026-11-07"), lastMonthlyPeriodEnd: d("2026-10-24"),
                                  firstUseDay: d("2026-09-01"), now: clock.date(on: d("2026-11-09"), hour: 19, minute: 0)).isEmpty)
    }

    // 4. Breaks from before an accepted level-down triggered another level-down.
    @Test func breaksBeforeTheLastChangeDontRepeatALevelDown() {
        // Breaks Sep 22 and Sep 25, level-down accepted Sep 27, then 14 perfect days.
        var history = habit(from: "2026-09-01", String(repeating: "x", count: 20) + "..x..x" + String(repeating: "x", count: 15),
                            kind: .amount(unit: "pages"), target: 10)
        #expect(HabitEvaluation(history: history, today: d("2026-10-10")).breakDays == [d("2026-09-22"), d("2026-09-25")])
        history.changeTarget(to: 7, on: d("2026-09-27"), source: .suggested)
        let s = Suggestions.suggestion(for: HabitEvaluation(history: history, today: d("2026-10-10")))
        #expect(s?.kind != .levelDown)
        #expect(s?.change == .target(from: 7, to: 8)) // 14 perfect days since: a small level-up
    }

    // 5. Changing a target on an earlier day than the last change (west across the date line) crashed.
    @Test func backwardDayDoesNotCrash() {
        var history = habit(from: "2026-11-01", kind: .amount(unit: "pages"), target: 10)
        history.changeTarget(to: 12, on: d("2026-11-12"), source: .manual)
        history.changeTarget(to: 13, on: d("2026-11-11"), source: .manual)
        #expect(history.targetChanges.map(\.amount) == [10, 13])
        #expect(history.targetChanges.last?.day == d("2026-11-12"))
        history.changeSchedule(to: days(.monday), on: d("2026-11-12"), source: .manual)
        history.changeSchedule(to: days(.tuesday), on: d("2026-11-11"), source: .manual)
        #expect(history.scheduleChanges.last == ScheduleChange(day: d("2026-11-12"), schedule: days(.tuesday), source: .manual))
    }

    // 6. Corrupt stored data was accepted and misbehaved later.
    @Test func invalidStoredDataIsRejected() {
        let day = d("2026-11-01")
        let schedule = [ScheduleChange(day: day, schedule: .everyDay, source: .initial)]
        #expect(throws: HabitHistory.InvalidData.noActivePeriod) {
            try HabitHistory(kind: .yesNo, createdDay: day, scheduleChanges: schedule, activePeriods: [])
        }
        #expect(throws: HabitHistory.InvalidData.noSchedule) {
            try HabitHistory(kind: .yesNo, createdDay: day, scheduleChanges: [])
        }
        #expect(throws: HabitHistory.InvalidData.amountHabitWithoutTarget) {
            try HabitHistory(kind: .amount(unit: "pages"), createdDay: day, scheduleChanges: schedule)
        }
        #expect(throws: HabitHistory.InvalidData.firstPeriodNotOnCreatedDay) {
            try HabitHistory(kind: .yesNo, createdDay: day, scheduleChanges: schedule,
                             activePeriods: [ActivePeriod(start: d("2026-11-03"))])
        }
        #expect(throws: HabitHistory.InvalidData.periodsOverlapOrOpenInMiddle) {
            try HabitHistory(kind: .yesNo, createdDay: day, scheduleChanges: schedule,
                             activePeriods: [ActivePeriod(start: day), ActivePeriod(start: d("2026-11-05"))])
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Schedule.self, from: Data("0".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TargetChange.self, from: Data(#"{"day":"2026-11-01","amount":0,"source":"initial"}"#.utf8))
        }
    }

    // Rest after a miss: closed loophole (decided 2026-11-12).
    @Test func cannotRestOnADangerDay() {
        let e = evaluate(habit(from: "2026-11-01", "xx."), today: "2026-11-04")
        #expect(e.recovery == .danger)
        #expect(!EditRules.canRest(e, on: d("2026-11-04")))
    }

    // A miss from before a pause doesn't nag on reactivation day.
    @Test func noDangerLineAfterReactivating() {
        var history = habit(from: "2026-11-01", "xx.")
        history.deactivate(on: d("2026-11-04"), reason: .paused)
        history.reactivate(on: d("2027-02-01"))
        let e = HabitEvaluation(history: history, today: d("2027-02-01"))
        #expect(e.recovery == .none)
        #expect(!NeverMissTwiceReminder.qualifies(e))
        #expect(e.currentStreak == 2)
    }

    // Check-offs and rests stay consistent.
    @Test func doneClearsRestAndRestDoesNotOverrideDone() {
        var history = habit(from: "2026-11-01")
        history.setRested(true, on: d("2026-11-01"))
        history.setDone(true, on: d("2026-11-01"))
        history.setDone(false, on: d("2026-11-01"))
        #expect(history.rests.isEmpty && history.completions.isEmpty) // the rest doesn't come back
        history.setDone(true, on: d("2026-11-02"))
        history.setRested(true, on: d("2026-11-02"))
        #expect(history.rests.isEmpty)
    }

    // Boundaries the review found untested.
    @Test func welcomeBackBoundary() {
        // Streak breaks Nov 6 (misses Nov 5 and 6), so only the number of days away decides.
        let e = HabitEvaluation(history: habit(from: "2026-11-01", "xxxx...."), today: d("2026-11-09"))
        #expect(e.breakDays == [d("2026-11-06")])
        // Last opened Nov 5: Nov 6–8 not opened (3 days) → show.
        #expect(WelcomeBack.shouldShow(lastOpenedDay: d("2026-11-05"), evaluations: [e], today: d("2026-11-09")))
        // Last opened Nov 6: Nov 7–8 not opened (2 days) → don't.
        #expect(!WelcomeBack.shouldShow(lastOpenedDay: d("2026-11-06"), evaluations: [e], today: d("2026-11-09")))
        // A break on the last day opened counts as happening while away.
        #expect(WelcomeBack.shouldShow(lastOpenedDay: d("2026-11-06"), evaluations: [e], today: d("2026-11-10")))
    }

    @Test func levelUpOnThe14thDayOnceTodayIsDone() {
        let pattern = String(repeating: "x", count: 14)
        let history = habit(from: "2026-10-01", pattern, kind: .amount(unit: "pages"), target: 10)
        #expect(Suggestions.suggestion(for: HabitEvaluation(history: history, today: d("2026-10-14")))?.kind == .levelUp)
        #expect(Suggestions.suggestion(for: HabitEvaluation(history: history, today: d("2026-10-13"))) == nil)
    }

    @Test func snoozedLevelDownDoesNotTurnIntoLevelUp() {
        // Low consistency: level-down applies; snoozed, it must not offer a level-up instead.
        let pattern = "x.x.x.x.x.x.xx"
        let history = habit(from: "2026-10-01", pattern, kind: .amount(unit: "pages"), target: 10)
        let e = HabitEvaluation(history: history, today: d("2026-10-15"))
        #expect(Suggestions.suggestion(for: e, dismissals: [SuggestionDismissal(kind: .levelDown, day: d("2026-10-15"))]) == nil)
    }

    @Test func weakestWeekdayForgetsOldStretchesAndRemovedDays() {
        // Wednesdays missed in Sep, then perfect for 9 weeks: no longer reported.
        var history = habit(from: "2026-09-01")
        let end = d("2026-11-30")
        for day in d("2026-09-01")...end where !(day < d("2026-10-01") && day.weekday == .wednesday) {
            history.setDone(true, on: day)
        }
        #expect(Insights.weakestWeekday(HabitEvaluation(history: history, today: end), through: end) == nil)
        // Wednesdays always missed, then Wednesday removed from the schedule: not reported.
        var dropped = habit(from: "2026-09-01")
        for day in d("2026-09-01")...d("2026-10-31") where day.weekday != .wednesday {
            dropped.setDone(true, on: day)
        }
        dropped.changeSchedule(to: Schedule(days: WeekdaySet.all.subtracting(WeekdaySet(.wednesday)))!,
                               on: d("2026-10-31"), source: .manual)
        #expect(Insights.weakestWeekday(HabitEvaluation(history: dropped, today: d("2026-11-01")), through: d("2026-10-31")) == nil)
    }

    @Test(arguments: ["calories", "movies", "series", "es"])
    func irregularUnitsFallBackOrMapCorrectly(_ unit: String) {
        let expected = ["calories": "calorie", "movies": "movie"][unit]
        #expect(NeverMissTwiceReminder.singular(unit) == expected)
    }

    @Test func dayKeyRejectsSigns() {
        #expect(DayKey("2026-+1-05") == nil)
        #expect(DayKey("+026-11-05") == nil)
    }

    @Test func monthlyAcrossTheYearBoundary() {
        // Dec 27 2026 is December's last Sunday; previous monthly ended Nov 28.
        let clock = DayClock(timeZone: TimeZone(identifier: "America/New_York")!)
        let due = ReportSchedule(clock: clock).dueReports(
            lastCoveredWeekEnd: d("2026-12-19"), lastMonthlyPeriodEnd: d("2026-11-28"), firstUseDay: d("2026-09-01"),
            now: clock.date(on: d("2027-01-03"), hour: 19, minute: 0))
        #expect(due.map(\.kind) == [.monthly, .weekly])
        #expect(due.first?.period == DayRange(d("2026-11-29"), d("2026-12-26")))
        #expect(due.last?.period == DayRange(d("2026-12-27"), d("2027-01-02")))
    }
}
