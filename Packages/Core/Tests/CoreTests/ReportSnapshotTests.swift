import Foundation
import Testing
@testable import Core

/// Reports are stored when they're delivered (Phase 2), so they're built as of their delivery
/// day and must survive a JSON round trip unchanged.
@Suite struct ReportAsOfDeliveryTests {
    /// Regression (Phase 2 build): evaluations used `history.isActiveNow`, the state right
    /// now, so a report caught up for a past week dropped a habit paused since then.
    @Test func habitPausedAfterTheDeliveryDayIsStillActiveInThatReport() {
        var read = habit(from: "2026-10-04", String(repeating: "x", count: 40))
        read.deactivate(on: d("2026-11-12"), reason: .paused)
        let asOfDelivery = evaluate(read, today: "2026-11-08")
        #expect(asOfDelivery.isActive)

        let report = WeeklyReport(period: DayRange(d("2026-11-01"), d("2026-11-07")),
                                  evaluations: [asOfDelivery], notes: [], previousObstacle: nil)
        #expect(report.sections.journeys[read.id] != nil)
        let monthly = MonthlyReport(period: DayRange(d("2026-10-04"), d("2026-11-07")),
                                    evaluations: [asOfDelivery], notes: [])
        #expect(monthly.inactiveHabits.isEmpty)
    }

    /// Regression (Phase 2 build): a habit created after the delivery day showed up with a
    /// Day-0 journey (it counted as active "now").
    @Test func habitCreatedAfterTheDeliveryDayIsNotInThatReport() {
        let older = habit(from: "2026-10-04", String(repeating: "x", count: 36))
        let newer = habit(from: "2026-11-10", "x")
        let evaluations = [evaluate(older, today: "2026-11-08"), evaluate(newer, today: "2026-11-08")]
        #expect(!evaluations[1].isActive)

        let report = WeeklyReport(period: DayRange(d("2026-11-01"), d("2026-11-07")),
                                  evaluations: evaluations, notes: [], previousObstacle: nil)
        #expect(Set(report.sections.journeys.keys) == [older.id])
        let monthly = MonthlyReport(period: DayRange(d("2026-10-04"), d("2026-11-07")),
                                    evaluations: evaluations, notes: [])
        #expect(monthly.inactiveHabits.isEmpty)
    }

    @Test func pausedOnTheDeliveryDayIsInactiveInThatReport() {
        var read = habit(from: "2026-10-04", String(repeating: "x", count: 30))
        read.deactivate(on: d("2026-11-08"), reason: .paused)
        let evaluation = evaluate(read, today: "2026-11-08")
        #expect(!evaluation.isActive)
        let monthly = MonthlyReport(period: DayRange(d("2026-10-04"), d("2026-11-07")),
                                    evaluations: [evaluation], notes: [])
        #expect(monthly.inactiveHabits == [read.id])
    }

    @Test func noSuggestionOrReminderForAHabitNotActiveThatDay() {
        // Paused Nov 20; as of Nov 25 there's nothing to suggest or remind.
        var habit = habit(from: "2026-10-01", String(repeating: "x", count: 50))
        habit.deactivate(on: d("2026-11-20"), reason: .paused)
        let evaluation = evaluate(habit, today: "2026-11-25")
        #expect(Suggestions.suggestion(for: evaluation) == nil)
        #expect(!NeverMissTwiceReminder.qualifies(evaluation))
        #expect(evaluation.nextScheduledDay == nil)
        // As of Nov 10 it was active and had earned a level-up... but it's yes/no every day,
        // so there's nothing to raise. An amount habit would get one.
        #expect(evaluate(habit, today: "2026-11-10").isActive)
    }
}

@Suite struct ReportCodingTests {
    func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try JSONDecoder().decode(T.self, from: encoder.encode(value))
    }

    /// A habit with misses, recoveries, rests, a target change and a note.
    func sampleEvaluations(today: String) -> [HabitEvaluation] {
        var pages = habit(from: "2026-09-06", "xx.xx.xxrxx..xxxxxxxxxxxxxxxx.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
                          kind: .amount(unit: "pages"), target: 10)
        pages.changeTarget(to: 12, on: d("2026-10-10"), source: .suggested)
        let meditate = habit(from: "2026-10-01", "x.x..xxxxxxxxxxxxxxxxxxxxxxxxxx.xxxxxxxxxx", schedule: days(.monday, .wednesday, .friday))
        return [evaluate(pages, today: today), evaluate(meditate, today: today)]
    }

    @Test func weeklyMonthlyAndDay66ReportsRoundTrip() throws {
        let evaluations = sampleEvaluations(today: "2026-11-17")
        let notes = [DayNote(day: d("2026-11-03"), text: "Read before bed"), DayNote(day: d("2026-09-07"), text: "First")]
        let weekly = WeeklyReport(period: DayRange(d("2026-11-08"), d("2026-11-14")), evaluations: evaluations,
                                  notes: notes, previousObstacle: "Late meetings")
        let monthly = MonthlyReport(period: DayRange(d("2026-09-06"), d("2026-11-14")), evaluations: evaluations,
                                    notes: notes, dismissals: [evaluations[0].id: [SuggestionDismissal(kind: .levelUp, day: d("2026-11-01"))]])
        let day66 = try #require(Day66Report(evaluation: evaluations[0], notes: notes))

        #expect(try roundTrip(weekly) == weekly)
        #expect(try roundTrip(monthly) == monthly)
        #expect(monthly.trend != nil)
        #expect(try roundTrip(day66) == day66)
    }

    @Test func habitIDIsAPlainUUIDStringAndAnObjectKey() throws {
        let id = HabitID(UUID(uuidString: "6F0F5C3E-2B7D-4C1A-9E2F-0D1A2B3C4D5E")!)
        let json = String(decoding: try JSONEncoder().encode([id: 1]), as: UTF8.self)
        #expect(json == #"{"6F0F5C3E-2B7D-4C1A-9E2F-0D1A2B3C4D5E":1}"#)
        #expect(String(decoding: try JSONEncoder().encode(id), as: UTF8.self) == #""6F0F5C3E-2B7D-4C1A-9E2F-0D1A2B3C4D5E""#)
        #expect(try roundTrip(id) == id)
    }

    @Test func dayRangeRejectsAnEndBeforeItsStart() {
        let json = Data(#"{"start":"2026-11-08","end":"2026-11-01"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DayRange.self, from: json) }
    }
}
