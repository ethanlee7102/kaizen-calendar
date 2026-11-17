import Core
import Foundation
import Testing
@testable import UI

/// What the notebook shows (Phase 5), checked on `Fixture.month()` (today Sat Nov 14, 2026):
/// Read (10 pages, daily, from Oct 25) has a recovered miss Nov 3, a break Nov 8–9, a rest
/// Nov 11 and a miss yesterday; Pushups is Mon/Wed/Fri from Nov 1; Floss is daily from Nov 5;
/// Meditate starts today. Nov 4 has a note.
@Suite struct NotebookTabTests {
    @Test func tabsInOrderAndArrowsStopAtTheEnds() {
        #expect(NotebookTab.allCases.map(\.title) == ["Calendar", "Habits", "Reports", "Stamp book", "The Science", "Settings"])
        #expect(NotebookTab.calendar.moved(by: 1) == .habits)
        #expect(NotebookTab.calendar.moved(by: -1) == .calendar)
        #expect(NotebookTab.settings.moved(by: 1) == .settings)
        #expect(NotebookTab.stampBook.moved(by: -1) == .reports)
    }

    @Test func stampBookMarkerWhileAnUnlockIsUnseen() {
        var input = NotebookInput(note: Fixture.month())
        #expect(input.newMarkers.isEmpty)
        input.unlocks = [UnlockInfo(unlock: .darkMode, isNew: true)]
        #expect(input.newMarkers == [.stampBook])
        input.unlocks = [UnlockInfo(unlock: .darkMode, isNew: false)]
        #expect(input.newMarkers.isEmpty)
    }

    @Test func navigationRemembersTheLastTabAndOpensAtTodaysMonth() throws {
        let suite = "notebook.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let navigation = NotebookNavigation(defaults: defaults)
        #expect(navigation.tab == .calendar)
        navigation.show(.settings)
        #expect(NotebookNavigation(defaults: defaults).tab == .settings)

        navigation.calendarMonth = d("2026-09-01")
        navigation.calendarYear = 2025
        navigation.calendarFilter = HabitID()
        navigation.opened()
        #expect(navigation.calendarMonth == nil)
        #expect(navigation.calendarYear == nil)
        #expect(navigation.calendarFilter != nil) // the filter stays

        let habit = HabitID()
        navigation.showHabit(habit)
        #expect(navigation.tab == .habits)
        #expect(navigation.selectedHabit == habit)

        // In-memory modes remember nothing.
        let memory = NotebookNavigation(defaults: nil)
        memory.show(.habits)
        #expect(NotebookNavigation(defaults: nil).tab == .calendar)
    }
}

@Suite struct CalendarTabTests {
    let input = Fixture.month()

    @Test func arrowsReachFromTheFirstHabitsMonthToToday() {
        #expect(input.firstCalendarMonth == d("2026-10-01"))
        #expect(input.lastCalendarMonth == d("2026-11-01"))
        #expect(input.clampedCalendarMonth(d("2026-03-09")) == d("2026-10-01"))
        #expect(input.clampedCalendarMonth(d("2027-01-15")) == d("2026-11-01"))
        #expect(input.calendarYears == 2026...2026)
        // No habits: today's month only.
        let empty = NoteInput(today: Fixture.today, habits: [])
        #expect(empty.firstCalendarMonth == d("2026-11-01"))
    }

    @Test func monthArithmeticCrossesYears() {
        #expect(CalendarMath.month(d("2026-12-31"), adding: 1) == d("2027-01-01"))
        #expect(CalendarMath.month(d("2026-01-15"), adding: -1) == d("2025-12-01"))
        #expect(CalendarMath.month(d("2026-11-14"), adding: -13) == d("2025-10-01"))
        #expect(CalendarMath.month(d("2026-11-14"), adding: 0) == d("2026-11-01"))
    }

    @Test func noteTickOnDaysWithANote() {
        #expect(input.calendarCell(for: d("2026-11-04"), filter: nil).hasNote)
        #expect(!input.calendarCell(for: d("2026-11-05"), filter: nil).hasNote)
        // Filtered too: the note belongs to the day.
        #expect(input.calendarCell(for: d("2026-11-04"), filter: input.habits[0].id).hasNote)
    }

