import Core
import Foundation
@testable import Persistence
import SQLiteData
import Testing

@Suite struct AddAndEditHabitTests {
    @Test func addsAHabitThatStartsToday() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "  Read ", identity: " a reader ", kind: .amount(unit: " pages "), target: 10,
                                   schedule: .everyDay, today: d("2026-11-13"))
        let habit = try #require(try repo.appData().habit(id))
        #expect(habit.name == "Read")
        #expect(habit.identity == "a reader")
        let history = try habit.history.get()
        #expect(history == HabitHistory.new(id: id, kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, on: d("2026-11-13")))
    }

    @Test func rejectsInvalidInput() throws {
        let repo = try makeRepository()
        let today = d("2026-11-13")
        #expect(throws: Repository.Failure.emptyName) { try repo.addHabit(name: "  ", kind: .yesNo, schedule: .everyDay, today: today) }
        #expect(throws: Repository.Failure.missingUnit) {
            try repo.addHabit(name: "Read", kind: .amount(unit: " "), target: 5, schedule: .everyDay, today: today)
        }
        #expect(throws: Repository.Failure.invalidTarget) {
            try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 0, schedule: .everyDay, today: today)
        }
        #expect(throws: Repository.Failure.invalidTarget) {
            try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), schedule: .everyDay, today: today)
        }
        #expect(try repo.appData().habits.isEmpty)
    }

    @Test func noEmptyIdentityStored() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Walk", identity: "   ", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13"))
        #expect(try repo.appData().habit(id)?.identity == nil)
    }

    @Test func atMostFiveActiveHabits() throws {
        let repo = try makeRepository()
        let today = d("2026-11-13")
        for n in 1...5 { try repo.addHabit(name: "H\(n)", kind: .yesNo, schedule: .everyDay, today: today) }
        #expect(throws: Repository.Failure.atHabitLimit) {
            try repo.addHabit(name: "H6", kind: .yesNo, schedule: .everyDay, today: today)
        }
        // Inactive habits don't count.
        try repo.deactivate(try repo.appData().habits[0].id, today: today)
        try repo.addHabit(name: "H6", kind: .yesNo, schedule: .everyDay, today: today)
        #expect(try repo.appData().habits.count == 6)
    }

    @Test func newHabitsGoToTheEndAndReorderSetsTheListOrder() throws {
        let repo = try makeRepository()
        let today = d("2026-11-13")
        let a = try repo.addHabit(name: "A", kind: .yesNo, schedule: .everyDay, today: today)
        let b = try repo.addHabit(name: "B", kind: .yesNo, schedule: .everyDay, today: today)
        let c = try repo.addHabit(name: "C", kind: .yesNo, schedule: .everyDay, today: today)
        #expect(try repo.appData().habits.map(\.id) == [a, b, c])
        try repo.reorder([c, a, b])
        #expect(try repo.appData().habits.map(\.id) == [c, a, b])
        // Unlisted habits keep their order after the listed ones.
        try repo.reorder([b])
        #expect(try repo.appData().habits.map(\.id) == [b, c, a])
    }

    @Test func detailsChange() throws {
        let repo = try makeRepository()
        let today = d("2026-11-13")
        let id = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: today)
        try repo.updateDetails(of: id, name: "Read books", identity: "a reader", unit: "chapters", today: today)
        let habit = try #require(try repo.appData().habit(id))
        #expect(habit.name == "Read books")
        #expect(habit.identity == "a reader")
        #expect(try habit.history.get().kind == .amount(unit: "chapters"))
        #expect(throws: Repository.Failure.emptyName) { try repo.updateDetails(of: id, name: "", identity: nil, today: today) }
    }

    @Test func targetAndScheduleChangesUseCoresSameDayTypoRule() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: d("2026-11-01"))
        // Same day as creation: a typo fix keeps it the initial target.
        try repo.changeTarget(of: id, to: 12, today: d("2026-11-01"))
        #expect(try repo.history(id).targetChanges == [TargetChange(day: d("2026-11-01"), amount: 12, source: .initial)])
        // Later: a history entry, and a same-day fix replaces it.
        try repo.changeTarget(of: id, to: 15, today: d("2026-11-10"), source: .suggested)
        try repo.changeTarget(of: id, to: 14, today: d("2026-11-10"))
        #expect(try repo.history(id).targetChanges.map(\.amount) == [12, 14])
        // Changing back the same day removes the entry entirely.
        try repo.changeTarget(of: id, to: 12, today: d("2026-11-10"))
        #expect(try repo.history(id).targetChanges.map(\.amount) == [12])

        let weekdays = Schedule([.monday, .wednesday, .friday])!
        try repo.changeSchedule(of: id, to: weekdays, today: d("2026-11-11"))
        #expect(try repo.history(id).schedule(on: d("2026-11-11")) == weekdays)
        #expect(try repo.history(id).schedule(on: d("2026-11-10")) == .everyDay)
    }

    @Test func yesNoHabitsHaveNoTarget() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        #expect(throws: Repository.Failure.notAnAmountHabit) { try repo.changeTarget(of: id, to: 3, today: d("2026-11-02")) }
    }
}

