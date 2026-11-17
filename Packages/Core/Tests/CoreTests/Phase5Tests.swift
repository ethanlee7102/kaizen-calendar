@testable import Core
import Foundation
import Testing

/// Core additions for the expanded view (Phase 5).
@Suite struct Phase5Tests {
    @Test func inactiveSinceAndReasonFollowTheLastPeriod() {
        var history = habit(from: "2026-11-01", "xxx")
        #expect(history.inactiveSince == nil)
        #expect(history.inactiveReason == nil)

        history.deactivate(on: d("2026-11-04"), reason: .paused)
        #expect(history.inactiveSince == d("2026-11-04"))
        #expect(history.inactiveReason == .paused)

        history.reactivate(on: d("2026-11-08"))
        #expect(history.inactiveSince == nil)
        #expect(history.inactiveReason == nil)

        history.deactivate(on: d("2026-11-10"), reason: .graduated)
        #expect(history.inactiveSince == d("2026-11-10"))
        #expect(history.inactiveReason == .graduated)
    }
}

/// "My day ends at" changes start with the next day (user's choice after the Phase 5 review).
@Suite struct DayEndTests {
    let tz = TimeZone(identifier: "America/New_York")!

    func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        DayClock(timeZone: tz).date(on: d(day), hour: hour, minute: minute)
    }

    /// Tuesday Nov 17, 2026, 00:30 with a midnight day end: choosing 1am keeps today Tuesday.
    @Test func aLaterHourChosenAfterMidnightKeepsToday() {
        let before = DayEnd(hour: 0)
        let changed = before.changing(to: 1, at: at("2026-11-17", 0, 30), timeZone: tz)
        #expect(changed.chosenHour == 1)
        #expect(changed.change == DayEnd.Change(hour: 1, after: d("2026-11-17")))
        #expect(changed.day(for: at("2026-11-17", 0, 30), timeZone: tz) == d("2026-11-17"))
        #expect(changed.startsLater(today: d("2026-11-17")))
        // Tuesday still ends at midnight (the old hour) …
        #expect(changed.end(of: d("2026-11-17"), timeZone: tz) == at("2026-11-18", 0))
        // … and Wednesday, the first day with the new hour, never goes back to Tuesday.
        #expect(changed.day(for: at("2026-11-18", 0, 30), timeZone: tz) == d("2026-11-18"))
        #expect(changed.end(of: d("2026-11-18"), timeZone: tz) == at("2026-11-19", 1))
        #expect(changed.day(for: at("2026-11-19", 0, 30), timeZone: tz) == d("2026-11-18"))
        #expect(!changed.startsLater(today: d("2026-11-18")))
        // Without the rule today would have jumped back to Monday.
        #expect(DayClock(timeZone: tz, dayEndHour: 1).day(for: at("2026-11-17", 0, 30)) == d("2026-11-16"))
    }

    /// 1am → midnight at 00:30 (still Monday with the old hour): Monday keeps its 1am end.
    @Test func anEarlierHourStillLetsTodayEndAsPlanned() {
        let changed = DayEnd(hour: 1).changing(to: 0, at: at("2026-11-17", 0, 30), timeZone: tz)
        #expect(changed.day(for: at("2026-11-17", 0, 30), timeZone: tz) == d("2026-11-16"))
        #expect(changed.end(of: d("2026-11-16"), timeZone: tz) == at("2026-11-17", 1))
        #expect(changed.day(for: at("2026-11-17", 1), timeZone: tz) == d("2026-11-17"))
        #expect(changed.end(of: d("2026-11-17"), timeZone: tz) == at("2026-11-18", 0))
    }

    @Test func changingBackTheSameDayCancelsAndLaterChangesFoldIn() {
        let noon = at("2026-11-17", 12)
        let changed = DayEnd(hour: 0).changing(to: 2, at: noon, timeZone: tz)
        #expect(changed.changing(to: 0, at: noon, timeZone: tz) == DayEnd(hour: 0))
        #expect(changed.changing(to: 3, at: noon, timeZone: tz) == DayEnd(hour: 0, change: .init(hour: 3, after: d("2026-11-17"))))
        // Two days later the 2am change is settled; a new choice starts from there.
        let later = changed.changing(to: 4, at: at("2026-11-19", 12), timeZone: tz)
        #expect(later == DayEnd(hour: 2, change: .init(hour: 4, after: d("2026-11-19"))))
        #expect(DayEnd(hour: 0).changing(to: 0, at: noon, timeZone: tz) == DayEnd(hour: 0))
    }

    /// Whatever is chosen, whenever: today never moves backwards as time goes on.
    @Test(arguments: 1...200)
    func todayNeverMovesBackwards(seed: Int) {
        var rng = SeededRandom(seed: UInt64(seed))
        var setting = DayEnd(hour: Int.random(in: 0...4, using: &rng))
        var time = at("2026-11-01", 12)
        var last = setting.day(for: time, timeZone: tz)
        for _ in 0..<60 {
            time += TimeInterval(Int.random(in: 1...(10 * 3600), using: &rng))
            if Bool.random(using: &rng) {
                setting = setting.changing(to: Int.random(in: 0...4, using: &rng), at: time, timeZone: tz)
            }
            let today = setting.day(for: time, timeZone: tz)
            #expect(today >= last, "seed \(seed): \(today) after \(last)")
            #expect(time < setting.end(of: today, timeZone: tz), "seed \(seed): \(time) is past the end of \(today)")
            last = today
        }
    }
}