    @Test func heatSquaresFollowTheMarks() {
        let read = input.habits[0].id
        #expect(input.heatSquare(for: d("2026-11-03"), filter: nil) == .missed)        // only Read counted, missed
        #expect(input.heatSquare(for: d("2026-11-03"), filter: read) == .recovered)     // gold in the filtered view
        #expect(input.heatSquare(for: d("2026-11-11"), filter: nil) == .someDone)       // a rest blocks the full seal
        #expect(input.heatSquare(for: d("2026-11-11"), filter: read) == .rest)
        #expect(input.heatSquare(for: d("2026-11-10"), filter: nil) == .allDone)
        #expect(input.heatSquare(for: d("2026-11-14"), filter: nil) == .someDone)       // today, Floss done
        #expect(input.heatSquare(for: d("2026-11-14"), filter: read) == .nothing)       // today, not decided yet
        #expect(input.heatSquare(for: d("2026-11-15"), filter: nil) == .future)
        #expect(input.heatSquare(for: d("2026-10-24"), filter: nil) == .nothing)        // before any habit
        #expect(HeatSquare(.slicedSeal(inked: [false, false])) == .nothing)
        #expect(HeatSquare.legend(filtered: false) == [.allDone, .someDone, .missed, .rest])
        #expect(HeatSquare.legend(filtered: true) == [.allDone, .missed, .recovered, .rest])
    }

    @Test func heatTooltipSaysTheDateAndWhatHappened() {
        #expect(input.heatTooltip(for: d("2026-11-03"), filter: input.habits[0].id) == "Nov 3 — Read: missed (recovered)")
        #expect(input.heatTooltip(for: d("2026-10-20"), filter: nil) == "Oct 20")
        #expect(input.heatTooltip(for: d("2026-11-20"), filter: nil) == "Nov 20")
    }

    @Test func monthSummaryOnlyOnceMeaningful() {
        let today = Fixture.today
        let floss = noteHabit("Floss", created: "2026-11-01", done: days("2026-11-01", "2026-11-13", skipping: ["2026-11-05"]),
                              today: today)
        let one = NoteInput(today: today, habits: [floss])
        // Nov 1–13 decided (today pending): 12 of 13 done, Nov 5 recovered.
        #expect(one.monthSummary(for: d("2026-11-01"), filter: nil) == "November · 92% consistency · 1 miss recovered")
        #expect(one.monthSummary(for: d("2026-11-01"), filter: floss.id) == "November · 92% consistency · 1 miss recovered")

        let perfect = noteHabit("Walk", created: "2026-11-01", done: days("2026-11-01", "2026-11-13"), today: today)
        #expect(NoteInput(today: today, habits: [perfect]).monthSummary(for: d("2026-11-01"), filter: nil)
                == "November · 100% consistency")

        // Fewer than 7 scheduled days: nothing to say yet.
        let new = noteHabit("Run", created: "2026-11-10", done: days("2026-11-10", "2026-11-13"), today: today)
        #expect(NoteInput(today: today, habits: [new]).monthSummary(for: d("2026-11-01"), filter: nil) == nil)
    }

    @Test func inactiveHabitsNewestFirst() {
        let today = Fixture.today
        let a = noteHabit("Stretch", created: "2026-10-01", deactivated: "2026-11-02", today: today)
        let b = noteHabit("Journal", created: "2026-10-01", deactivated: "2026-11-09", today: today)
        let c = noteHabit("Swim", created: "2026-10-01", deactivated: "2026-11-02", today: today)
        let active = noteHabit("Read", created: "2026-10-01", today: today)
        let input = NoteInput(today: today, habits: [a, active, b, c])
        #expect(input.inactiveHabits.map(\.name) == ["Journal", "Stretch", "Swim"]) // same day: list order
        #expect(input.chipHabits.map(\.name) == ["Read"])
    }
}

@Suite struct HabitsTabTests {
    let input = Fixture.month()

