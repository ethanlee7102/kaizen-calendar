import Foundation
import Testing
@testable import Core

@Suite struct ReportScheduleTests {
    let clock = DayClock(timeZone: TimeZone(identifier: "America/New_York")!)
    var schedule: ReportSchedule { ReportSchedule(clock: clock) }

    func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        clock.date(on: d(day), hour: hour, minute: minute)
    }

    @Test func weeklyCoversTheLastFinishedSundayToSaturdayWeek() {
        // Delivered Sunday Nov 8 → Nov 1–7 (decided 2026-11-11).
        #expect(ReportSchedule.weekCovered(byDeliveryOn: d("2026-11-08")) == DayRange(d("2026-11-01"), d("2026-11-07")))
        // A Monday delivery day still covers the same finished week.
        #expect(ReportSchedule.weekCovered(byDeliveryOn: d("2026-11-09")) == DayRange(d("2026-11-01"), d("2026-11-07")))
        // A Saturday delivery day can't include its own unfinished week.
        #expect(ReportSchedule.weekCovered(byDeliveryOn: d("2026-11-14")) == DayRange(d("2026-11-01"), d("2026-11-07")))
    }

    @Test func notBeforeSixPm() {
        let due = schedule.dueReports(lastCoveredWeekEnd: nil, lastMonthlyPeriodEnd: nil,
                                      firstUseDay: d("2026-11-02"), now: at("2026-11-08", 17, 59))
        #expect(due.isEmpty)
        let now = schedule.dueReports(lastCoveredWeekEnd: nil, lastMonthlyPeriodEnd: nil,
                                      firstUseDay: d("2026-11-02"), now: at("2026-11-08", 18))
        #expect(now == [DueReport(kind: .weekly, deliveryDay: d("2026-11-08"),
                                  period: DayRange(d("2026-11-01"), d("2026-11-07")))])
    }

    @Test func skipsWeeksBeforeFirstUse() {
        // Started Sunday Nov 8: the Nov 8 report would cover Nov 1–7, before any habit.
        let due = schedule.dueReports(lastCoveredWeekEnd: nil, lastMonthlyPeriodEnd: nil,
                                      firstUseDay: d("2026-11-08"), now: at("2026-11-08", 20))
        #expect(due.isEmpty)
    }

    @Test func monthlyReplacesTheLastWeeklyOfTheMonth() {
        // Nov 29 is November's last Sunday. Previous monthly ended Oct 24 → covers Oct 25–Nov 28.
        let due = schedule.dueReports(lastCoveredWeekEnd: d("2026-11-21"), lastMonthlyPeriodEnd: d("2026-10-24"),
                                      firstUseDay: d("2026-09-01"), now: at("2026-11-29", 18))
        #expect(due == [DueReport(kind: .monthly, deliveryDay: d("2026-11-29"),
                                  period: DayRange(d("2026-10-25"), d("2026-11-28")))])
        #expect(due.first?.titleMonth == 11)
    }

    @Test func firstMonthlyStartsAtTheFirstWeekOfUse() {
        let due = schedule.dueReports(lastCoveredWeekEnd: d("2026-11-21"), lastMonthlyPeriodEnd: nil,
                                      firstUseDay: d("2026-11-04"), now: at("2026-11-29", 18))
        #expect(due.first?.period == DayRange(d("2026-11-01"), d("2026-11-28")))
    }

    @Test func catchesUpAfterTheMacWasOff() {
        // Off from Nov 7 to Dec 2: Nov 8, 15, 22 weekly and Nov 29 monthly, oldest first.
        let due = schedule.dueReports(lastCoveredWeekEnd: d("2026-10-31"), lastMonthlyPeriodEnd: d("2026-10-24"),
                                      firstUseDay: d("2026-09-01"), now: at("2026-12-02", 9))
        #expect(due.map(\.deliveryDay) == [d("2026-11-08"), d("2026-11-15"), d("2026-11-22"), d("2026-11-29")])
        #expect(due.map(\.kind) == [.weekly, .weekly, .weekly, .monthly])
    }

    @Test func customDeliveryDay() {
        let monday = ReportSchedule(settings: ReportSettings(weekday: .monday, hour: 9), clock: clock)
        let due = monday.dueReports(lastCoveredWeekEnd: nil, lastMonthlyPeriodEnd: nil,
                                    firstUseDay: d("2026-11-01"), now: at("2026-11-09", 9))
        #expect(due.map(\.period) == [DayRange(d("2026-11-01"), d("2026-11-07"))])
        // Nov 30 is November's last Monday.
        #expect(monday.isMonthlyDeliveryDay(d("2026-11-30")))
        #expect(!monday.isMonthlyDeliveryDay(d("2026-11-23")))
    }
}

