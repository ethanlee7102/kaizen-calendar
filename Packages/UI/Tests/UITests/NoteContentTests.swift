import Core
import Testing
@testable import UI

/// What the note shows (spec-collapsed-note.md §2–§4, §6–§8, spec-edge-states.md), checked on
/// `Fixture.month()`: see its comment for the history.
@Suite struct NoteRowTests {
    let input = Fixture.month()

    @Test func subtitlesCoverStreakNotScheduledAndStartsToday() {
        let rows = input.rows
        #expect(rows.map(\.name) == ["Read", "Pushups", "Floss", "Meditate"])
        #expect(rows.map(\.subtitle) == [
            "10 pages · 2-day streak",          // done days since the Nov 9 break, rest skipped
            "15 pushups · 6-day streak",         // Mon/Wed/Fri; today (Saturday) isn't one of its days
            "10-day streak",                     // daily yes/no: streak only
            "starts today",                      // new, nothing decided yet
        ])
    }

    @Test func leavesAndWhatTheyDo() {
        let rows = input.rows
        #expect(rows.map(\.check) == [.leaf(.unchecked), .next("next: Mon"), .leaf(.checked), .leaf(.unchecked)])
        #expect(rows.map(\.canToggle) == [true, false, true, true])
        #expect(rows.map(\.isDone) == [false, false, true, false])
        #expect(rows.map(\.journey.count) == [15, 6, 10, 0])
    }

    @Test func dangerLineTurnsIntoRecoveredWhenCheckedToday() {
        #expect(input.rows[0].line == .danger)
        #expect(RowLine.danger.text == "Never miss twice. Today counts.")
        var read = input.habits[0].evaluation.history
        read.setDone(true, on: Fixture.today)
        var checked = input
        checked.habits[0] = NoteHabit(name: "Read", identity: nil, evaluation: HabitEvaluation(history: read, today: Fixture.today))
        #expect(checked.rows[0].line == .recovered)
        #expect(RowLine.recovered.text == "Recovered. You didn’t miss twice.")
    }

    /// User's request (2026-11-15): habits not scheduled today go in a folded section below.
    @Test func habitsNotScheduledTodayAreSplitOff() {
        #expect(input.scheduledRows.map(\.name) == ["Read", "Floss", "Meditate"])
        #expect(input.unscheduledRows.map(\.name) == ["Pushups"])
        let walk = noteHabit("Walk", created: "2026-11-10", done: days("2026-11-10", "2026-11-13"), rested: [Fixture.today],
                             today: Fixture.today)
        #expect(NoteInput(today: Fixture.today, habits: [walk]).scheduledRows.count == 1, "A rested habit stays in the list")
    }

    @Test func restedRowShowsTheRestLineAndCanStillBeCheckedOff() {
        let walk = noteHabit("Walk", created: "2026-11-10", done: days("2026-11-10", "2026-11-13"), rested: [Fixture.today],
                             today: Fixture.today)
        let row = NoteInput(today: Fixture.today, habits: [walk]).rows[0]
        #expect(row.line == .resting)
        #expect(RowLine.resting.text == "Rest day. Streak paused.")
        #expect(row.check == .leaf(.rested))
        #expect(row.canToggle, "Checking off a rested habit clears the rest")
    }

    @Test func yesNoHabitOnSomeDaysSaysHowManyDaysAWeek() {
        let habit = noteHabit("Swim", schedule: Schedule([.tuesday, .thursday, .saturday])!, created: "2026-11-10",
                              done: [d("2026-11-10"), d("2026-11-12")], today: Fixture.today)
        #expect(NoteInput(today: Fixture.today, habits: [habit]).rows[0].subtitle == "3 days a week · 2-day streak")
        let once = noteHabit("Call home", schedule: Schedule([.saturday])!, created: "2026-11-14", today: Fixture.today)
        #expect(NoteInput(today: Fixture.today, habits: [once]).rows[0].subtitle == "1 day a week · starts today")
    }

    @Test func aNewHabitNotScheduledTodaySaysSo() {
        let habit = noteHabit("Gym", kind: .amount(unit: "minutes"), target: 20, schedule: Schedule([.monday])!,
                              created: "2026-11-14", today: Fixture.today)
        #expect(NoteInput(today: Fixture.today, habits: [habit]).rows[0].subtitle == "20 minutes · starts Mon")
        let sunday = noteHabit("Call home", schedule: Schedule([.sunday])!, created: "2026-11-14", today: Fixture.today)
        #expect(NoteInput(today: Fixture.today, habits: [sunday]).rows[0].subtitle == "1 day a week · starts tomorrow")
    }

    @Test func inactiveHabitsAreNotRowsButKeepTheirMarks() {
        let paused = noteHabit("Run", created: "2026-11-01", done: days("2026-11-01", "2026-11-05"),
                               deactivated: "2026-11-06", today: Fixture.today)
        let input = NoteInput(today: Fixture.today, habits: [paused])
        #expect(input.rows.isEmpty)
        #expect(input.hasInactiveHabits)
        #expect(input.cell(for: d("2026-11-03"), filter: nil).mark == .fullSeal)
    }
}