@Suite struct CheckOffAndRestTests {
    let today = d("2026-11-13")

    func dailyHabit(_ repo: Repository, created: String = "2026-11-01") throws -> HabitID {
        try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d(created))
    }

    @Test func checkAndUncheck() throws {
        let repo = try makeRepository()
        let id = try dailyHabit(repo)
        try repo.setDone(true, habit: id, on: today, today: today)
        #expect(try repo.history(id).completions == [today])
        try repo.setDone(false, habit: id, on: today, today: today)
        #expect(try repo.history(id).completions.isEmpty)
        #expect(try repo.database.read { try HabitDayRecord.fetchCount($0) } == 0)
    }

    @Test func editWindowIsTodayAndTwoDaysBefore() throws {
        let repo = try makeRepository()
        let id = try dailyHabit(repo)
        try repo.setDone(true, habit: id, on: d("2026-11-11"), today: today)
        #expect(throws: Repository.Failure.olderDayNeedsConfirmation) {
            try repo.setDone(true, habit: id, on: d("2026-11-10"), today: today)
        }
        try repo.setDone(true, habit: id, on: d("2026-11-10"), today: today, changeAnyway: true)
        #expect(throws: Repository.Failure.futureDay) {
            try repo.setDone(true, habit: id, on: d("2026-11-14"), today: today, changeAnyway: true)
        }
        #expect(try repo.history(id).completions == [d("2026-11-10"), d("2026-11-11")])
    }

    @Test func onlyOnDaysTheHabitCounts() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Gym", kind: .yesNo, schedule: Schedule([.monday])!, today: d("2026-11-01"))
        // Nov 13 2026 is a Friday.
        #expect(throws: Repository.Failure.dayDoesNotCount) { try repo.setDone(true, habit: id, on: today, today: today) }
        // Before the habit existed.
        #expect(throws: Repository.Failure.dayDoesNotCount) {
            try repo.setDone(true, habit: id, on: d("2026-10-26"), today: today, changeAnyway: true)
        }
    }

    @Test func doneClearsARest() throws {
        let repo = try makeRepository()
        let id = try dailyHabit(repo)
        try repo.setDone(true, habit: id, on: d("2026-11-12"), today: today)
        try repo.setRested(true, habit: id, today: today)
        #expect(try repo.history(id).rests == [today])
        try repo.setDone(true, habit: id, on: today, today: today)
        #expect(try repo.history(id).rests.isEmpty)
        #expect(try repo.history(id).completions.contains(today))
        let rows = try repo.database.read { try HabitDayRecord.all.fetchAll($0) }
        #expect(rows.map(\.state).sorted() == ["done", "done"])
    }

    @Test func restOnlyWhenEditRulesAllowIt() throws {
        let repo = try makeRepository()
        let id = try dailyHabit(repo, created: "2026-11-11")
        try repo.setDone(true, habit: id, on: d("2026-11-11"), today: today)
        // Nov 12 missed once: today is a danger day, so no rest.
        #expect(throws: Repository.Failure.cannotRest) { try repo.setRested(true, habit: id, today: today) }
        try repo.setDone(true, habit: id, on: d("2026-11-12"), today: today)
        try repo.setRested(true, habit: id, today: today)
        try repo.setRested(false, habit: id, today: today)
        #expect(try repo.history(id).rests.isEmpty)
        // Not once it's done.
        try repo.setDone(true, habit: id, on: today, today: today)
        #expect(throws: Repository.Failure.cannotRest) { try repo.setRested(true, habit: id, today: today) }
    }

    @Test func notesFollowTheEditWindowAndBlankRemovesThem() throws {
        let repo = try makeRepository()
        try repo.setNote("Read before bed", on: today, today: today)
        try repo.setNote("Earlier", on: d("2026-11-11"), today: today)
        #expect(throws: Repository.Failure.olderDayNeedsConfirmation) { try repo.setNote("x", on: d("2026-11-10"), today: today) }
        #expect(throws: Repository.Failure.futureDay) { try repo.setNote("x", on: d("2026-11-14"), today: today) }
        try repo.setNote("Edited", on: today, today: today)
        #expect(try repo.appData().notes == [today: "Edited", d("2026-11-11"): "Earlier"])
        try repo.setNote("  \n", on: today, today: today)
        #expect(try repo.appData().notes == [d("2026-11-11"): "Earlier"])
    }
}

