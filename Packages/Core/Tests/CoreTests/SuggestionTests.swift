import Testing
@testable import Core

@Suite struct SuggestionTests {
    func amountHabit(_ pattern: String, target: Int = 10) -> HabitHistory {
        habit(from: "2026-10-01", pattern, kind: .amount(unit: "pages"), target: target)
    }

    /// Today is the day after the pattern ends.
    func suggest(_ history: HabitHistory, _ pattern: String,
                 dismissals: [SuggestionDismissal] = []) -> Suggestion? {
        let today = history.createdDay.adding(days: pattern.count)
        return Suggestions.suggestion(for: HabitEvaluation(history: history, today: today),
                                      dismissals: dismissals)
    }

    @Test(arguments: [(10, 11), (12, 13), (5, 6), (1, 2), (20, 22), (100, 110)])
    func levelUpSize(_ from: Int, _ to: Int) {
        #expect(Suggestions.raisedTarget(from) == to)
    }

    @Test(arguments: [(10, 7), (12, 9), (4, 3), (3, 2), (2, 1), (5, 4), (100, 75)])
    func levelDownSize(_ from: Int, _ to: Int) {
        #expect(Suggestions.loweredTarget(from) == to)
    }

    @Test func neverBelowOne() {
        #expect(Suggestions.loweredTarget(1) == nil)
    }

    @Test func levelUpAfter14SteadyDays() {
        let pattern = String(repeating: "x", count: 14)
        let s = suggest(amountHabit(pattern), pattern)
        #expect(s?.kind == .levelUp)
        #expect(s?.change == .target(from: 10, to: 11))
    }

    @Test func notBefore14ScheduledDays() {
        let pattern = String(repeating: "x", count: 13)
        #expect(suggest(amountHabit(pattern), pattern) == nil)
    }

    @Test func aRecoveredMissIsFineForLevelUp() {
        // 13 of 14 done (93%), the miss recovered.
        let pattern = "xxxxxx.xxxxxxx"
        #expect(suggest(amountHabit(pattern), pattern)?.kind == .levelUp)
    }

    @Test func restDaysDontCountAsScheduled() {
        // 14 done plus 2 rests: still 14 scheduled days, 100%.
        let pattern = "xxxxxxxrxxxxxxrx"
        #expect(suggest(amountHabit(pattern), pattern)?.kind == .levelUp)
    }

    @Test func levelDownBelow60Percent() {
        // 8 of 14 (57%), misses recovered so no breaks.
        let pattern = "x.x.x.x.x.x.xx"
        let s = suggest(amountHabit(pattern), pattern)
        #expect(s?.kind == .levelDown)
        #expect(s?.change == .target(from: 10, to: 7))
    }

    @Test func levelDownAfterTwoBreaksInThreeWeeks() {
        // 10 of 14 (71%) but two streak breaks in the last 21 days.
        let pattern = "xxxxxx..xxx..xx"
        #expect(suggest(amountHabit(pattern), pattern)?.kind == .levelDown)
    }

    @Test func middleGroundSuggestsNothing() {
        // 12 of 14 (86%): not enough for level-up, not low enough for level-down.
        let pattern = "xxxx.xxxxx.xxx"
        #expect(suggest(amountHabit(pattern), pattern) == nil)
    }

    @Test func cooldownAfterATargetChange() {
        var history = amountHabit(String(repeating: "x", count: 30))
        history.changeTarget(to: 11, on: d("2026-10-25"), source: .suggested)
        let today = d("2026-10-31")
        // Only 6 scheduled days since the change.
        #expect(Suggestions.suggestion(for: HabitEvaluation(history: history, today: today)) == nil)
        // 14 scheduled days after the change (Oct 25 – Nov 7), it can suggest again.
        history.completions.formUnion(d("2026-10-31")...d("2026-11-07"))
        let later = Suggestions.suggestion(for: HabitEvaluation(history: history, today: d("2026-11-08")))
        #expect(later?.change == .target(from: 11, to: 12))
    }