@Suite struct TodayLineTests {
    @Test func countsDoneOfScheduled() {
        // Floss done; Read and Meditate open; Pushups isn't scheduled on Saturdays.
        let line = Fixture.month().todayLine
        #expect(line == TodayLine(summary: "Sat, Nov 14 · 1 of 3 done", nothingScheduled: false))
        #expect(!Fixture.month().showsDailyNoteLine)
    }

    @Test func allDoneCountsRestedHabitsAsHandled() {
        let floss = noteHabit("Floss", created: "2026-11-10", done: days("2026-11-10", "2026-11-14"), today: Fixture.today)
        let walk = noteHabit("Walk", created: "2026-11-10", done: days("2026-11-10", "2026-11-13"), rested: [Fixture.today],
                             today: Fixture.today)
        let input = NoteInput(today: Fixture.today, habits: [floss, walk])
        #expect(input.todayLine.summary == "Sat, Nov 14 · All done")
        #expect(input.showsDailyNoteLine)
    }

    @Test func nothingScheduledTodayShowsNextDaysInsteadOfLeaves() {
        let gym = noteHabit("Gym", schedule: Schedule([.monday, .thursday])!, created: "2026-11-01", today: Fixture.today)
        let swim = noteHabit("Swim", schedule: Schedule([.wednesday])!, created: "2026-11-01", today: Fixture.today)
        let input = NoteInput(today: Fixture.today, habits: [gym, swim])
        #expect(input.todayLine == TodayLine(summary: "Sat, Nov 14", nothingScheduled: true))
        #expect(input.rows.map(\.check) == [.next("next: Mon"), .next("next: Wed")])
        #expect(input.rows.allSatisfy { !$0.canToggle })
        #expect(!input.showsDailyNoteLine)
    }

    @Test func noHabitsShowsJustTheDate() {
        let input = NoteInput(today: Fixture.today, habits: [])
        #expect(input.todayLine == TodayLine(summary: "Sat, Nov 14", nothingScheduled: false))
        #expect(!input.showsDailyNoteLine)
        #expect(!input.hasInactiveHabits)
        #expect(input.addHabitState == .allowed)
    }

    @Test func addHabitStateFollowsTheActiveCount() {
        func input(_ count: Int) -> NoteInput {
            NoteInput(today: Fixture.today, habits: (0..<count).map { noteHabit("H\($0)", created: "2026-11-14", today: Fixture.today) })
        }
        #expect(input(2).addHabitState == .allowed)
        #expect(input(3).addHabitState == .allowedWithNudge)
        #expect(input(5).addHabitState == .atLimit)
    }
}

@Suite struct MonthGridTests {
    let input = Fixture.month()

    @Test func headerAndGrid() {
        #expect(input.monthTitle == "November")
        #expect(input.yearTitle == "2026")
        #expect(input.grid.weeks.first?.first == .some(d("2026-11-01")), "Nov 1, 2026 is a Sunday")
    }