@Suite struct InactiveTests {
    @Test func inactiveHabitsAreReadOnly() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: d("2026-11-01"))
        try repo.deactivate(id, today: d("2026-11-10"))
        let today = d("2026-11-11")
        #expect(throws: Repository.Failure.habitInactive) { try repo.setDone(true, habit: id, on: today, today: today) }
        #expect(throws: Repository.Failure.habitInactive) { try repo.changeTarget(of: id, to: 12, today: today) }
        #expect(throws: Repository.Failure.habitInactive) { try repo.changeSchedule(of: id, to: Schedule([.monday])!, today: today) }
        #expect(throws: Repository.Failure.habitInactive) { try repo.updateDetails(of: id, name: "X", identity: nil, today: today) }
    }

    @Test func reactivatingContinuesAndGoesToTheEnd() throws {
        let repo = try makeRepository()
        let read = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        let walk = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        try repo.setDone(true, habit: read, on: d("2026-11-03"), today: d("2026-11-03"))
        try repo.deactivate(read, today: d("2026-11-04"), reason: .graduated)
        try repo.reactivate(read, today: d("2026-11-09"))

        let history = try repo.history(read)
        #expect(history.activePeriods == [
            ActivePeriod(start: d("2026-11-01"), end: d("2026-11-04"), endReason: .graduated),
            ActivePeriod(start: d("2026-11-09")),
        ])
        #expect(try repo.appData().habits.map(\.id) == [walk, read])
    }

    @Test func sameDayReactivationUndoesIt() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        try repo.deactivate(id, today: d("2026-11-05"))
        try repo.reactivate(id, today: d("2026-11-05"))
        #expect(try repo.history(id).activePeriods == [ActivePeriod(start: d("2026-11-01"))])
        #expect(try repo.database.read { try ActivePeriodRecord.fetchCount($0) } == 1)
    }

    @Test func reactivateNeedsRoom() throws {
        let repo = try makeRepository()
        let today = d("2026-11-13")
        let first = try repo.addHabit(name: "H0", kind: .yesNo, schedule: .everyDay, today: today)
        try repo.deactivate(first, today: today)
        for n in 1...5 { try repo.addHabit(name: "H\(n)", kind: .yesNo, schedule: .everyDay, today: today) }
        #expect(throws: Repository.Failure.atHabitLimit) { try repo.reactivate(first, today: d("2026-11-14")) }
    }
}