    @Test func listSectionsAndLabels() {
        #expect(input.activeTitle == "Active · 4 of 5")
        #expect(input.activeItems.map(\.name) == ["Read", "Pushups", "Floss", "Meditate"])
        #expect(input.activeItems.map(\.dayText) == ["Day 15", "Day 6", "Day 10", "Day 0"])
        #expect(input.activeItems.allSatisfy { $0.statusText == nil })

        var graduated = HabitHistory.new(kind: .yesNo, schedule: .everyDay, on: d("2026-08-01"))
        graduated.deactivate(on: d("2026-11-01"), reason: .graduated)
        let stretch = NoteHabit(name: "Stretch", identity: nil, evaluation: HabitEvaluation(history: graduated, today: Fixture.today))
        let journal = noteHabit("Journal", created: "2026-10-01", deactivated: "2026-11-03", today: Fixture.today)
        let withInactive = NoteInput(today: Fixture.today, habits: input.habits + [stretch, journal])
        #expect(withInactive.inactiveItems.map(\.name) == ["Journal", "Stretch"])
        #expect(withInactive.inactiveItems.map(\.statusText) == ["Paused", "Graduated ✓66"])
    }

    @Test func selectionKeepsTheCurrentHabitElseTheFirst() {
        let pushups = input.habits[1].id
        #expect(input.habitSelection(keeping: pushups) == pushups)
        #expect(input.habitSelection(keeping: HabitID()) == input.habits[0].id) // gone: the first active
        #expect(input.habitSelection(keeping: nil) == input.habits[0].id)
        let paused = noteHabit("Run", created: "2026-11-01", deactivated: "2026-11-06", today: Fixture.today)
        #expect(NoteInput(today: Fixture.today, habits: [paused]).habitSelection(keeping: nil) == paused.id)
        #expect(NoteInput(today: Fixture.today, habits: []).habitSelection(keeping: nil) == nil)
    }

    @Test func moveUpDownAndDragReorderTheActiveList() {
        let ids = input.habits.map(\.id)
        #expect(input.activeOrder(moving: ids[1], by: -1) == [ids[1], ids[0], ids[2], ids[3]])
        #expect(input.activeOrder(moving: ids[1], by: 1) == [ids[0], ids[2], ids[1], ids[3]])
        #expect(input.activeOrder(moving: ids[0], by: -1) == nil)
        #expect(input.activeOrder(moving: ids[3], by: 1) == nil)
        // Dragged onto a row: it takes that row's place.
        #expect(input.activeOrder(moving: ids[0], onto: ids[2]) == [ids[1], ids[2], ids[0], ids[3]])
        #expect(input.activeOrder(moving: ids[3], onto: ids[0]) == [ids[3], ids[0], ids[1], ids[2]])
        #expect(input.activeOrder(moving: ids[1], onto: ids[1]) == nil)
        #expect(input.activeOrder(moving: HabitID(), onto: ids[1]) == nil)
    }

    @Test func pageForAnAmountHabit() throws {
        let page = try #require(input.habitPage(input.habits[0].id))
        #expect(page.name == "Read")
        #expect(page.identityLine == "I’m a reader.")
        #expect(page.detailLine == "10 pages · every day")
        #expect(page.isActive)
        #expect(page.inactiveLine == nil)
        #expect(page.primaryChange == .target(current: 10, unit: "pages"))
        #expect(!page.canMoveUp)
        #expect(page.canMoveDown)
        #expect(page.journey.count == 15)
        #expect(page.journeyLine == "51 more done days until your day-66 check-in.")
        #expect(page.streak == 2)
        #expect(page.streakUnit == "days")
        #expect(page.savesLine == "1 never-miss-twice save")
        // Oct 16–Nov 14: 19 decided days (rest excluded, today pending), 15 done.
        #expect(page.consistency == "79%")
        #expect(page.consistencyCaption == "last 30 days")
        #expect(page.monthTitle == "November")
        #expect(page.monthCells[d("2026-11-03")]?.mark == .goldSeam)
        #expect(page.history == [HistoryStep(value: "10 pages", when: "Started Oct 25 · now", isCurrent: true)])
    }