@Suite struct ReportContentTests {
    @Test func weeklyReportSections() {
        let a = habit(from: "2026-11-01", "x.xxxxx")
        let b = habit(from: "2026-11-09") // starts after the period: not in the rows
        let evaluations = [a, b].map { HabitEvaluation(history: $0, today: d("2026-11-09")) }
        let notes = [DayNote(day: d("2026-11-03"), text: "Read before bed"), DayNote(day: d("2026-11-08"), text: "late"),
                     DayNote(day: d("2026-11-04"), text: "")]
        let report = WeeklyReport(period: DayRange(d("2026-11-01"), d("2026-11-07")), evaluations: evaluations,
                                  notes: notes, previousObstacle: "Late meetings")
        #expect(report.sections.rows.map(\.habitID) == [a.id])
        #expect(report.sections.rows[0].consistency.percent == 86)
        #expect(report.sections.saves.recoveredEveryTime)
        #expect(report.sections.notes.map(\.text) == ["Read before bed"])
        #expect(report.sections.journeys[a.id]?.count == 6)
        #expect(report.isFirstWeek)
        #expect(report.previousObstacle == "Late meetings")
    }

    @Test func monthlyReportReactivation() {
        var paused = habit(from: "2026-10-01", "xxxx")
        paused.deactivate(on: d("2026-10-05"), reason: .paused)
        let evaluations = [paused, habit(from: "2026-10-01")].map { HabitEvaluation(history: $0, today: d("2026-11-29")) }
        let report = MonthlyReport(period: DayRange(d("2026-10-25"), d("2026-11-28")), evaluations: evaluations, notes: [])
        #expect(report.inactiveHabits == [paused.id])
        #expect(report.canReactivate)
        #expect(report.trend?.count == 8)
    }

    @Test func day66Report() {
        var history = habit(from: "2026-01-01", String(repeating: "x", count: 30) + "." + String(repeating: "x", count: 40),
                            kind: .amount(unit: "pages"), target: 5)
        history.changeTarget(to: 6, on: d("2026-01-20"), source: .suggested)
        let e = HabitEvaluation(history: history, today: d("2026-03-12"))
        let notes = [DayNote(day: d("2026-01-02"), text: "first"), DayNote(day: d("2026-03-01"), text: "latest")]
        let report = Day66Report(evaluation: e, notes: notes)
        #expect(report?.doneDays.count == 66)
        #expect(report?.reachedOn == d("2026-03-08"))
        #expect(report?.calendarDays == 67)
        #expect(report?.saves == 1)
        #expect(report?.targetHistory.map(\.amount) == [5, 6])
        #expect(report?.firstNote?.text == "first" && report?.latestNote?.text == "latest")
        #expect(Day66Report(evaluation: HabitEvaluation(history: habit(from: "2026-01-01", "xx"), today: d("2026-01-02")),
                            notes: []) == nil)
    }

    @Test func automaticity() {
        #expect(Automaticity.recommendation(for: .mostly) == .graduate)
        #expect(Automaticity.recommendation(for: .completely) == .graduate)
        #expect(Automaticity.recommendation(for: .somewhat) == .keepGoing)
        #expect(Automaticity.nextCheckDay(after: d("2026-03-08")) == d("2026-03-29"))
        #expect(!Automaticity.isRecheckDue(lastCheck: d("2026-03-08"), today: d("2026-03-28")))
        #expect(Automaticity.isRecheckDue(lastCheck: d("2026-03-08"), today: d("2026-03-29")))
    }
}