    @Test func notNowSnoozesFor14ScheduledDays() {
        let pattern = String(repeating: "x", count: 20)
        let history = amountHabit(pattern + String(repeating: "x", count: 14))
        let dismissal = SuggestionDismissal(kind: .levelUp, day: d("2026-10-20"))
        #expect(suggest(history, pattern, dismissals: [dismissal]) == nil)
        // 14 more scheduled days later it comes back.
        let later = Suggestions.suggestion(
            for: HabitEvaluation(history: history, today: d("2026-11-04")), dismissals: [dismissal])
        #expect(later?.kind == .levelUp)
    }

    @Test func dismissingLevelUpDoesntHideLevelDown() {
        let pattern = "x.x.x.x.x.x.xx"
        let dismissal = SuggestionDismissal(kind: .levelUp, day: d("2026-10-13"))
        #expect(suggest(amountHabit(pattern), pattern, dismissals: [dismissal])?.kind == .levelDown)
    }

    @Test func inactiveHabitsGetNoSuggestions() {
        let pattern = String(repeating: "x", count: 14)
        var history = amountHabit(pattern)
        history.deactivate(on: d("2026-10-15"), reason: .paused)
        #expect(suggest(history, pattern) == nil)
    }

    @Test func amountAtOneHasNoLevelDown() {
        let pattern = "x.x.x.x.x.x.xx"
        #expect(suggest(amountHabit(pattern, target: 1), pattern) == nil)
    }

    // MARK: Yes/no habits

    @Test func yesNoSpecificDaysAddsTheMostSpreadOutDay() {
        // Mon/Wed/Fri, all done for 14 scheduled days (from Thu Oct 1 through Nov 2).
        var history = habit(from: "2026-10-01", schedule: days(.monday, .wednesday, .friday))
        history.completions = Set((d("2026-10-01")...d("2026-11-02")).filter { history.isScheduled(on: $0) })
        let s = Suggestions.suggestion(for: HabitEvaluation(history: history, today: d("2026-11-03")))
        // Sunday is 1 away from Mon and 2 from Fri; Tue/Thu/Sat are 1 away. Sunday spreads it best.
        #expect(s?.change == .schedule(from: days(.monday, .wednesday, .friday),
                                       to: days(.sunday, .monday, .wednesday, .friday)))
    }

    @Test func yesNoEveryDayHasNoLevelUp() {
        let pattern = String(repeating: "x", count: 14)
        #expect(suggest(habit(from: "2026-10-01", pattern), pattern) == nil)
    }

    @Test func yesNoEveryDayLevelDownDropsToFiveDays() {
        // Tuesday + Wednesday missed each week: two streak breaks (Oct 1 2026 is a Thursday).
        let pattern = "xxxxx..xxxxx.."
        let s = suggest(habit(from: "2026-10-01", pattern), pattern)
        guard case .schedule(_, let to)? = s?.change else {
            Issue.record("Expected a schedule change, got \(String(describing: s))")
            return
        }
        #expect(s?.kind == .levelDown)
        #expect(to.daysPerWeek == 5)
        #expect(!to.days.contains(.tuesday) && !to.days.contains(.wednesday))
    }

    @Test func yesNoSpecificDaysLevelDownRemovesTheMostMissedDay() {
        // Mon/Wed/Fri; Wednesdays always missed, Fridays every other week (50% overall).
        var history = habit(from: "2026-10-01", schedule: days(.monday, .wednesday, .friday))
        history.completions = Set((d("2026-10-01")...d("2026-11-25")).filter {
            guard history.isScheduled(on: $0), $0.weekday != .wednesday else { return false }
            return $0.weekday != .friday || $0.julianDay / 7 % 2 == 0
        })
        let s = Suggestions.suggestion(for: HabitEvaluation(history: history, today: d("2026-11-26")))
        #expect(s?.kind == .levelDown)
        #expect(s?.change == .schedule(from: days(.monday, .wednesday, .friday), to: days(.monday, .friday)))
    }

    @Test func oneDayAWeekNeverDropsLower() {
        var history = habit(from: "2026-08-01", schedule: days(.monday))
        history.completions = []
        #expect(Suggestions.suggestion(for: HabitEvaluation(history: history, today: d("2026-11-26"))) == nil)
    }
}