    @Test func weeklyTrendForThreeFullWeeks() throws {
        let page = try #require(input.habitPage(input.habits[0].id))
        let trend = try #require(page.trend)
        #expect(trend.map(\.weekStart) == [d("2026-10-25"), d("2026-11-01"), d("2026-11-08")])
        #expect(trend.map(\.percent) == [100, 86, 40])
        #expect(trend[1].recoveredMisses == [d("2026-11-03")])
        #expect(trend[2].breakingMisses == [d("2026-11-08"), d("2026-11-09"), d("2026-11-13")])
        #expect(trend.map(\.label) == ["Oct 25", "Nov 1", "Nov 8"])
        #expect(trend[0].details == "Week of Oct 25 · 100% · no misses")
        #expect(trend[1].details == "Week of Nov 1 · 86% · recovered Nov 3")
        #expect(trend[2].details == "Week of Nov 8 · 40% · missed Nov 8, Nov 9, Nov 13")
        // Hovering: the week's details; an index from a longer span shows the legend (Phase 5 review).
        #expect(TrendPoint.caption(hovered: 1, in: trend) == trend[1].details)
        #expect(TrendPoint.caption(hovered: nil, in: trend) == TrendPoint.legend)
        #expect(TrendPoint.caption(hovered: 15, in: trend) == TrendPoint.legend)
        // A habit under 2 full weeks old has no graph yet.
        #expect(try #require(input.habitPage(input.habits[2].id)).trend == nil)
    }

