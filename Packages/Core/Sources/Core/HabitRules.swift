/// Fixed numbers from the product rules.
public enum HabitRules {
    /// "Day X of 66": the median time new daily habits took to feel automatic (Lally et al., 2010).
    public static let journeyLength = 66

    /// Journey milestones: 66, then 100, 254 (the longest anyone took in the Lally study) and 365.
    public static let milestones = [66, 100, 254, 365]

    /// The most habits that can be active at once ("Why 5?", spec-collapsed-note.md §8).
    public static let maxActiveHabits = 5

    /// Adding a habit beyond this many shows Fogg's "start with three" nudge.
    public static let recommendedActiveHabits = 3

    /// Today plus this many past days can be edited freely (spec-collapsed-note.md §6).
    public static let freeEditDays = 2

    /// The automaticity check returns this many days after "Keep going" (spec-reports.md).
    public static let automaticityRecheckDays = 21

    public enum AddHabitState: Hashable, Sendable {
        case allowed
        /// Allowed, with the dismissible "Fogg recommends starting with three" note.
        case allowedWithNudge
        /// "You're at 5 habits. Graduate one that feels automatic to make room."
        case atLimit
    }

    public static func addHabitState(activeCount: Int) -> AddHabitState {
        if activeCount >= maxActiveHabits { return .atLimit }
        if activeCount >= recommendedActiveHabits { return .allowedWithNudge }
        return .allowed
    }
}

/// Which days can be changed, and how (spec-collapsed-note.md §6).
public enum EditRules {
    public enum DayAccess: Hashable, Sendable {
        /// Today and the 2 days before: check-offs and notes are editable.
        case editable
        /// Older: read-only, with "Change anyway" plus a confirmation.
        case readOnly
        /// After today: disabled.
        case future
    }

    public static func access(to day: DayKey, today: DayKey) -> DayAccess {
        if day > today { return .future }
        return day.days(to: today) <= HabitRules.freeEditDays ? .editable : .readOnly
    }

    /// Rest can only be marked for today, on a habit that's scheduled and not done, and not on
    /// the day after a miss: that day must be done or it's the second miss (decided 2026-11-12,
    /// closes the "rest every day after a miss" loophole).
    public static func canRest(_ evaluation: HabitEvaluation, on day: DayKey) -> Bool {
        day == evaluation.today && evaluation.status(on: day) == .pending && evaluation.recovery != .danger
    }
}