@Suite struct ReminderTests {
    @Test func qualifiesOnlyInDanger() {
        #expect(NeverMissTwiceReminder.qualifies(HabitEvaluation(history: habit(from: "2026-11-01", "x."), today: d("2026-11-03"))))
        #expect(!NeverMissTwiceReminder.qualifies(HabitEvaluation(history: habit(from: "2026-11-01", "x.x"), today: d("2026-11-03"))))
        #expect(!NeverMissTwiceReminder.qualifies(HabitEvaluation(history: habit(from: "2026-11-01", "x.r"), today: d("2026-11-03"))))
        #expect(!NeverMissTwiceReminder.qualifies(HabitEvaluation(history: habit(from: "2026-11-01", "xx"), today: d("2026-11-03"))))
    }

    @Test func oneHabitWording() {
        let pages = NeverMissTwiceReminder.message(for: [.init(name: "Read", kind: .amount(unit: "pages"), streak: 12)])
        #expect(pages?.title == "Read: never miss twice.")
        #expect(pages?.body == "One small page keeps your 12-day streak going.")
        let yesNo = NeverMissTwiceReminder.message(for: [.init(name: "Floss", kind: .yesNo, streak: 5)])
        #expect(yesNo?.body == "Do it once today to keep your 5-day streak going.")
        let noStreak = NeverMissTwiceReminder.message(for: [.init(name: "Floss", kind: .yesNo, streak: 0)])
        #expect(noStreak?.body == "Do it once today to get your streak going.")
    }

    @Test func severalHabitsCombineIntoOne() {
        let items = ["Read", "Pushups", "Meditate"].map { NeverMissTwiceReminder.Item(name: $0, kind: .yesNo, streak: 3) }
        #expect(NeverMissTwiceReminder.message(for: Array(items.prefix(2)))?.body == "Read and Pushups are still open today.")
        #expect(NeverMissTwiceReminder.message(for: items)?.body == "Read, Pushups and Meditate are still open today.")
        #expect(NeverMissTwiceReminder.message(for: items)?.title == "Never miss twice:")
        #expect(NeverMissTwiceReminder.message(for: []) == nil)
    }

    @Test(arguments: [("pages", "page"), ("pushups", "pushup"), ("minutes", "minute"), ("glasses", "glass"),
                      ("stretches", "stretch"), ("stories", "story"), ("sets", "set")])
    func singularUnits(_ plural: String, _ singular: String) {
        #expect(NeverMissTwiceReminder.singular(plural) == singular)
    }

    @Test(arguments: ["km", "yoga", "push ups", "", "class"])
    func unknownUnitsFallBack(_ unit: String) {
        #expect(NeverMissTwiceReminder.singular(unit) == nil)
    }
}

@Suite struct ScienceRegistryTests {
    @Test func everyTopicHasTextAndASource() {
        for entry in ScienceRegistry.all {
            #expect(!entry.title.isEmpty)
            #expect(!entry.body.isEmpty)
            #expect(!entry.sources.isEmpty, "\(entry.topic) has no source, so it shouldn't have an info button")
        }
    }

    @Test func everyGroupHasEntries() {
        for group in ScienceGroup.allCases {
            #expect(!ScienceRegistry.entries(in: group).isEmpty)
        }
        #expect(Set(ScienceRegistry.allSources).count == ScienceRegistry.allSources.count)
    }

    @Test func userFacingTextSaysHabitNotGoal() {
        let texts = ScienceRegistry.all.flatMap { [$0.title, $0.body] } + FirstTimeNote.allCases.map(\.text)
        for text in texts {
            // "goal" is allowed only in the "A habit, not a goal" title.
            let lowered = text.lowercased().replacingOccurrences(of: "a habit, not a goal", with: "")
            #expect(!lowered.contains("goal"), "\(text)")
        }
    }

    @Test func restNoteHasNoInfoButton() {
        #expect(FirstTimeNote.restDay.topic == nil)
        #expect(FirstTimeNote.day66Seal.topic == .why66)
    }
}
