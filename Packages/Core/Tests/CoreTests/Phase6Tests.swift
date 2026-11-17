import Foundation
import Testing
@testable import Core

/// Phase 6: the next report time, the re-check schedule and letter values.
@Suite struct Phase6Tests {
    let clock = DayClock(timeZone: TimeZone(identifier: "America/New_York")!)

    func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        clock.date(on: d(day), hour: hour, minute: minute)
    }

    @Test func theNextReportTime() {
        let schedule = ReportSchedule(clock: clock) // Sunday 6pm
        #expect(schedule.nextDeliveryTime(after: at("2026-11-12", 9)) == at("2026-11-15", 18)) // Thursday
        #expect(schedule.nextDeliveryTime(after: at("2026-11-15", 17, 59)) == at("2026-11-15", 18)) // that Sunday
        #expect(schedule.nextDeliveryTime(after: at("2026-11-15", 18)) == at("2026-11-22", 18)) // just delivered
        let wednesday = ReportSchedule(settings: ReportSettings(weekday: .wednesday, hour: 7, minute: 30), clock: clock)
        #expect(wednesday.nextDeliveryTime(after: at("2026-11-15", 18)) == at("2026-11-18", 7, 30))
    }

    @Test func theRecheckCountsFromTheLastLetterOrTheReactivation() {
        var history = habit(from: "2026-09-01")
        // No day-66 letter yet: no re-check.
        #expect(Automaticity.recheckDay(lastLetterDay: nil, history: history) == nil)
        #expect(Automaticity.recheckDay(lastLetterDay: d("2026-11-05"), history: history) == d("2026-11-26"))
        // Inactive: none. Reactivated later: 3 weeks from then.
        history.deactivate(on: d("2026-11-10"), reason: .graduated)
        #expect(Automaticity.recheckDay(lastLetterDay: d("2026-11-05"), history: history) == nil)
        history.reactivate(on: d("2026-12-01"))
        #expect(Automaticity.recheckDay(lastLetterDay: d("2026-11-05"), history: history) == d("2026-12-22"))
    }

    @Test func letterKindsAndQuestions() {
        #expect(ReportKind.weekly.questions == [.obstacle])
        #expect(ReportKind.monthly.questions == [.biggestWin, .nextFocus])
        #expect(ReportKind.day66.questions.isEmpty && ReportKind.recheck.questions.isEmpty)
        #expect(ReportKind.allCases.filter(\.asksAutomaticity) == [.day66, .recheck])
        #expect(LetterChoice.changeTarget(12).decision == .changeTarget)
    }

    @Test func aRecheckLetterRoundTripsAsJSON() throws {
        let content = ReportContent.recheck(RecheckReport(habitID: HabitID(), dayCount: 87, previousAnswer: .somewhat))
        let decoded = try JSONDecoder().decode(ReportContent.self, from: JSONEncoder().encode(content))
        #expect(decoded == content)
        #expect(decoded.kind == .recheck && decoded.period == nil && decoded.habitID != nil)
    }
}
