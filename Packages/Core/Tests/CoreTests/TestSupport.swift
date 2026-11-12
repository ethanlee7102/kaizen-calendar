@testable import Core

/// "2026-11-08" → DayKey. Crashes on bad input (tests only).
func d(_ string: String) -> DayKey { DayKey(string)! }

/// A daily (or scheduled) yes/no habit created on `created`, with check-offs written as a
/// compact pattern starting that day: "x" done, "." missed (or pending if it's today),
/// "r" rest, "-" skip (no fact). Pattern positions are calendar days, not scheduled days.
func habit(
    from created: String,
    _ pattern: String = "",
    schedule: Schedule = .everyDay,
    kind: HabitKind = .yesNo,
    target: Int? = nil,
    id: HabitID = HabitID()
) -> HabitHistory {
    let start = d(created)
    var history = HabitHistory.new(id: id, kind: kind, target: target ?? (kind == .yesNo ? nil : 10),
                                   schedule: schedule, on: start)
    for (offset, char) in pattern.enumerated() {
        let day = start.adding(days: offset)
        switch char {
        case "x": history.completions.insert(day)
        case "r": history.rests.insert(day)
        default: break
        }
    }
    return history
}

/// `today` is the last pattern day unless given.
func evaluate(_ history: HabitHistory, today: String) -> HabitEvaluation {
    HabitEvaluation(history: history, today: d(today))
}

func days(_ weekdays: Weekday...) -> Schedule { Schedule(weekdays)! }
