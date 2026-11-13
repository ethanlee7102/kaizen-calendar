import Foundation
import Testing
@testable import Core

/// Core regressions found in the Phase 2 code review (2026-11-13).
@Suite struct Phase2ReviewTests {
    /// The day-66 letter is written as of its delivery day: target changes made after that day
    /// (e.g. when it's caught up later) aren't in its history.
    @Test func day66HistoryStopsAtTheDeliveryDay() throws {
        var read = habit(from: "2026-09-01", String(repeating: "x", count: 80), kind: .amount(unit: "pages"), target: 10)
        read.changeTarget(to: 12, on: d("2026-10-01"), source: .manual)
        read.changeTarget(to: 15, on: d("2026-11-15"), source: .manual)
        read.changeSchedule(to: days(.monday), on: d("2026-11-16"), source: .manual)
        let report = try #require(Day66Report(evaluation: evaluate(read, today: "2026-11-06"), notes: []))
        #expect(report.targetHistory.map(\.amount) == [10, 12])
        #expect(report.scheduleHistory.count == 1)
    }

    /// Known edge (Phase 2 review; kept as is, decided 2026-11-13): changing the report day from Sunday to
    /// Saturday in a month's last week means that month gets no monthly letter, because the last
    /// Saturday's week was already covered by Sunday's weekly. Nothing is lost: those weeks go
    /// into the next monthly letter. Pinned so a change here is deliberate.
    @Test func changingTheReportDayLateInAMonthMergesItsMonthlyIntoTheNext() {
        let clock = DayClock(timeZone: TimeZone(identifier: "America/New_York")!)
        let saturday = ReportSchedule(settings: ReportSettings(weekday: .saturday), clock: clock)
        // Weekly on Sun Nov 22 covered Nov 15–21; October's monthly ended Oct 24.
        let due = saturday.dueReports(lastCoveredWeekEnd: d("2026-11-21"), lastMonthlyPeriodEnd: d("2026-10-24"),
                                      firstUseDay: d("2026-09-01"), now: clock.date(on: d("2026-12-26"), hour: 19, minute: 0))
        #expect(due.map(\.deliveryDay) == [d("2026-12-05"), d("2026-12-12"), d("2026-12-19"), d("2026-12-26")])
        #expect(due.last == DueReport(kind: .monthly, deliveryDay: d("2026-12-26"), period: DayRange(d("2026-10-25"), d("2026-12-19"))))
    }
}