@Suite struct DeleteAndUndoTests {
    func seeded() throws -> (Repository, HabitID) {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, today: d("2026-11-01"))
        try repo.changeTarget(of: id, to: 12, today: d("2026-11-05"))
        for day in 1...12 where day != 7 {
            let key = DayKey(year: 2026, month: 11, day: day)!
            try repo.setDone(true, habit: id, on: key, today: key)
        }
        try repo.setRested(true, habit: id, today: d("2026-11-13"))
        try repo.dismissSuggestion(.levelUp, habit: id, today: d("2026-11-12"))
        try repo.recordAutomaticityCheck(.mostly, habit: id, today: d("2026-11-12"))
        try repo.markMilestoneSeen(100, habit: id)
        return (repo, id)
    }

    @Test func deleteRemovesEverythingAndUndoPutsItBack() throws {
        let (repo, id) = try seeded()
        let before = try repo.appData()

        let deleted = try repo.deleteHabit(id)
        #expect(deleted.name == "Read")
        let after = try repo.appData()
        #expect(after.habits.isEmpty)
        #expect(after.dismissals.isEmpty && after.automaticityChecks.isEmpty && after.milestonesSeen.isEmpty)
        for table in ["scheduleChanges", "targetChanges", "activePeriods", "habitDays"] {
            #expect(try repo.database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM \(table)") } == 0)
        }

        try repo.restore(deleted, today: d("2026-11-13"))
        #expect(try repo.appData() == before)
        // A second Undo does nothing.
        try repo.restore(deleted, today: d("2026-11-13"))
        #expect(try repo.appData() == before)
    }

    @Test func undoAtTheLimitBringsItBackPaused() throws {
        let (repo, id) = try seeded()
        let deleted = try repo.deleteHabit(id)
        for n in 1...5 { try repo.addHabit(name: "H\(n)", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13")) }

        try repo.restore(deleted, today: d("2026-11-13"))
        let history = try repo.history(id)
        #expect(history.activePeriods == [ActivePeriod(start: d("2026-11-01"), end: d("2026-11-13"), endReason: .paused)])
        #expect(history.completions.count == 11)
    }

    @Test func deletingAMissingHabitFails() throws {
        let repo = try makeRepository()
        #expect(throws: Repository.Failure.habitNotFound) { try repo.deleteHabit(HabitID()) }
    }
}

@Suite struct CorruptDataTests {
    /// A corrupt habit loads as unreadable; every other habit keeps working (build plan,
    /// "surface a corrupt row instead of crashing").
    @Test func aBadRowOnlyAffectsItsHabit() throws {
        let repo = try makeRepository()
        let good = try repo.addHabit(name: "Good", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        let bad = try repo.addHabit(name: "Bad", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        try repo.setDone(true, habit: bad, on: d("2026-11-01"), today: d("2026-11-01"))
        try repo.execute("UPDATE habitDays SET day = '2026-02-30'")

        let data = try repo.appData()
        #expect(try data.habit(good)?.history.get() != nil)
        #expect(data.habit(bad)?.history == .failure(.badDay(table: "habitDays", value: "2026-02-30")))
        #expect(data.readableHabits.map(\.habit.id) == [good])
        // It can't be changed, only deleted.
        #expect(throws: Repository.Failure.unreadable(.badDay(table: "habitDays", value: "2026-02-30"))) {
            try repo.setDone(true, habit: bad, on: d("2026-11-02"), today: d("2026-11-02"))
        }
        _ = try repo.deleteHabit(bad)
        #expect(try repo.appData().habits.map(\.id) == [good])
    }

    @Test(arguments: [
        ("UPDATE habits SET kind = 'sometimes'", StoredDataError.unknownValue(table: "habits", column: "kind", value: "sometimes")),
        ("UPDATE habitDays SET state = 'skipped'", .unknownValue(table: "habitDays", column: "state", value: "skipped")),
        ("UPDATE scheduleChanges SET source = 'magic'", .unknownValue(table: "scheduleChanges", column: "source", value: "magic")),
        ("DELETE FROM activePeriods", .invalidHistory(.noActivePeriod)),
        ("DELETE FROM scheduleChanges", .invalidHistory(.noSchedule)),
        ("UPDATE activePeriods SET start = '2026-10-01'", .invalidHistory(.firstPeriodNotOnCreatedDay)),
        ("UPDATE activePeriods SET \"end\" = '2026-10-01', endReason = 'paused'", .invalidHistory(.periodsOverlapOrOpenInMiddle)),
        ("UPDATE activePeriods SET \"end\" = '2026-11-05'", .invalidHistory(.periodsOverlapOrOpenInMiddle)),
        ("UPDATE habits SET createdDay = 'yesterday'", .badDay(table: "habits", value: "yesterday")),
    ])
    func corruptHistoriesAreReported(sql: String, error: StoredDataError) throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        try repo.setDone(true, habit: id, on: d("2026-11-01"), today: d("2026-11-01"))
        try repo.execute(sql)
        #expect(try repo.appData().habit(id)?.history == .failure(error))
    }

    @Test func badSideRowsAreSkippedAndReported() throws {
        let repo = try makeRepository()
        try repo.setNote("Fine", on: d("2026-11-13"), today: d("2026-11-13"))
        try repo.setNote("Broken", on: d("2026-11-12"), today: d("2026-11-13"))
        try repo.execute("UPDATE dayNotes SET day = 'nope' WHERE text = 'Broken'")
        try repo.updateSettings { $0.dayEndHour = 3 }
        try repo.execute("UPDATE appSettings SET dayEndHour = 9, appearance = 'neon'")

        let data = try repo.appData()
        #expect(data.notes == [d("2026-11-13"): "Fine"])
        #expect(data.settings.dayEndHour == 0) // back to the default
        #expect(data.problems.map(\.table).sorted() == ["appSettings", "appSettings", "dayNotes"])
    }
}

@Suite struct SettingsAndFlagsTests {
    @Test func defaultsUntilChanged() throws {
        let repo = try makeRepository()
        #expect(try repo.appData().settings == AppSettings())
        try repo.updateSettings {
            $0.dayEndHour = 2
            $0.report = ReportSettings(weekday: .saturday, hour: 9, minute: 30)
            $0.appearance = .dark
            $0.soundsEnabled = false
        }
        let settings = try repo.appData().settings
        #expect(settings.dayEndHour == 2)
        #expect(settings.report == ReportSettings(weekday: .saturday, hour: 9, minute: 30))
        #expect(settings.appearance == .dark)
        #expect(!settings.soundsEnabled)
        #expect(throws: Repository.Failure.invalidSettings) { try repo.updateSettings { $0.dayEndHour = 5 } }
        #expect(try repo.appData().settings.dayEndHour == 2)
    }

    @Test func unlocksAreKeptAndMarkedSeen() throws {
        let repo = try makeRepository()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try repo.recordUnlocks([.darkMode], at: now)
        try repo.recordUnlocks([.darkMode], at: now.addingTimeInterval(60)) // already there: unchanged
        #expect(try repo.appData().unlocks == [UnlockState(unlock: .darkMode, unlockedAt: now, noticeDismissed: false, seen: false)])
        try repo.dismissUnlockNotice(.darkMode, at: now)
        try repo.markUnlocksSeen(at: now)
        #expect(try repo.appData().unlocks == [UnlockState(unlock: .darkMode, unlockedAt: now, noticeDismissed: true, seen: true)])
    }

    @Test func firstTimeNotesMilestonesAndChecksAreRemembered() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-01"))
        try repo.markFirstTimeNoteSeen(.recovery)
        try repo.markFirstTimeNoteSeen(.recovery)
        try repo.markMilestoneSeen(100, habit: id)
        try repo.recordAutomaticityCheck(.aLittle, habit: id, today: d("2026-11-10"))
        try repo.recordAutomaticityCheck(.mostly, habit: id, today: d("2026-11-10")) // same day: replaced
        try repo.recordAutomaticityCheck(.completely, habit: id, today: d("2026-12-01"))
        try repo.dismissSuggestion(.levelDown, habit: id, today: d("2026-11-10"))
        try repo.dismissSuggestion(.levelDown, habit: id, today: d("2026-11-10"))

        let data = try repo.appData()
        #expect(data.firstTimeNotesSeen == [.recovery])
        #expect(data.milestonesSeen == [id: [100]])
        #expect(data.automaticityChecks[id] == [AutomaticityCheck(day: d("2026-11-10"), answer: .mostly),
                                                AutomaticityCheck(day: d("2026-12-01"), answer: .completely)])
        #expect(data.dismissals[id] == [SuggestionDismissal(kind: .levelDown, day: d("2026-11-10"))])
    }
}
