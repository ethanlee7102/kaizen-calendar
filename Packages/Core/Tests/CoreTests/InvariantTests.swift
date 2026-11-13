import Foundation
import Testing
@testable import Core

/// Deterministic random numbers (SplitMix64) so a failure can be reproduced from its seed.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A random but valid habit history: random schedule and target changes, check-offs, rests,
/// and pause/reactivate periods, between `start` and `today`.
func randomHistory(_ rng: inout SeededRandom, start: DayKey, today: DayKey) -> HabitHistory {
    let created = start.adding(days: Int.random(in: 0...max(0, start.days(to: today)), using: &rng))
    let isAmount = Bool.random(using: &rng)
    func randomSchedule() -> Schedule {
        Bool.random(using: &rng) ? .everyDay : Schedule(days: WeekdaySet(rawValue: UInt8.random(in: 1...127, using: &rng)))!
    }
    var history = HabitHistory.new(kind: isAmount ? .amount(unit: "pages") : .yesNo,
                                   target: isAmount ? Int.random(in: 1...30, using: &rng) : nil,
                                   schedule: randomSchedule(), on: created)
    // How reliable this habit is, so some histories are mostly done and some mostly missed.
    let doneChance = Double.random(in: 0.3...1, using: &rng)
    var active = true
    for day in created...today {
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll < 0.01 { history.changeSchedule(to: randomSchedule(), on: day, source: .manual) }
        if isAmount, roll > 0.99 {
            history.changeTarget(to: Int.random(in: 1...40, using: &rng), on: day, source: .suggested)
        }
        if active, Double.random(in: 0..<1, using: &rng) < 0.004 {
            history.deactivate(on: day, reason: Bool.random(using: &rng) ? .paused : .graduated)
            active = false
        } else if !active, Double.random(in: 0..<1, using: &rng) < 0.05 {
            history.reactivate(on: day)
            active = true
        }
        let act = Double.random(in: 0..<1, using: &rng)
        if act < doneChance {
            history.setDone(true, on: day)
        } else if act < doneChance + 0.03 {
            history.setRested(true, on: day)
        }
    }
    return history
}

@Suite struct InvariantTests {
    static let seeds: [UInt64] = Array(1...400)

