import Foundation
import Testing
@testable import Core

/// The never-miss-twice reminder's schedule and prompt (spec-notifications.md, Phase 8).
@Suite struct ReminderPlanTests {
    typealias R = NeverMissTwiceReminder

    let la = TimeZone(identifier: "America/Los_Angeles")!
    var clock: DayClock { DayClock(timeZone: la) }
    let today = d("2026-11-14")
    let read = R.Item(name: "Read", streak: 12)

    /// The reminder a plan schedules, if it schedules one.
    func scheduledBy(_ plan: R.Plan) -> R.Pending? {
        if case .schedule(let pending) = plan.pending { pending } else { nil }
    }

    func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date { clock.date(on: d(day), hour: hour, minute: minute) }

    func plan(items: [R.Item]? = nil, enabled: Bool = true, canNotify: Bool = true, now: Date,
              fire: Date? = nil, last: R.Scheduled? = nil) -> R.Plan {
        R.plan(items: items ?? [read], isEnabled: enabled, canNotify: canNotify, today: today, now: now,
               fireDate: fire ?? at("2026-11-14", 20), last: last)
    }

    // MARK: Fire date

    @Test func eightPmOnTheDay() {
        #expect(R.fireDate(on: today, hour: 20, minute: 0, dayEnd: DayEnd(), timeZone: la) == at("2026-11-14", 20))
    }

    @Test func aTimeAfterMidnightBeforeTheDayEndBelongsToTheSameDay() {
        // 2am day end: Saturday runs until Sunday 2am, so a 1am reminder is Sunday 1am.
        #expect(R.fireDate(on: today, hour: 1, minute: 0, dayEnd: DayEnd(hour: 2), timeZone: la) == at("2026-11-15", 1))
        // At 2am or later it's the day's own date.
        #expect(R.fireDate(on: today, hour: 2, minute: 0, dayEnd: DayEnd(hour: 2), timeZone: la) == at("2026-11-14", 2))
    }

    @Test func aDayEndChosenTodayStartsTomorrow() {
        // Chosen on Saturday: Saturday still ends at midnight, so 1am is Saturday's early morning.
        let dayEnd = DayEnd(hour: 0, change: .init(hour: 2, after: today))
        #expect(R.fireDate(on: today, hour: 1, minute: 0, dayEnd: dayEnd, timeZone: la) == at("2026-11-14", 1))
        // Sunday still starts at midnight (a change never moves a day backwards) and ends Monday
        // 2am, so Sunday's 1am is its own early morning; Monday starts at 2am, so Monday's is
        // Tuesday 1am.
        #expect(R.fireDate(on: d("2026-11-15"), hour: 1, minute: 0, dayEnd: dayEnd, timeZone: la) == at("2026-11-15", 1))
        #expect(R.fireDate(on: d("2026-11-16"), hour: 1, minute: 0, dayEnd: dayEnd, timeZone: la) == at("2026-11-17", 1))
    }

    @Test func items() {
        let missed = habit(from: "2026-11-12", "x.")
        let fine = habit(from: "2026-11-12", "xx")
        let unnamed = habit(from: "2026-11-12", "x.")
        let names = [missed.id: "Read", fine.id: "Walk"]
        let evaluations = [missed, fine, unnamed].map { HabitEvaluation(history: $0, today: today) }
        #expect(R.items(evaluations) { names[$0] } == [R.Item(name: "Read", streak: 1)])
    }

    // MARK: Plan

    @Test func schedulesTonightWhileAHabitQualifies() {
        let result = plan(now: at("2026-11-14", 12))
        let scheduled = R.Scheduled(day: today, fireDate: at("2026-11-14", 20))
        #expect(scheduledBy(result)?.scheduled == scheduled)
        #expect(scheduledBy(result)?.message.title == "Read: never miss twice.")
        #expect(result.record == scheduled)
        #expect(!result.keepsDelivered)
    }

    @Test func nothingWhenOffNotAllowedOrNothingQualifies() {
        for result in [plan(enabled: false, now: at("2026-11-14", 12)),
                       plan(canNotify: false, now: at("2026-11-14", 12)),
                       plan(items: [], now: at("2026-11-14", 12))] {
            #expect(result.pending == .cancel)
            #expect(result.record == nil)
            #expect(!result.keepsDelivered)
        }
    }

    @Test func cancelledWhenDoneBeforeItFires() {
        // Scheduled at noon; Read is checked off at 7pm: nothing waits, and nothing is kept, so
        // unchecking it again schedules it again.
        let last = R.Scheduled(day: today, fireDate: at("2026-11-14", 20))
        let result = plan(items: [], now: at("2026-11-14", 19), last: last)
        #expect(result.pending == .cancel)
        #expect(result.record == nil)
        #expect(scheduledBy(plan(now: at("2026-11-14", 19, 30), last: result.record))?.scheduled == last)
    }

    @Test func atMostOneAnEvening() {
        // It fired at 8pm; at 8:30 the time is moved to 9pm. No second one.
        let fired = R.Scheduled(day: today, fireDate: at("2026-11-14", 20))
        let result = plan(now: at("2026-11-14", 20, 30), fire: at("2026-11-14", 21), last: fired)
        #expect(result.pending == .leave)
        #expect(result.record == fired)
        #expect(result.keepsDelivered)
    }