    @Test func yesNoHabitsShowTheirScheduleAndScheduleHistory() throws {
        let floss = try #require(input.habitPage(input.habits[2].id))
        #expect(floss.detailLine == "every day")
        #expect(floss.primaryChange == .schedule)
        #expect(floss.history == [HistoryStep(value: "every day", when: "Started Nov 5 · now", isCurrent: true)])

        var history = HabitHistory.new(kind: .yesNo, schedule: Schedule([.monday, .wednesday, .friday])!, on: d("2025-12-29"))
        history.changeSchedule(to: Schedule([.monday, .tuesday, .wednesday, .friday])!, on: d("2026-10-14"), source: .suggested)
        history.changeSchedule(to: .everyDay, on: d("2026-11-02"), source: .manual)
        let habit = NoteHabit(name: "Gym", identity: nil, evaluation: HabitEvaluation(history: history, today: Fixture.today))
        let page = try #require(NoteInput(today: Fixture.today, habits: [habit]).habitPage(habit.id))
        #expect(page.history == [
            HistoryStep(value: "3 days a week", when: "Started Dec 29, 2025", isCurrent: false),
            HistoryStep(value: "4 days a week", when: "Oct 14 · suggested", isCurrent: false),
            HistoryStep(value: "every day", when: "Nov 2 · changed by you · now", isCurrent: true),
        ])

        var weekdays = HabitHistory.new(kind: .yesNo, schedule: Schedule([.tuesday, .thursday])!, on: d("2026-11-01"))
        weekdays.setDone(true, on: d("2026-11-03"))
        let gym = NoteHabit(name: "Gym", identity: nil, evaluation: HabitEvaluation(history: weekdays, today: Fixture.today))
        #expect(NoteInput(today: Fixture.today, habits: [gym]).habitPage(gym.id)?.detailLine == "2 days a week")
    }

    @Test func amountHistoryNamesEachChangesReason() throws {
        var history = HabitHistory.new(kind: .amount(unit: "pages"), target: 5, schedule: .everyDay, on: d("2026-09-29"))
        history.changeTarget(to: 8, on: d("2026-10-14"), source: .suggested)
        history.changeTarget(to: 10, on: d("2026-11-02"), source: .manual)
        let habit = NoteHabit(name: "Read", identity: nil, evaluation: HabitEvaluation(history: history, today: Fixture.today))
        let page = try #require(NoteInput(today: Fixture.today, habits: [habit]).habitPage(habit.id))
        #expect(page.history.map(\.value) == ["5 pages", "8 pages", "10 pages"])
        #expect(page.history.map(\.when) == ["Started Sep 29", "Oct 14 · suggested", "Nov 2 · changed by you · now"])
        #expect(page.history.map(\.isCurrent) == [false, false, true])
    }

    @Test func inactivePageIsFrozenAtItsLastDay() throws {
        let run = noteHabit("Run", created: "2026-10-20", done: days("2026-10-20", "2026-11-05"), deactivated: "2026-11-06",
                            today: Fixture.today)
        let page = try #require(NoteInput(today: Fixture.today, habits: [run]).habitPage(run.id))
        #expect(!page.isActive)
        #expect(page.inactiveLine == "Paused since Nov 6")
        #expect(!page.canMoveUp && !page.canMoveDown)
        #expect(page.streak == 17)
        // As of Nov 6, not today: the last 30 days were all done.
        #expect(page.consistency == "100%")
        #expect(page.history == [HistoryStep(value: "every day", when: "Started Oct 20", isCurrent: true)])
        // Only one full week (Oct 25–31) by Nov 6, so no graph yet.
        #expect(page.trend == nil)

        var graduated = HabitHistory.new(kind: .yesNo, schedule: .everyDay, on: d("2026-08-01"))
        graduated.deactivate(on: d("2026-11-01"), reason: .graduated)
        let stretch = NoteHabit(name: "Stretch", identity: nil, evaluation: HabitEvaluation(history: graduated, today: Fixture.today))
        #expect(NoteInput(today: Fixture.today, habits: [stretch]).habitPage(stretch.id)?.inactiveLine
                == "Graduated ✓66 on Nov 1")
    }

    @Test func consistencyWithNothingScheduledYet() throws {
        let page = try #require(input.habitPage(input.habits[3].id)) // Meditate starts today
        #expect(page.consistency == "–")
        #expect(page.consistencyCaption == "nothing scheduled yet")
        #expect(page.streakUnit == "days")
        #expect(page.savesLine == nil)
        #expect(page.canMoveUp && !page.canMoveDown)
    }

    @Test func journeyLines() {
        func journey(_ n: Int) -> Journey { Journey(doneDays: (0..<n).map { d("2025-01-01").adding(days: $0) }) }
        #expect(NoteInput.journeyLine(journey(0)) == "66 more done days until your day-66 check-in.")
        #expect(NoteInput.journeyLine(journey(65)) == "1 more done day until your day-66 check-in.")
        #expect(NoteInput.journeyLine(journey(66)) == "34 more done days to day 100.")
        #expect(NoteInput.journeyLine(journey(253)) == "1 more done day to day 254.")
        #expect(NoteInput.journeyLine(journey(365)) == "Past every milestone. Keep going as long as you like.")
    }

    @Test func deleteConfirmationNamesTheHistory() throws {
        let read = try #require(input.deleteConfirmation(input.habits[0].id))
        #expect(read.title == "Delete Read and all 15 days of history?")
        #expect(read.message == "To keep the history, move it to inactive instead.")
        #expect(read.offersMoveToInactive)
        #expect(input.deleteConfirmation(input.habits[3].id)?.title == "Delete Meditate?")

        let one = noteHabit("Run", created: "2026-11-01", done: [d("2026-11-01")], deactivated: "2026-11-06", today: Fixture.today)
        let inactive = try #require(NoteInput(today: Fixture.today, habits: [one]).deleteConfirmation(one.id))
        #expect(inactive.title == "Delete Run and its 1 day of history?")
        #expect(inactive.message == "To keep the history, leave it inactive instead.")
        #expect(!inactive.offersMoveToInactive)
        #expect(input.deleteConfirmation(HabitID()) == nil)
    }
}

@Suite struct StampBookAndSettingsTests {
    @Test func unlockNoticeWords() {
        let notice = UnlockNotice(unlock: .darkMode)
        #expect(notice.title == "You found something: Dark mode.")
        #expect(notice.message == "Charcoal paper with light ink. Choose it in the Stamp book.")
    }

