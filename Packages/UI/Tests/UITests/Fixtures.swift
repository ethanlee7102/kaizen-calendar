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
