import Testing
@testable import Core

// Nov 1 2026 is a Sunday. Patterns: x done, . missed/pending, r rest, - no fact.

@Suite struct DayStatusTests {
    @Test func basicStatuses() {
        let e = evaluate(habit(from: "2026-11-01", "x.x"), today: "2026-11-04")
        #expect(e.status(on: d("2026-10-31")) == .beforeStart)
        #expect(e.status(on: d("2026-11-01")) == .done)
        #expect(e.status(on: d("2026-11-02")) == .missedRecovered)
        #expect(e.status(on: d("2026-11-03")) == .done)
        #expect(e.status(on: d("2026-11-04")) == .pending)
        #expect(e.status(on: d("2026-11-05")) == .future)
    }

    @Test func unscheduledDaysDontCount() {
        // Mon/Wed/Fri; created Sunday Nov 1.
        let e = evaluate(habit(from: "2026-11-01", "-x-x-x", schedule: days(.monday, .wednesday, .friday)),
                         today: "2026-11-07")
        #expect(e.status(on: d("2026-11-01")) == .notScheduled)
        #expect(e.status(on: d("2026-11-07")) == .notScheduled)
        #expect(e.scheduledDays == [d("2026-11-02"), d("2026-11-04"), d("2026-11-06")])
        #expect(e.currentStreak == 3)
        #expect(e.nextScheduledDay == d("2026-11-09"))
    }

    @Test func completionsOnUnscheduledDaysAreIgnored() {
        var history = habit(from: "2026-11-02", schedule: days(.monday))
        history.completions = [d("2026-11-03")]
        let e = evaluate(history, today: "2026-11-05")
        #expect(e.status(on: d("2026-11-03")) == .notScheduled)
        #expect(e.journey.count == 0)
    }

    @Test func missBeforeTodayPendingStaysMissed() {
        let e = evaluate(habit(from: "2026-11-01", "x."), today: "2026-11-03")
        #expect(e.status(on: d("2026-11-02")) == .missed)
        #expect(e.recovery == .danger)
    }
}

@Suite struct StreakTests {
    @Test func countsDoneDaysOnly() {
        // done, done, missed, done, done = 4-day streak (decided 2026-11-11).
        let e = evaluate(habit(from: "2026-11-01", "xx.xx"), today: "2026-11-05")
        #expect(e.currentStreak == 4)
        #expect(e.breakDays.isEmpty)
        #expect(e.saves == 1)
    }

    @Test func twoMissesInARowBreakIt() {
        let e = evaluate(habit(from: "2026-11-01", "xxx..x"), today: "2026-11-06")
        #expect(e.currentStreak == 1)
        #expect(e.longestStreak == 3)
        #expect(e.breakDays == [d("2026-11-05")])
        #expect(e.saves == 0)
        #expect(e.status(on: d("2026-11-05")) == .missed) // part of the break, not a gold seam
    }

    @Test func aLongRunOfMissesIsOneBreak() {
        let e = evaluate(habit(from: "2026-11-01", "xx.....xx"), today: "2026-11-09")
        #expect(e.breakDays == [d("2026-11-04")])
        #expect(e.currentStreak == 2)
    }

    @Test func todayPendingDoesNotBreakOrCount() {
        let e = evaluate(habit(from: "2026-11-01", "xxx."), today: "2026-11-04")
        #expect(e.currentStreak == 3)
        #expect(e.status(on: d("2026-11-04")) == .pending)
    }

    @Test func todayDoneCountsImmediately() {
        let e = evaluate(habit(from: "2026-11-01", "xxxx"), today: "2026-11-04")
        #expect(e.currentStreak == 4)
    }

    @Test func restPausesInsteadOfBreaking() {
        // miss, rest, done: the rest is skipped, so the miss is recovered.
        let e = evaluate(habit(from: "2026-11-01", "x.rx"), today: "2026-11-04")
        #expect(e.status(on: d("2026-11-02")) == .missedRecovered)
        #expect(e.status(on: d("2026-11-03")) == .rest)
        #expect(e.currentStreak == 2)
        #expect(e.breakDays.isEmpty)
    }

    @Test func restBetweenTwoMissesStillBreaks() {
        let e = evaluate(habit(from: "2026-11-01", "x.r.x"), today: "2026-11-05")
        #expect(e.breakDays == [d("2026-11-04")])
        #expect(e.currentStreak == 1)
    }

    @Test func unscheduledDaysBetweenMissesStillBreak() {
        // Mon/Thu: miss Mon Nov 2, miss Thu Nov 5 → break (scheduled days in a row).
        let e = evaluate(habit(from: "2026-11-02", "...", schedule: days(.monday, .thursday)), today: "2026-11-06")
        #expect(e.breakDays == [d("2026-11-05")])
    }

