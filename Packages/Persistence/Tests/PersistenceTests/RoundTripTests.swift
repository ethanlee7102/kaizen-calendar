import Core
import Foundation
@testable import Persistence
import Testing

/// Phase 2 is done when "a test can create habits, log a month of history, and read back the
/// same Core results" (build plan).
@Suite struct RoundTripTests {
    @Test func aMonthOfHistoryReadsBackTheSame() throws {
        let repo = try makeRepository()
        let start = d("2026-11-01")
        let read = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: start)
        let gym = try repo.addHabit(name: "Gym", kind: .yesNo, schedule: Schedule([.monday, .wednesday, .friday])!, today: start)
        var expected: [HabitID: HabitHistory] = [
            read: HabitHistory.new(id: read, kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, on: start),
            gym: HabitHistory.new(id: gym, kind: .yesNo, schedule: Schedule([.monday, .wednesday, .friday])!, on: start),
        ]

        // Read: misses Nov 7 (recovered) and Nov 15–16 (a break); rests Nov 20; target 12 from Nov 22.
        // Gym: every scheduled day, then paused Nov 25.
        for today in start...d("2026-11-30") {
            if ![d("2026-11-07"), d("2026-11-15"), d("2026-11-16"), d("2026-11-20")].contains(today) {
                try repo.setDone(true, habit: read, on: today, today: today)
                expected[read]!.setDone(true, on: today)
            }
            if today == d("2026-11-20") {
                try repo.setRested(true, habit: read, today: today)
                expected[read]!.setRested(true, on: today)
            }
            if today == d("2026-11-22") {
                try repo.changeTarget(of: read, to: 12, today: today)
                expected[read]!.changeTarget(to: 12, on: today, source: .manual)
            }
            if today == d("2026-11-25") {
                try repo.deactivate(gym, today: today)
                expected[gym]!.deactivate(on: today, reason: .paused)
            } else if today < d("2026-11-25"), expected[gym]!.isScheduled(on: today) {
                try repo.setDone(true, habit: gym, on: today, today: today)
                expected[gym]!.setDone(true, on: today)
            }
        }

        let today = d("2026-11-30")
        let stored = try repo.appData().readableHabits
        #expect(stored.map(\.history) == [expected[read]!, expected[gym]!])

        let storedEvaluations = stored.map { HabitEvaluation(history: $0.history, today: today) }
        let expectedEvaluations = [read, gym].map { HabitEvaluation(history: expected[$0]!, today: today) }
        for (a, b) in zip(storedEvaluations, expectedEvaluations) {
            #expect(a.currentStreak == b.currentStreak && a.longestStreak == b.longestStreak)
            #expect(a.journey == b.journey && a.saves == b.saves && a.breakDays == b.breakDays)
            #expect((start...today).map(a.status) == (start...today).map(b.status))
        }
        #expect(StampBook(evaluations: storedEvaluations, today: today) == StampBook(evaluations: expectedEvaluations, today: today))

        // And the numbers are the ones the rules give.
        let readResult = storedEvaluations[0]
        #expect(readResult.journey.count == 26)
        #expect(readResult.breakDays == [d("2026-11-16")])
        #expect(readResult.saves == 1)
        #expect(readResult.currentStreak == 13) // Nov 17–30 minus the Nov 20 rest
        #expect(readResult.history.target(on: today) == 12)
        #expect(storedEvaluations[1].journey.count == 10) // M/W/F Nov 2–23
        #expect(!storedEvaluations[1].isActive)
    }
}

/// Random histories written through the repository must read back exactly as Core builds them
/// in memory, and the repository must refuse exactly what the rules refuse. Seeded, so a
/// failure names its seed and reproduces.
@Suite struct RandomRoundTripTests {
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The in-memory model the repository is checked against.
    struct Mirror {
        var histories: [HabitID: HabitHistory] = [:]
        var order: [HabitID] = []
        var notes: [DayKey: String] = [:]

        var activeCount: Int { histories.values.count(where: \.isActiveNow) }
    }