    @Test func aFiredReminderIsRemovedOnceItNoLongerApplies() {
        let fired = R.Scheduled(day: today, fireDate: at("2026-11-14", 20))
        // Done after it fired.
        #expect(!plan(items: [], now: at("2026-11-14", 21), last: fired).keepsDelivered)
        // Turned off.
        #expect(!plan(enabled: false, now: at("2026-11-14", 21), last: fired).keepsDelivered)
        // The next day (yesterday's reminder is stale), with nothing due yet.
        let tomorrow = R.plan(items: [], isEnabled: true, canNotify: true, today: d("2026-11-15"),
                              now: at("2026-11-15", 9), fireDate: at("2026-11-15", 20), last: fired)
        #expect(!tomorrow.keepsDelivered)
    }

    @Test func yesterdaysReminderDoesNotBlockToday() {
        let yesterday = R.Scheduled(day: d("2026-11-13"), fireDate: at("2026-11-13", 20))
        let result = R.plan(items: [read], isEnabled: true, canNotify: true, today: today, now: at("2026-11-14", 9),
                            fireDate: at("2026-11-14", 20), last: yesterday)
        #expect(scheduledBy(result)?.scheduled == R.Scheduled(day: today, fireDate: at("2026-11-14", 20)))
    }

    @Test func notScheduledOnceTheTimeHasPassed() {
        // Opened at 9pm: too late for tonight (no late reminder).
        let result = plan(now: at("2026-11-14", 21))
        #expect(result.pending == .cancel)
        #expect(result.record == nil)
    }

    @Test func theRecordSurvivesAMoveToALaterTimeBeforeItFires() {
        // Scheduled for 8pm, moved to 9pm at 7pm: one pending reminder, at 9pm.
        let last = R.Scheduled(day: today, fireDate: at("2026-11-14", 20))
        let result = plan(now: at("2026-11-14", 19), fire: at("2026-11-14", 21), last: last)
        #expect(scheduledBy(result)?.scheduled.fireDate == at("2026-11-14", 21))
    }

    /// Phase 8 review: at the reminder time (+1s) or on waking after it, the reminder may not be
    /// delivered yet. Cancelling the "pending" one then would lose it.
    @Test func aFiredReminderThatStillAppliesIsLeftAlone() {
        let fired = R.Scheduled(day: today, fireDate: at("2026-11-14", 20))
        let justAfter = plan(now: at("2026-11-14", 20, 0).addingTimeInterval(1), last: fired)
        #expect(justAfter.pending == .leave)
        #expect(justAfter.keepsDelivered)
        // No longer applies: cancelled (in case it's still waiting) and removed.
        let done = plan(items: [], now: at("2026-11-14", 21), last: fired)
        #expect(done.pending == .cancel)
        #expect(!done.keepsDelivered)
        // The next day: yesterday's is cancelled too.
        let tomorrow = R.plan(items: [read], isEnabled: true, canNotify: true, today: d("2026-11-15"),
                              now: at("2026-11-15", 21), fireDate: at("2026-11-15", 20), last: fired)
        #expect(tomorrow.pending == .cancel)
    }

    // MARK: Hours offered

    @Test func reminderHoursRunFromNoonToTheDaysLastHour() {
        #expect(R.reminderHours(dayEndHour: 0, including: 20) == Array(12...23))
        #expect(R.reminderHours(dayEndHour: 2, including: 20) == Array(12...23) + [0, 1])
        // The day-end hour itself is never offered (it would be the day's very start: Phase 8
        // review).
        #expect(!R.reminderHours(dayEndHour: 0, including: 20).contains(0))
        #expect(!R.reminderHours(dayEndHour: 2, including: 20).contains(2))
    }

    @Test func aStoredHourOutsideTheRangeStillShowsInDayOrder() {
        // 1am chosen with a 2am day end, then the day end moved back to midnight.
        #expect(R.reminderHours(dayEndHour: 0, including: 1) == [1] + Array(12...23))
        #expect(R.reminderHours(dayEndHour: 2, including: 8) == [8] + Array(12...23) + [0, 1])
    }

    // MARK: Prompt

    @Test func promptShowsOnlyWhenItWouldHelpTonight() {
        let fire = at("2026-11-14", 20)
        #expect(R.showsPrompt(anyQualifies: true, isEnabled: true, permissionUndecided: true, now: at("2026-11-14", 12), fireDate: fire))
        #expect(!R.showsPrompt(anyQualifies: false, isEnabled: true, permissionUndecided: true, now: at("2026-11-14", 12), fireDate: fire))
        #expect(!R.showsPrompt(anyQualifies: true, isEnabled: false, permissionUndecided: true, now: at("2026-11-14", 12), fireDate: fire))
        #expect(!R.showsPrompt(anyQualifies: true, isEnabled: true, permissionUndecided: false, now: at("2026-11-14", 12), fireDate: fire))
        #expect(!R.showsPrompt(anyQualifies: true, isEnabled: true, permissionUndecided: true, now: fire, fireDate: fire))
    }
}