    @Test func missOnFirstDayThenDoneIsRecovered() {
        let e = evaluate(habit(from: "2026-11-01", ".x"), today: "2026-11-02")
        #expect(e.status(on: d("2026-11-01")) == .missedRecovered)
        #expect(e.currentStreak == 1)
        #expect(e.recovery == .recovered)
    }

    @Test func backfillChangesPastStates() {
        var history = habit(from: "2026-11-01", "xx..")
        #expect(evaluate(history, today: "2026-11-05").breakDays == [d("2026-11-04")])
        history.completions.insert(d("2026-11-04")) // backfilled
        let e = evaluate(history, today: "2026-11-05")
        #expect(e.breakDays.isEmpty)
        #expect(e.status(on: d("2026-11-03")) == .missedRecovered)
        #expect(e.currentStreak == 3)
    }

    @Test func scheduleChangeMidStreak() {
        // Daily for a week, then only Mondays from Sun Nov 8. Tue–Sat no longer count.
        var history = habit(from: "2026-11-01", "xxxxxxx")
        history.changeSchedule(to: days(.monday), on: d("2026-11-08"), source: .manual)
        history.completions.insert(d("2026-11-09"))
        let e = evaluate(history, today: "2026-11-14")
        #expect(e.status(on: d("2026-11-10")) == .notScheduled)
        #expect(e.status(on: d("2026-11-03")) == .done) // the past is unchanged
        #expect(e.currentStreak == 8)
    }
}

@Suite struct InactiveTests {
    @Test func inactiveDaysAreSkippedAndStreakContinues() {
        var history = habit(from: "2026-11-01", "xxx")
        history.deactivate(on: d("2026-11-04"), reason: .paused)
        #expect(!history.isActive(on: d("2026-11-04")))
        history.reactivate(on: d("2026-11-10"))
        history.completions.insert(d("2026-11-10"))
        let e = evaluate(history, today: "2026-11-10")
        #expect(e.status(on: d("2026-11-05")) == .inactive)
        #expect(e.currentStreak == 4)
        #expect(e.breakDays.isEmpty)
        #expect(e.journey.count == 4)
    }

    @Test func frozenWhileInactive() {
        var history = habit(from: "2026-11-01", "xx.")
        history.deactivate(on: d("2026-11-04"), reason: .graduated)
        let e = evaluate(history, today: "2026-11-20")
        #expect(e.status(on: d("2026-11-03")) == .missed)
        #expect(e.currentStreak == 2)
        #expect(e.nextScheduledDay == nil)
        #expect(e.recovery == .none)
        #expect(history.activePeriods.last?.endReason == .graduated)
    }

    @Test func sameDayReactivateMergesPeriods() {
        var history = habit(from: "2026-11-01")
        history.deactivate(on: d("2026-11-05"), reason: .paused)
        history.reactivate(on: d("2026-11-05"))
        #expect(history.activePeriods == [ActivePeriod(start: d("2026-11-01"))])
    }
}

@Suite struct RecoveryLineTests {
    @Test func dangerThenRecovered() {
        #expect(evaluate(habit(from: "2026-11-01", "x."), today: "2026-11-03").recovery == .danger)
        #expect(evaluate(habit(from: "2026-11-01", "x.x"), today: "2026-11-03").recovery == .recovered)
    }

    @Test func noDangerOnceTheStreakIsAlreadyBroken() {
        // Two misses already broke it, so "Never miss twice" would be untrue.
        #expect(evaluate(habit(from: "2026-11-01", "x.."), today: "2026-11-04").recovery == .none)
    }

    @Test func restingToday() {
        #expect(evaluate(habit(from: "2026-11-01", "x.r"), today: "2026-11-03").recovery == .resting)
    }

    @Test func noDangerOnUnscheduledToday() {
        // Missed Monday, today is Tuesday (not scheduled): nothing to do today.
        let e = evaluate(habit(from: "2026-11-02", ".", schedule: days(.monday, .thursday)), today: "2026-11-03")
        #expect(e.recovery == .none)
        #expect(e.status(on: d("2026-11-02")) == .missed)
    }

    @Test func dangerAcrossARestDay() {
        // Missed, rested yesterday, today pending: still one miss to recover.
        #expect(evaluate(habit(from: "2026-11-01", "x.r"), today: "2026-11-04").recovery == .danger)
    }
}