    @Test func allHabitsMarks() {
        func mark(_ day: String) -> DayCellMark { input.cell(for: d(day), filter: nil).mark }
        #expect(mark("2026-11-01") == .fullSeal)
        #expect(mark("2026-11-03") == .pencilCircle, "Read's only habit that day, missed")
        #expect(mark("2026-11-04") == .fullSeal)
        #expect(mark("2026-11-11") == .slicedSeal(inked: [false, true, true]), "Read rested; Pushups and Floss done")
        #expect(mark("2026-11-14") == .slicedSeal(inked: [false, true, false]), "Today fills in live")
        #expect(mark("2026-11-15") == .future)
    }

    @Test func filteredMarks() {
        let read = input.habits[0].id
        func mark(_ day: String) -> DayCellMark { input.cell(for: d(day), filter: read).mark }
        #expect(mark("2026-11-02") == .fullSeal)
        #expect(mark("2026-11-03") == .goldSeam)
        #expect(mark("2026-11-08") == .pencilCircle)
        #expect(mark("2026-11-09") == .pencilCircle, "The second miss broke the streak: no seam")
        #expect(mark("2026-11-11") == .restDash)
        #expect(mark("2026-11-14") == .todayPending)
    }

    @Test func tooltipsListScheduledHabitsAndTheNote() {
        #expect(input.cell(for: d("2026-11-03"), filter: nil).tooltip == "Nov 3 — Read: missed (recovered)")
        #expect(input.cell(for: d("2026-11-04"), filter: nil).tooltip
                == "Nov 4 — Read: done · Pushups: done “Read before bed, not after.”")
        #expect(input.cell(for: d("2026-11-11"), filter: nil).tooltip
                == "Nov 11 — Read: rest day · Pushups: done · Floss: done")
        #expect(input.cell(for: d("2026-11-14"), filter: nil).tooltip
                == "Nov 14 — Read: not yet · Floss: done · Meditate: not yet")
        #expect(input.cell(for: d("2026-11-15"), filter: nil).tooltip == nil, "Future days have nothing to tell")
        let pushups = input.habits[1].id
        #expect(input.cell(for: d("2026-11-04"), filter: pushups).tooltip == "Nov 4 — Pushups: done “Read before bed, not after.”")
        #expect(input.cell(for: d("2026-11-03"), filter: pushups).tooltip == nil, "Not one of its days")
    }

    @Test func pastDaysAndTodayOpenTheDayCard() {
        #expect(input.cell(for: d("2026-11-01"), filter: nil).opensDayCard)
        #expect(input.cell(for: Fixture.today, filter: nil).opensDayCard)
        #expect(input.cell(for: Fixture.today, filter: nil).isToday)
        #expect(!input.cell(for: d("2026-11-15"), filter: nil).opensDayCard)
    }

    @Test func voiceOverLabelsSayTheMarkAndDetails() {
        #expect(input.cell(for: d("2026-11-04"), filter: nil).accessibilityLabel
                == "November 4: all done. Read: done · Pushups: done “Read before bed, not after.”")
        #expect(input.cell(for: Fixture.today, filter: nil).accessibilityLabel
                == "November 14, today: 1 of 3 done. Read: not yet · Floss: done · Meditate: not yet")
        #expect(input.cell(for: d("2026-11-20"), filter: nil).accessibilityLabel == "November 20")
    }
}

@Suite struct DayCardTests {
    let input = Fixture.month()

    @Test func todayCardOffersRestExceptOnADangerDay() {
        let card = input.dayCard(for: Fixture.today)
        #expect(card.title == "Sat, Nov 14 · Today")
        #expect(card.access == .editable)
        #expect(card.rows.map(\.name) == ["Read", "Floss", "Meditate"], "Pushups isn't scheduled on Saturdays")
        #expect(card.rows.map(\.status) == ["Not yet", "Done", "Not yet"])
        #expect(card.rows.map(\.restAction) == [nil, nil, .rest], "Read must be done today (never miss twice)")
    }

    @Test func restedHabitOffersUndo() {
        let walk = noteHabit("Walk", created: "2026-11-10", done: days("2026-11-10", "2026-11-13"), rested: [Fixture.today],
                             today: Fixture.today)
        let card = NoteInput(today: Fixture.today, habits: [walk]).dayCard(for: Fixture.today)
        #expect(card.rows.map(\.restAction) == [.undoRest])
        #expect(card.rows.map(\.status) == ["Rest day"])
        #expect(card.rows.map(\.leaf) == [.rested])
    }

