import Foundation
import Core
@testable import UI

func d(_ string: String) -> DayKey { DayKey(string)! }

/// A habit made from Core values: created on `created`, done on `done` days, rested on `rested`.
func noteHabit(_ name: String, identity: String? = nil, kind: HabitKind = .yesNo, target: Int? = nil,
               schedule: Schedule = .everyDay, created: String, done: [DayKey] = [], rested: [DayKey] = [],
               deactivated: String? = nil, today: DayKey) -> NoteHabit {
    var history = HabitHistory.new(kind: kind, target: target, schedule: schedule, on: d(created))
    // Only scheduled days: a check-off can't be stored on any other day (the repository's rule).
    for day in done where history.isScheduled(on: day) { history.setDone(true, on: day) }
    for day in rested { history.setRested(true, on: day) }
    if let deactivated { history.deactivate(on: d(deactivated), reason: .paused) }
    return NoteHabit(name: name, identity: identity, evaluation: HabitEvaluation(history: history, today: today))
}

/// Every day from `start` through `end`, except `skipping`.
func days(_ start: String, _ end: String, skipping: [String] = []) -> [DayKey] {
    let skip = Set(skipping.map(d))
    return (d(start)...d(end)).filter { !skip.contains($0) }
}

enum Fixture {
    /// Saturday.
    static let today = d("2026-11-14")

    /// A month with every mark: Read has a recovered miss (Nov 3), a broken streak (Nov 8–9), a
    /// rest day (Nov 11) and a miss yesterday (a danger day today); Pushups is Mon/Wed/Fri;
    /// Floss is done today; Meditate starts today.
    static func month(today: DayKey = today) -> NoteInput {
        let read = noteHabit("Read", identity: "a reader", kind: .amount(unit: "pages"), target: 10, created: "2026-10-25",
                             done: days("2026-10-25", "2026-11-12", skipping: ["2026-11-03", "2026-11-08", "2026-11-09", "2026-11-11"]),
                             rested: [d("2026-11-11")], today: today)
        let pushups = noteHabit("Pushups", kind: .amount(unit: "pushups"), target: 15,
                                schedule: Schedule([.monday, .wednesday, .friday])!, created: "2026-11-01",
                                done: days("2026-11-01", "2026-11-13"), today: today)
        let floss = noteHabit("Floss", created: "2026-11-05", done: days("2026-11-05", "2026-11-14"), today: today)
        let meditate = noteHabit("Meditate", identity: "calm", created: "2026-11-14", today: today)
        return NoteInput(today: today, habits: [read, pushups, floss, meditate],
                         notes: [d("2026-11-04"): "Read before bed, not after."])
    }
}

/// Letters (Phase 6): built from Core's report values the way the app builds them, as of their
/// delivery day.
enum LetterFixture {
    static let readID = HabitID(UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!)
    static let walkID = HabitID(UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!)
    static let weeklyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    static let monthlyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let day66ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!
    static let recheckID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!

    static let read = ReportHabitLabel(name: "Read", identity: "a reader", kind: .amount(unit: "pages"))
    static let walk = ReportHabitLabel(name: "Walk", identity: nil, kind: .yesNo)

    /// Read since Sep 1 (10 pages, daily), done every day except Nov 3 (recovered).
    static func readHistory() -> HabitHistory {
        var history = HabitHistory.new(id: readID, kind: .amount(unit: "pages"), target: 10, schedule: .everyDay, on: d("2026-09-01"))
        for day in days("2026-09-01", "2026-11-13", skipping: ["2026-11-03"]) { history.setDone(true, on: day) }
        return history
    }

    /// Walk (yes/no, daily) since Sep 20, done to Oct 10, then paused.
    static func walkHistory() -> HabitHistory {
        var history = HabitHistory.new(id: walkID, kind: .yesNo, schedule: .everyDay, on: d("2026-09-20"))
        for day in days("2026-09-20", "2026-10-10", skipping: ["2026-09-30"]) { history.setDone(true, on: day) }
        history.deactivate(on: d("2026-10-11"), reason: .paused)
        return history
    }

    /// The notebook today (Sat Nov 14): Read active, Walk paused.
    static func note(today: DayKey = Fixture.today) -> NoteInput {
        NoteInput(today: today, habits: [
            NoteHabit(name: "Read", identity: "a reader", evaluation: HabitEvaluation(history: readHistory(), today: today)),
            NoteHabit(name: "Walk", identity: nil, evaluation: HabitEvaluation(history: walkHistory(), today: today)),
        ])
    }

    static func weekly(isFiled: Bool = false, isUnread: Bool = true, answers: [ReportQuestion: String] = [:]) -> LetterInput {
        let delivery = d("2026-11-08")
        let period = DayRange(d("2026-11-01"), d("2026-11-07"))
        let report = WeeklyReport(period: period, evaluations: [HabitEvaluation(history: readHistory(), today: delivery)],
                                  notes: [DayNote(day: d("2026-11-05"), text: "Read before bed, not after.")],
                                  previousObstacle: "Late meetings. Read at lunch instead.")
        return LetterInput(id: weeklyID, kind: .weekly, deliveryDay: delivery, period: period, isUnread: isUnread,
                           isFiled: isFiled, content: .weekly(report), habits: [readID: read], answers: answers)
    }

    static func monthly() -> LetterInput {
        let delivery = d("2026-10-25")
        let period = DayRange(d("2026-08-30"), d("2026-10-24"))
        let evaluations = [readHistory(), walkHistory()].map { HabitEvaluation(history: $0, today: delivery) }
        let report = MonthlyReport(period: period, evaluations: evaluations, notes: [])
        return LetterInput(id: monthlyID, kind: .monthly, deliveryDay: delivery, period: period, isUnread: false,
                           isFiled: true, content: .monthly(report), habits: [readID: read, walkID: walk],
                           answers: [.biggestWin: "Reading every single day in October."])
    }

    static func day66(answers: [ReportQuestion: String] = [:]) -> LetterInput {
        let delivery = d("2026-11-06")
        var notes = [DayNote(day: d("2026-09-02"), text: "Ten pages felt long."),
                     DayNote(day: d("2026-11-05"), text: "Read before bed, not after.")]
        notes.sort { $0.day < $1.day }
        let report = Day66Report(evaluation: HabitEvaluation(history: readHistory(), today: delivery), notes: notes)!
        return LetterInput(id: day66ID, kind: .day66, deliveryDay: delivery, period: nil, isUnread: false, isFiled: false,
                           content: .day66(report), habits: [readID: read], answers: answers)
    }

    static func recheck() -> LetterInput {
        LetterInput(id: recheckID, kind: .recheck, deliveryDay: d("2026-11-13"), period: nil, isUnread: true, isFiled: false,
                    content: .recheck(RecheckReport(habitID: readID, dayCount: 73, previousAnswer: .somewhat)),
                    habits: [readID: read], answers: [:])
    }

    static func input(letters: [LetterInput], suggestions: [HabitID: Suggestion] = [:],
                      dismissals: [HabitID: [SuggestionDismissal]] = [:]) -> NotebookInput {
        NotebookInput(note: note(), letters: letters, suggestions: suggestions, dismissals: dismissals)
    }
}