@Suite struct JourneyTests {
    @Test func countsDoneDaysAndNeverResets() {
        let e = evaluate(habit(from: "2026-11-01", "xx...x"), today: "2026-11-06")
        #expect(e.journey.count == 3)
        #expect(e.currentStreak == 1)
        #expect(e.journey.dayReached(3) == d("2026-11-06"))
        #expect(e.journey.dayReached(4) == nil)
    }

    @Test func reaches66AndMilestones() {
        let pattern = String(repeating: "x", count: 70)
        let e = evaluate(habit(from: "2026-01-01", pattern), today: "2026-03-11")
        #expect(e.journey.count == 70)
        #expect(e.journey.hasReached66)
        #expect(e.journey.dayReached(66) == d("2026-03-07"))
        #expect(e.journey.nextMilestone == 100)
        #expect(e.journey.reachedMilestones == [66])
        #expect(e.journey.progress == 1)
    }

    @Test func noMilestoneAfter365() {
        #expect(Journey(doneDays: Array(d("2025-01-01")...d("2026-01-10"))).nextMilestone == nil)
        #expect(Journey(doneDays: []).nextMilestone == 66)
    }
}

@Suite struct ConsistencyTests {
    @Test func excludesRestAndPendingToday() {
        let e = evaluate(habit(from: "2026-11-01", "xx.rx."), today: "2026-11-06")
        let c = e.consistency(in: DayRange(d("2026-11-01"), d("2026-11-06")))
        #expect(c.done == 3 && c.scheduled == 4)
        #expect(c.percent == 75)
    }

    @Test func nothingScheduledHasNoRate() {
        let e = evaluate(habit(from: "2026-11-10"), today: "2026-11-12")
        #expect(e.consistency(in: DayRange(d("2026-11-01"), d("2026-11-05"))).rate == nil)
    }
}

@Suite struct HistoryChangeTests {
    @Test func sameDayTargetChangeReplacesInsteadOfAddingHistory() {
        var history = habit(from: "2026-11-01", kind: .amount(unit: "pages"), target: 10)
        history.changeTarget(to: 12, on: d("2026-11-01"), source: .manual) // typo fix on day one
        #expect(history.targetChanges == [TargetChange(day: d("2026-11-01"), amount: 12, source: .initial)])

        history.changeTarget(to: 15, on: d("2026-11-10"), source: .suggested)
        history.changeTarget(to: 14, on: d("2026-11-10"), source: .manual) // fixed the same day
        #expect(history.targetChanges.count == 2)
        #expect(history.targetChanges.last == TargetChange(day: d("2026-11-10"), amount: 14, source: .manual))

        history.changeTarget(to: 12, on: d("2026-11-10"), source: .manual) // changed back: no entry
        #expect(history.targetChanges.count == 1)
        #expect(history.target(on: d("2026-11-20")) == 12)
    }

    @Test func targetLookupByDay() {
        var history = habit(from: "2026-11-01", kind: .amount(unit: "pages"), target: 5)
        history.changeTarget(to: 8, on: d("2026-11-14"), source: .suggested)
        #expect(history.target(on: d("2026-11-13")) == 5)
        #expect(history.target(on: d("2026-11-14")) == 8)
        #expect(history.lastChangeDay == d("2026-11-14"))
    }

    @Test func unchangedTargetAddsNothing() {
        var history = habit(from: "2026-11-01", kind: .amount(unit: "pages"), target: 5)
        history.changeTarget(to: 5, on: d("2026-11-05"), source: .manual)
        #expect(history.targetChanges.count == 1)
    }
}

@Suite struct EditRulesTests {
    @Test func todayAndTwoDaysBackAreEditable() {
        let today = d("2026-11-11")
        #expect(EditRules.access(to: today, today: today) == .editable)
        #expect(EditRules.access(to: d("2026-11-09"), today: today) == .editable)
        #expect(EditRules.access(to: d("2026-11-08"), today: today) == .readOnly)
        #expect(EditRules.access(to: d("2026-11-12"), today: today) == .future)
    }

    @Test func restOnlyTodayAndOnlyWhenOpen() {
        let e = evaluate(habit(from: "2026-11-01", "xx."), today: "2026-11-03")
        #expect(EditRules.canRest(e, on: d("2026-11-03")))
        #expect(!EditRules.canRest(e, on: d("2026-11-02")))
        let done = evaluate(habit(from: "2026-11-01", "x"), today: "2026-11-01")
        #expect(!EditRules.canRest(done, on: d("2026-11-01")))
    }

    @Test func addHabitLimits() {
        #expect(HabitRules.addHabitState(activeCount: 2) == .allowed)
        #expect(HabitRules.addHabitState(activeCount: 3) == .allowedWithNudge)
        #expect(HabitRules.addHabitState(activeCount: 5) == .atLimit)
    }
}