    @Test func pastCardsNeverOfferRest() {
        let card = input.dayCard(for: d("2026-11-12"))
        #expect(card.title == "Thu, Nov 12")
        #expect(card.access == .editable, "Two days ago is still editable")
        #expect(card.rows.allSatisfy { $0.restAction == nil })
    }

    @Test func olderDaysAreReadOnlyWithStatuses() {
        let card = input.dayCard(for: d("2026-11-11"))
        #expect(card.access == .readOnly)
        #expect(card.rows.map(\.status) == ["Rest day", "Done", "Done"])
        #expect(input.dayCard(for: d("2026-11-03")).rows.map(\.status) == ["Missed, then recovered"])
        #expect(input.dayCard(for: d("2026-11-04")).note == "Read before bed, not after.")
    }

    @Test func inactiveHabitsAreReadOnlyInTheCard() {
        let paused = noteHabit("Run", created: "2026-11-10", done: [d("2026-11-10")], deactivated: "2026-11-14",
                               today: Fixture.today)
        let card = NoteInput(today: Fixture.today, habits: [paused]).dayCard(for: d("2026-11-12"))
        #expect(card.rows.map(\.status) == ["Missed"])
        #expect(card.rows.map(\.isChangeable) == [false])
    }

    @Test func aDayBeforeAnyHabitHasNoRows() {
        #expect(input.dayCard(for: d("2026-10-01")).rows.isEmpty)
    }
}

@Suite struct HabitDraftTests {
    @Test func amountHabitNeedsNameTargetAndUnit() {
        var draft = HabitDraft()
        #expect(draft.request == nil)
        draft.name = "  Read "
        #expect(draft.request == nil, "Track an amount is the default and needs a target")
        draft.target = "10"
        #expect(draft.request == nil, "…and a unit")
        draft.unit = "pages"
        #expect(draft.request == HabitDraft.Request(name: "Read", identity: nil, kind: .amount(unit: "pages"), target: 10,
                                                    schedule: .everyDay))
        draft.target = "0"
        #expect(draft.request == nil, "Targets are at least 1")
    }

    @Test func yesNoHabitNeedsOnlyAName() {
        var draft = HabitDraft()
        draft.name = "Floss"
        draft.kind = .yesNo
        draft.target = "10" // ignored
        draft.identity = " someone who flosses "
        #expect(draft.request == HabitDraft.Request(name: "Floss", identity: "someone who flosses", kind: .yesNo, target: nil,
                                                    schedule: .everyDay))
    }

    @Test func specificDaysNeedAtLeastOneDay() {
        var draft = HabitDraft()
        draft.name = "Swim"
        draft.kind = .yesNo
        draft.scheduleChoice = .specificDays
        #expect(draft.request == nil)
        draft.weekdays = [WeekdaySet(.monday), WeekdaySet(.friday)]
        #expect(draft.request?.schedule == Schedule([.monday, .friday]))
    }

    @Test func previewShowsWhatIsFilledIn() {
        var draft = HabitDraft()
        #expect(draft.previewName == "Your habit")
        #expect(draft.previewDetails == "every day")
        draft.name = "Read"
        draft.target = "10"
        draft.unit = "pages"
        draft.identity = "a reader"
        draft.scheduleChoice = .specificDays
        draft.weekdays = [WeekdaySet(.monday), WeekdaySet(.wednesday)]
        #expect(draft.previewName == "Read")
        #expect(draft.previewDetails == "10 pages · Mon, Wed · I’m a reader")
        draft.kind = .yesNo
        #expect(draft.previewDetails == "Mon, Wed · I’m a reader", "Just do it has no target")
    }

    @Test func targetFieldKeepsOnlyDigits() {
        #expect(HabitDraft.filteredTarget("1a2.5") == "125")
        #expect(HabitDraft.filteredTarget("1234567") == "12345")
        #expect(HabitDraft.filteredTarget("٣") == "", "ASCII digits only")
    }
}