    /// The streak / journey / recovery rules, checked on random histories.
    @Test(arguments: seeds)
    func habitRulesAlwaysHold(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let today = d("2026-11-12")
        let history = randomHistory(&rng, start: d("2026-01-01"), today: today)
        let e = HabitEvaluation(history: history, today: today)

        // Days counted are in order, end by today, and all count.
        #expect(e.scheduledDays == e.scheduledDays.sorted())
        #expect(e.scheduledDays.allSatisfy { $0 <= today && history.counts(on: $0) })

        let counted = e.scheduledDays.filter { e.status(on: $0) != .rest }
        let statuses = counted.map { e.status(on: $0) }

        // Journey = done days.
        #expect(e.journey.count == statuses.count { $0 == .done })
        #expect(e.doneDays == counted.filter { e.status(on: $0) == .done })
        #expect(e.currentStreak <= e.longestStreak)
        #expect(e.longestStreak <= e.journey.count)

        for (i, status) in statuses.enumerated() {
            let previous = i > 0 ? statuses[i - 1] : nil
            let next = i + 1 < statuses.count ? statuses[i + 1] : nil
            if status == .missedRecovered {
                // A gold seam: a single miss followed by a done day.
                #expect(next == .done, "seed \(seed): recovered miss on \(counted[i]) not followed by done")
                #expect(previous?.isMiss != true, "seed \(seed): recovered miss on \(counted[i]) follows a miss")
            }
            if status == .missed, previous?.isMiss != true {
                // A single miss that isn't recovered: the next day isn't done (yet).
                #expect(next != .done, "seed \(seed): unrecovered single miss on \(counted[i]) followed by done")
            }
            if status == .pending { #expect(counted[i] == today) }
        }

        // One break per run of 2+ misses, on the run's second miss.
        var expectedBreaks: [DayKey] = []
        var run = 0
        for (i, status) in statuses.enumerated() {
            run = status.isMiss ? run + 1 : 0
            if run == 2 { expectedBreaks.append(counted[i]) }
        }
        #expect(e.breakDays == expectedBreaks, "seed \(seed)")

        // Current streak = done days since the last break.
        let sinceBreak = e.breakDays.last.map { last in e.doneDays.filter { $0 > last } } ?? e.doneDays
        #expect(e.currentStreak == sinceBreak.count, "seed \(seed)")

        // Danger only when actionable today; no rest on a danger day.
        if e.recovery == .danger {
            #expect(e.status(on: today) == .pending)
            #expect(!EditRules.canRest(e, on: today))
        }

        // Consistency is a proper fraction.
        let c = e.consistency(in: DayRange(history.createdDay, today))
        #expect(c.done <= c.scheduled)
        #expect(c.rate.map { (0...1).contains($0) } ?? true)

        // Day-66 report exists exactly when the journey reached 66.
        #expect((Day66Report(evaluation: e, notes: []) != nil) == e.journey.hasReached66)

        // Suggestions only for active habits, and they move in the right direction.
        if let s = Suggestions.suggestion(for: e) {
            #expect(history.isActiveNow)
            switch (s.kind, s.change) {
            case (.levelUp, .target(let from, let to)): #expect(to > from)
            case (.levelDown, .target(let from, let to)): #expect(to < from && to >= 1)
            case (.levelUp, .schedule(let from, let to)): #expect(to.daysPerWeek > from.daysPerWeek)
            case (.levelDown, .schedule(let from, let to)): #expect(to.daysPerWeek < from.daysPerWeek && to.daysPerWeek >= 1)
            }
        }
    }

    /// Calendar marks and the stamp book agree for random groups of habits.
    @Test(arguments: Array(seeds.prefix(100)))
    func marksAndStampsAgree(seed: UInt64) {
        var rng = SeededRandom(seed: seed &+ 10_000)
        let today = d("2026-11-12")
        let evaluations = (0..<Int.random(in: 1...5, using: &rng)).map { _ in
            HabitEvaluation(history: randomHistory(&rng, start: d("2026-06-01"), today: today), today: today)
        }
        let stamps = Set(StampBook(evaluations: evaluations, today: today).stampDays)
        for day in d("2026-06-01")...today {
            let mark = DayMarks.allHabits(on: day, evaluations: evaluations, today: today)
            #expect((mark == .fullSeal) == stamps.contains(day), "seed \(seed) \(day)")
            let statuses = evaluations.map { $0.status(on: day) }.filter(\.isScheduled)
            switch mark {
            case .fullSeal: #expect(!statuses.isEmpty && statuses.allSatisfy { $0 == .done })
            case .restDash: #expect(!statuses.isEmpty && statuses.allSatisfy { $0 == .rest })
            case .pencilCircle: #expect(day < today && !statuses.contains(.done))
            case .faint: #expect(statuses.isEmpty)
            case .slicedSeal(let slices): #expect(slices.count == statuses.count)
            case .future: Issue.record("past day marked future")
            }
        }
        let progress = TodayProgress(evaluations: evaluations, today: today)
        #expect(progress.done <= progress.total)
    }

    /// Changing the delivery day at random never covers a week twice or skips one.
    @Test(arguments: Array(seeds.prefix(100)))
    func reportsCoverEachWeekOnce(seed: UInt64) {
        var rng = SeededRandom(seed: seed &+ 20_000)
        let clock = DayClock(timeZone: TimeZone(identifier: "America/New_York")!)
        let firstUse = d("2026-01-01").adding(days: Int.random(in: 0...60, using: &rng))
        var settings = ReportSettings()
        var lastCovered: DayKey?
        var lastMonthly: DayKey?
        var weeklyEnds: [DayKey] = []
        var monthlyPeriods: [DayRange] = []
        var day = firstUse
        while day < d("2027-06-01") {
            if Double.random(in: 0..<1, using: &rng) < 0.1 {
                settings = ReportSettings(weekday: Weekday.allCases.randomElement(using: &rng)!,
                                          hour: Int.random(in: 0...23, using: &rng))
            }
            let now = clock.date(on: day, hour: Int.random(in: 0...23, using: &rng), minute: 0)
            let due = ReportSchedule(settings: settings, clock: clock)
                .dueReports(lastCoveredWeekEnd: lastCovered, lastMonthlyPeriodEnd: lastMonthly, firstUseDay: firstUse, now: now)
            for report in due {
                #expect(report.period.start.weekday == .sunday && report.period.end.weekday == .saturday)
                #expect(report.period.end < report.deliveryDay)
                if let lastCovered { #expect(report.period.end > lastCovered, "seed \(seed): week repeated") }
                switch report.kind {
                case .weekly: weeklyEnds.append(report.period.end)
                case .monthly:
                    if let previous = monthlyPeriods.last {
                        #expect(report.period.start == previous.end.adding(days: 1), "seed \(seed): monthly gap")
                    }
                    monthlyPeriods.append(report.period)
                    lastMonthly = report.period.end
                }
                lastCovered = report.period.end
            }
            // Advance 1–4 days (the Mac is sometimes off for a while).
            day = day.adding(days: Int.random(in: 1...4, using: &rng))
        }
        #expect(Set(weeklyEnds).count == weeklyEnds.count)
        #expect(!weeklyEnds.isEmpty && !monthlyPeriods.isEmpty)
    }

    /// Guards the tests above against being vacuous: the random histories must actually reach
    /// every tricky case.
    @Test func randomHistoriesExerciseEveryRule() {
        var counts: [String: Int] = [:]
        let today = d("2026-11-12")
        for seed in Self.seeds {
            var rng = SeededRandom(seed: seed)
            let history = randomHistory(&rng, start: d("2026-01-01"), today: today)
            let e = HabitEvaluation(history: history, today: today)
            let statuses = e.scheduledDays.map { e.status(on: $0) }
            if statuses.contains(.missedRecovered) { counts["gold seam", default: 0] += 1 }
            if !e.breakDays.isEmpty { counts["break", default: 0] += 1 }
            if statuses.contains(.rest) { counts["rest", default: 0] += 1 }
            if history.activePeriods.count > 1 { counts["reactivated", default: 0] += 1 }
            if !history.isActiveNow { counts["inactive now", default: 0] += 1 }
            if history.activePeriods.contains(where: { $0.end.map { history.counts(on: $0) && !history.isActive(on: $0) } ?? false }) {
                counts["done on deactivation day", default: 0] += 1
            }
            if history.scheduleChanges.count > 1 { counts["schedule change", default: 0] += 1 }
            if e.journey.hasReached66 { counts["day 66", default: 0] += 1 }
            if e.recovery == .danger { counts["danger", default: 0] += 1 }
            if let s = Suggestions.suggestion(for: e) { counts["\(s.kind)", default: 0] += 1 }
        }
        for feature in ["gold seam", "break", "rest", "reactivated", "inactive now", "done on deactivation day",
                        "schedule change", "day 66", "danger", "levelUp", "levelDown"] {
            #expect(counts[feature, default: 0] >= 3, "only \(counts[feature, default: 0]) random histories have \(feature)")
        }
    }

    @Test(arguments: Array(seeds.prefix(50)))
    func dayKeyRoundTrips(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let day = DayKey(julianDay: Int.random(in: 2_000_000...2_600_000, using: &rng))
        #expect(DayKey(day.description) == day)
        #expect(DayKey(year: day.year, month: day.month, day: day.day) == day)
        #expect(day.adding(days: 1).weekday.rawValue == (day.weekday.rawValue + 1) % 7)
    }
}

@Suite struct PerformanceTests {
    /// 5 habits × 3 years: everything the note and calendar need must stay fast, since views
    /// recompute it. Debug builds are slow, so the bound is generous.
    @Test func threeYearsOfFiveHabitsIsFast() {
        var rng = SeededRandom(seed: 42)
        let today = d("2026-11-12")
        let histories = (0..<5).map { _ in randomHistory(&rng, start: d("2023-11-12"), today: d("2023-11-12")) }
            .map { history -> HabitHistory in
                var h = history
                for day in h.createdDay...today where Double.random(in: 0..<1, using: &rng) < 0.85 {
                    h.setDone(true, on: day)
                }
                return h
            }
        let elapsed = ContinuousClock().measure {
            let evaluations = histories.map { HabitEvaluation(history: $0, today: today) }
            _ = StampBook(evaluations: evaluations, today: today)
            for day in MonthGrid(containing: today).days {
                _ = DayMarks.allHabits(on: day, evaluations: evaluations, today: today)
            }
            _ = evaluations.map { Suggestions.suggestion(for: $0) }
            _ = Insights.weeklyTrend(evaluations, through: today)
            _ = evaluations.map { Insights.weakestWeekday($0, through: today) }
        }
        #expect(elapsed < .seconds(1), "took \(elapsed)")
    }
}
