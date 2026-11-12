import Testing
@testable import Core

@Suite struct DayMarkTests {
    let today = d("2026-11-05")

    func marks(_ habits: [HabitHistory], on day: String) -> AllHabitsMark {
        DayMarks.allHabits(on: d(day), evaluations: habits.map { HabitEvaluation(history: $0, today: today) },
                           today: today)
    }

    @Test func fullSealWhenAllDone() {
        #expect(marks([habit(from: "2026-11-01", "x"), habit(from: "2026-11-01", "x")], on: "2026-11-01") == .fullSeal)
    }

    @Test func slicedSealInHabitOrder() {
        let a = habit(from: "2026-11-01", ".")
        let b = habit(from: "2026-11-01", "x")
        guard case .slicedSeal(let slices) = marks([a, b], on: "2026-11-01") else {
            Issue.record("expected a sliced seal")
            return
        }
        #expect(slices.map(\.habitID) == [a.id, b.id])
        #expect(slices.map(\.isInked) == [false, true])
    }

    @Test func restBlocksTheFullSeal() {
        // One done, one rested: sliced, not full (spec-stamp-book.md).
        guard case .slicedSeal(let slices) = marks([habit(from: "2026-11-01", "x"), habit(from: "2026-11-01", "r")],
                                                   on: "2026-11-01") else {
            Issue.record("expected a sliced seal")
            return
        }
        #expect(slices.map(\.status) == [.done, .rest])
    }

    @Test func otherMarks() {
        #expect(marks([habit(from: "2026-11-01", ".")], on: "2026-11-01") == .pencilCircle)
        #expect(marks([habit(from: "2026-11-01", "r"), habit(from: "2026-11-01", "r")], on: "2026-11-01") == .restDash)
        #expect(marks([habit(from: "2026-11-03")], on: "2026-11-01") == .faint)
        #expect(marks([habit(from: "2026-11-01", schedule: days(.monday))], on: "2026-11-01") == .faint)
        #expect(marks([habit(from: "2026-11-01")], on: "2026-11-06") == .future)
    }

    @Test func todayInProgressIsSlicedEvenWithNothingDone() {
        guard case .slicedSeal(let slices) = marks([habit(from: "2026-11-01")], on: "2026-11-05") else {
            Issue.record("expected a sliced seal")
            return
        }
        #expect(slices.map(\.status) == [.pending])
    }

    @Test func inactiveHabitsKeepTheirPastSeals() {
        var a = habit(from: "2026-11-01", "xx")
        a.deactivate(on: d("2026-11-03"), reason: .paused)
        let b = habit(from: "2026-11-01", "xxx")
        // Nov 2: both active and done. Nov 3: only b counts.
        #expect(marks([a, b], on: "2026-11-02") == .fullSeal)
        #expect(marks([a, b], on: "2026-11-03") == .fullSeal)
    }

    @Test func singleHabitMarks() {
        let e = HabitEvaluation(history: habit(from: "2026-11-01", "x.xr.."), today: d("2026-11-06"))
        #expect(DayMarks.singleHabit(on: d("2026-11-01"), evaluation: e) == .fullSeal)
        #expect(DayMarks.singleHabit(on: d("2026-11-02"), evaluation: e) == .goldSeam)
        #expect(DayMarks.singleHabit(on: d("2026-11-04"), evaluation: e) == .restDash)
        #expect(DayMarks.singleHabit(on: d("2026-11-05"), evaluation: e) == .pencilCircle)
        #expect(DayMarks.singleHabit(on: d("2026-11-06"), evaluation: e) == .todayPending)
        #expect(DayMarks.singleHabit(on: d("2026-10-31"), evaluation: e) == .faint)
    }

    @Test func todayProgress() {
        let evaluations = [habit(from: "2026-11-01", "----x"), habit(from: "2026-11-01", "----r"),
                           habit(from: "2026-11-01"), habit(from: "2026-11-01", schedule: days(.monday))]
            .map { HabitEvaluation(history: $0, today: today) }
        let progress = TodayProgress(evaluations: evaluations, today: today)
        #expect(progress.done == 1 && progress.total == 2)
        #expect(!progress.allDone)
    }

    @Test func allDoneCountsRestAsHandled() {
        let evaluations = [habit(from: "2026-11-01", "----x"), habit(from: "2026-11-01", "----r")]
            .map { HabitEvaluation(history: $0, today: today) }
        #expect(TodayProgress(evaluations: evaluations, today: today).allDone)
    }

    @Test func nothingScheduledToday() {
        let evaluations = [HabitEvaluation(history: habit(from: "2026-11-01", schedule: days(.monday)), today: today)]
        let progress = TodayProgress(evaluations: evaluations, today: today)
        #expect(progress.nothingScheduled && !progress.allDone)
    }
}

@Suite struct StampBookTests {
    @Test func countsFullSealDaysOnly() {
        let today = d("2026-11-06")
        let evaluations = [habit(from: "2026-11-01", "xxx.xx"), habit(from: "2026-11-01", "xrxxxx")]
            .map { HabitEvaluation(history: $0, today: today) }
        let book = StampBook(evaluations: evaluations, today: today)
        // Nov 2 has a rest, Nov 4 a miss.
        #expect(book.stampDays == [d("2026-11-01"), d("2026-11-03"), d("2026-11-05"), d("2026-11-06")])
    }

    @Test func emptyWithNoHabits() {
        #expect(StampBook(evaluations: [], today: d("2026-11-06")).count == 0)
    }

    @Test func darkModeUnlocksAtTheFirstStamp() {
        #expect(StampBook(stampDays: []).newUnlocks(alreadyUnlocked: []) == [])
        #expect(StampBook(stampDays: [d("2026-11-01")]).newUnlocks(alreadyUnlocked: []) == [.darkMode])
        #expect(StampBook(stampDays: [d("2026-11-01")]).newUnlocks(alreadyUnlocked: [.darkMode]) == [])
    }
}
