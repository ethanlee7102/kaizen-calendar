import Testing
@testable import Core

@Suite struct WeakestWeekdayTests {
    /// Daily habit from Sun Nov 1 for `weeks` weeks; misses every `missWeekday` (always) plus
    /// `extraMisses` other days.
    func evaluation(weeks: Int, missing missWeekday: Weekday?, extraMisses: [String] = []) -> HabitEvaluation {
        var history = habit(from: "2026-11-01")
        let end = d("2026-11-01").adding(days: weeks * 7 - 1)
        history.completions = Set((d("2026-11-01")...end).filter {
            $0.weekday != missWeekday && !extraMisses.contains($0.description)
        })
        return HabitEvaluation(history: history, today: end.adding(days: 1))
    }

    @Test func findsTheWeekdayMissedFarMoreThanUsual() {
        let e = evaluation(weeks: 4, missing: .wednesday)
        #expect(Insights.weakestWeekday(e, through: d("2026-11-28")) == .wednesday)
    }

    @Test func needsFourWeeksOfData() {
        let e = evaluation(weeks: 3, missing: .wednesday)
        #expect(Insights.weakestWeekday(e, through: d("2026-11-21")) == nil)
    }

    @Test func needsAtLeastThreeMisses() {
        // Wednesdays missed only twice in 4 weeks.
        let e = evaluation(weeks: 4, missing: nil, extraMisses: ["2026-11-04", "2026-11-11"])
        #expect(Insights.weakestWeekday(e, through: d("2026-11-28")) == nil)
    }

    @Test func notWhenMissesAreSpreadEvenly() {
        // Every day missed once a week on a rotating day: no weekday stands out.
        let e = evaluation(weeks: 4, missing: nil,
                           extraMisses: ["2026-11-01", "2026-11-09", "2026-11-17", "2026-11-25"])
        #expect(Insights.weakestWeekday(e, through: d("2026-11-28")) == nil)
    }
}

@Suite struct OtherInsightTests {
    @Test func savesInPeriod() {
        let e = HabitEvaluation(history: habit(from: "2026-11-01", "x.xx..x"), today: d("2026-11-08"))
        let saves = Insights.saves([e], in: DayRange(d("2026-11-01"), d("2026-11-07")))
        #expect(saves.misses == 3 && saves.recovered == 1)
        #expect(!saves.recoveredEveryTime && !saves.noMisses)
        #expect(Insights.saves([e], in: DayRange(d("2026-11-01"), d("2026-11-03"))).recoveredEveryTime)
    }

    @Test func monthSummaryNeedsSevenScheduledDays() {
        let six = HabitEvaluation(history: habit(from: "2026-11-01", "xxxxxx"), today: d("2026-11-07"))
        #expect(Insights.monthSummary([six], month: d("2026-11-01"), today: d("2026-11-07")) == nil)
        let eight = HabitEvaluation(history: habit(from: "2026-11-01", "xx.xxxxx"), today: d("2026-11-08"))
        let summary = Insights.monthSummary([eight], month: d("2026-11-01"), today: d("2026-11-08"))
        #expect(summary?.consistency.percent == 88)
        #expect(summary?.missesRecovered == 1)
    }

    @Test func trendNeedsTwoFullWeeks() {
        // Started Wed Nov 4: first full week is Nov 8–14.
        let history = habit(from: "2026-11-04", String(repeating: "x", count: 30))
        let early = HabitEvaluation(history: history, today: d("2026-11-20"))
        #expect(Insights.weeklyTrend([early], through: d("2026-11-20")) == nil)
        let later = HabitEvaluation(history: history, today: d("2026-11-22"))
        let trend = Insights.weeklyTrend([later], through: d("2026-11-22"))
        #expect(trend?.map(\.week.start) == [d("2026-11-08"), d("2026-11-15")])
        #expect(trend?.allSatisfy { $0.consistency.percent == 100 } == true)
    }

    @Test func trendMarksRecoveredAndBreakingMisses() {
        let history = habit(from: "2026-11-01", "x.xxx..xxxxxxx")
        let e = HabitEvaluation(history: history, today: d("2026-11-15"))
        let trend = Insights.weeklyTrend([e], through: d("2026-11-14"))
        #expect(trend?.first?.recoveredMisses == [d("2026-11-02")])
        #expect(trend?.first?.unrecoveredMisses == [d("2026-11-06"), d("2026-11-07")])
    }

    @Test func welcomeBackAfterAwayAndABreak() {
        let e = HabitEvaluation(history: habit(from: "2026-11-01", "xxx....."), today: d("2026-11-08"))
        #expect(WelcomeBack.shouldShow(lastOpenedDay: d("2026-11-03"), evaluations: [e], today: d("2026-11-08")))
        #expect(!WelcomeBack.shouldShow(lastOpenedDay: d("2026-11-07"), evaluations: [e], today: d("2026-11-08")))
        let fine = HabitEvaluation(history: habit(from: "2026-11-01", "xxxxxxx"), today: d("2026-11-08"))
        #expect(!WelcomeBack.shouldShow(lastOpenedDay: d("2026-11-03"), evaluations: [fine], today: d("2026-11-08")))
    }
}