    @Test func settingsWords() {
        #expect(SettingsValues.dayEndHours.map(SettingsValues.dayEndTitle) == ["Midnight", "1am", "2am", "3am", "4am"])
        #expect(SettingsValues.time(hour: 18, minute: 0) == "6pm")
        #expect(SettingsValues.time(hour: 0, minute: 0) == "12am")
        #expect(SettingsValues.time(hour: 12, minute: 0) == "12pm")
        #expect(SettingsValues.time(hour: 18, minute: 30) == "6:30pm")
        #expect(SettingsValues.time(hour: 9, minute: 5) == "9:05am")
        var settings = SettingsValues()
        #expect(settings.reportTime == "6pm")
        #expect(settings.dayEndCaption == "Check-offs before this time count for the previous day.")
        settings.dayEndStartsTomorrow = true
        #expect(settings.dayEndCaption
                == "Starts tomorrow, so today stays as it is. Check-offs before this time count for the previous day.")
        #expect(settings.reminderTime == "8pm")
        #expect(settings.monthlyNote == "The monthly report replaces it on the last Sunday of the month.")
        settings.reportWeekday = .friday
        #expect(settings.monthlyNote == "The monthly report replaces it on the last Friday of the month.")
        #expect(SettingsValues.Appearance.allCases.map(\.title) == ["Light", "Dark", "Match system"])
        #expect(SettingsValues.ReduceMotion.allCases.map(\.title) == ["Match system", "On", "Off"])
    }

    @Test func datesOutsideThisYearSayTheYear() {
        #expect(DayText.date(d("2026-03-04"), today: Fixture.today) == "Mar 4")
        #expect(DayText.date(d("2025-03-04"), today: Fixture.today) == "Mar 4, 2025")
    }
}

@Suite struct EditDraftTests {
    let today = Fixture.today

    @Test func editFormSavesOnlyRealChanges() throws {
        let read = Fixture.month().habits[0]
        var draft = HabitEditDraft(habit: read, today: today)
        #expect(draft.name == "Read")
        #expect(draft.identity == "a reader")
        #expect(draft.unit == "pages")
        #expect(draft.isAmount)
        #expect(draft.scheduleChoice == .everyDay)
        #expect(draft.changes == nil) // nothing changed yet

        #expect(draft.unitNote == "Measured in pages. To measure something else, start a new habit.")
        draft.name = "  Read more "
        #expect(draft.changes == HabitEditDraft.Changes(name: "Read more", identity: "a reader", schedule: nil))
        #expect(draft.scheduleNote == nil)

        draft.scheduleChoice = .specificDays
        #expect(draft.changes == nil) // no day picked
        draft.weekdays = WeekdaySet([.monday, .friday])
        #expect(draft.changes?.schedule == Schedule([.monday, .friday]))
        #expect(draft.scheduleNote == "The new schedule starts today. Past days keep theirs.")

        draft.identity = " "
        #expect(draft.changes?.identity == nil)
        draft.name = ""
        #expect(draft.changes == nil)
    }

    @Test func editFormForYesNoHabitsHasNoUnit() {
        let pushupsLike = noteHabit("Gym", schedule: Schedule([.tuesday, .thursday])!, created: "2026-11-01", today: today)
        var draft = HabitEditDraft(habit: pushupsLike, today: today)
        #expect(!draft.isAmount)
        #expect(draft.unitNote == nil)
        #expect(draft.scheduleChoice == .specificDays)
        #expect(draft.weekdays == WeekdaySet([.tuesday, .thursday]))
        draft.scheduleChoice = .everyDay
        #expect(draft.changes == HabitEditDraft.Changes(name: "Gym", identity: nil, schedule: .everyDay))
    }

    @Test func targetAndScheduleDrafts() {
        var target = TargetDraft(current: 10, unit: "pages")
        #expect(target.text == "10")
        #expect(target.newAmount == nil)
        target.text = "0"
        #expect(target.hint == "At least 1.")
        #expect(target.newAmount == nil)
        target.text = "12"
        #expect(target.newAmount == 12)
        #expect(target.hint == nil)

        var schedule = ScheduleDraft(current: .everyDay)
        #expect(schedule.newSchedule == nil)
        schedule.choice = .specificDays
        #expect(schedule.newSchedule == nil)
        schedule.weekdays = WeekdaySet(.saturday)
        #expect(schedule.newSchedule == Schedule([.saturday]))
    }
}