    @Test(arguments: 0..<60)
    func repositoryMatchesCore(seed: Int) throws {
        var rng = Generator(state: UInt64(seed))
        let repo = try makeRepository()
        var mirror = Mirror()
        let firstDay = d("2026-01-04")
        let schedules: [Schedule] = [.everyDay, Schedule([.monday, .wednesday, .friday])!, Schedule([.saturday, .sunday])!,
                                     Schedule([.tuesday])!]

        /// Runs `action` and checks it failed exactly when `expected` says it should.
        func attempt(_ expected: Repository.Failure?, _ what: String, _ action: () throws -> Void) throws -> Bool {
            do {
                try action()
                #expect(expected == nil, "seed \(seed): \(what) should fail with \(String(describing: expected))")
                return expected == nil
            } catch let failure as Repository.Failure {
                #expect(failure == expected, "seed \(seed): \(what) failed with \(failure)")
                return false
            }
        }

        for offset in 0..<70 {
            let today = firstDay.adding(days: offset)
            for _ in 0..<Int.random(in: 0...4, using: &rng) {
                let id = mirror.order.randomElement(using: &rng)
                switch Int.random(in: 0..<100, using: &rng) {
                case 0..<8: // add
                    let kind: HabitKind = Bool.random(using: &rng) ? .yesNo : .amount(unit: "pages")
                    let schedule = schedules.randomElement(using: &rng)!
                    let expected: Repository.Failure? = mirror.activeCount >= HabitRules.maxActiveHabits ? .atHabitLimit : nil
                    var newID: HabitID?
                    if try attempt(expected, "add", {
                        newID = try repo.addHabit(name: "H", kind: kind, target: kind == .yesNo ? nil : 10, schedule: schedule, today: today)
                    }), let newID {
                        mirror.histories[newID] = HabitHistory.new(id: newID, kind: kind, target: kind == .yesNo ? nil : 10,
                                                                   schedule: schedule, on: today)
                        mirror.order.append(newID)
                    }

                case 8..<55: // check / uncheck, sometimes an older day
                    guard let id else { continue }
                    let day = today.adding(days: -Int.random(in: 0...4, using: &rng))
                    let done = Int.random(in: 0..<4, using: &rng) > 0
                    let anyway = Bool.random(using: &rng)
                    let history = mirror.histories[id]!
                    let expected: Repository.Failure? =
                        if EditRules.access(to: day, today: today) == .readOnly && !anyway { .olderDayNeedsConfirmation }
                        else if !history.isActive(on: today) { .habitInactive }
                        else if !(history.isScheduled(on: day) || history.counts(on: day)) { .dayDoesNotCount }
                        else { nil }
                    if try attempt(expected, "setDone \(done) \(day)", {
                        try repo.setDone(done, habit: id, on: day, today: today, changeAnyway: anyway)
                    }) {
                        mirror.histories[id]!.setDone(done, on: day)
                        // A rest today never survives a change that makes today a danger day.
                        var unrested = mirror.histories[id]!
                        unrested.setRested(false, on: today)
                        if unrested.rests != mirror.histories[id]!.rests,
                           HabitEvaluation(history: unrested, today: today).recovery == .danger {
                            mirror.histories[id] = unrested
                        }
                    }

                case 55..<65: // rest / undo rest
                    guard let id else { continue }
                    let rested = Int.random(in: 0..<3, using: &rng) > 0
                    let history = mirror.histories[id]!
                    let expected: Repository.Failure? =
                        if !history.isActive(on: today) { .habitInactive }
                        else if rested && !EditRules.canRest(HabitEvaluation(history: history, today: today), on: today) { .cannotRest }
                        else { nil }
                    if try attempt(expected, "setRested \(rested)", { try repo.setRested(rested, habit: id, today: today) }) {
                        mirror.histories[id]!.setRested(rested, on: today)
                    }

                case 65..<75: // target or schedule changes, 1–3 the same day (the typo rule)
                    guard let id else { continue }
                    let history = mirror.histories[id]!
                    let changeTarget = history.kind != .yesNo && Bool.random(using: &rng)
                    for _ in 0..<Int.random(in: 1...3, using: &rng) {
                    if changeTarget {
                        let amount = Int.random(in: 9...11, using: &rng)
                        let expected: Repository.Failure? = history.isActive(on: today) ? nil : .habitInactive
                        if try attempt(expected, "changeTarget", { try repo.changeTarget(of: id, to: amount, today: today, source: .suggested) }) {
                            mirror.histories[id]!.changeTarget(to: amount, on: today, source: .suggested)
                        }
                    } else {
                        let schedule = schedules.randomElement(using: &rng)!
                        let expected: Repository.Failure? = history.isActive(on: today) ? nil : .habitInactive
                        if try attempt(expected, "changeSchedule", { try repo.changeSchedule(of: id, to: schedule, today: today) }) {
                            mirror.histories[id]!.changeSchedule(to: schedule, on: today, source: .manual)
                        }
                    }
                    }

                case 75..<83: // move to inactive
                    guard let id else { continue }
                    let reason: InactiveReason = Bool.random(using: &rng) ? .paused : .graduated
                    if try attempt(nil, "deactivate", { try repo.deactivate(id, today: today, reason: reason) }) {
                        mirror.histories[id]!.deactivate(on: today, reason: reason)
                    }

                case 83..<91: // reactivate (goes to the end of the list)
                    guard let id else { continue }
                    let history = mirror.histories[id]!
                    let isActive = history.isActive(on: today)
                    let expected: Repository.Failure? =
                        !isActive && mirror.activeCount >= HabitRules.maxActiveHabits ? .atHabitLimit : nil
                    if try attempt(expected, "reactivate", { try repo.reactivate(id, today: today) }), !isActive {
                        mirror.histories[id]!.reactivate(on: today)
                        mirror.order.removeAll { $0 == id }
                        mirror.order.append(id)
                    }

                case 91..<96: // daily note
                    let day = today.adding(days: -Int.random(in: 0...3, using: &rng))
                    let text = ["", "Note", "Another note", " "].randomElement(using: &rng)!
                    let anyway = Bool.random(using: &rng)
                    let expected: Repository.Failure? =
                        EditRules.access(to: day, today: today) == .readOnly && !anyway ? .olderDayNeedsConfirmation : nil
                    if try attempt(expected, "note", { try repo.setNote(text, on: day, today: today, changeAnyway: anyway) }) {
                        mirror.notes[day] = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text
                    }

                case 96..<98: // delete, then Undo: everything back as it was, in its place
                    guard let id else { continue }
                    let deleted = try repo.deleteHabit(id)
                    #expect(try repo.appData().habit(id) == nil)
                    try repo.restore(deleted, today: today)

                default: // reorder
                    let shuffled = mirror.order.shuffled(using: &rng)
                    try repo.reorder(shuffled)
                    mirror.order = shuffled
                }

                let data = try repo.appData()
                #expect(data.habits.map(\.id) == mirror.order, "seed \(seed), \(today): order")
                for habit in data.habits {
                    #expect(try habit.history.get() == mirror.histories[habit.id], "seed \(seed), \(today): history")
                }
                #expect(data.notes == mirror.notes, "seed \(seed), \(today): notes")
                if !data.problems.isEmpty { Issue.record("seed \(seed): \(data.problems)") }
            }
        }
    }
}
