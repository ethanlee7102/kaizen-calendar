/// Report contents as plain data; the UI turns them into the letter (spec-reports.md).
/// Every insight here follows its "show when" rule, so absent means "don't show".
///
/// Build each report from evaluations as of its delivery day (`HabitEvaluation(today:
/// deliveryDay)`), so a report caught up after the Mac was off shows the numbers it would have
/// shown then. Store the result when it's delivered: archived reports are read-only and must
/// not change if the data is edited later (Phase 2).

/// One habit's row in "The week at a glance".
public struct HabitPeriodRow: Hashable, Sendable {
    public let habitID: HabitID
    /// Each day of the period with this habit's status (dots: done / recovered / missed / rest).
    public let days: [Day]
    public let consistency: Consistency

    public struct Day: Hashable, Sendable {
        public let day: DayKey
        public let status: HabitDayStatus
    }
}

public struct HabitWeekday: Hashable, Sendable {
    public let habitID: HabitID
    public let weekday: Weekday
}

public struct DayNote: Hashable, Sendable {
    public let day: DayKey
    public let text: String

    public init(day: DayKey, text: String) {
        self.day = day
        self.text = text
    }
}

/// Sections shared by weekly and monthly reports.
public struct PeriodSections: Hashable, Sendable {
    public let period: DayRange
    /// Habits with at least one scheduled day in the period, in habit order.
    public let rows: [HabitPeriodRow]
    public let saves: Insights.Saves
    /// Each active habit's journey as of delivery.
    public let journeys: [HabitID: Journey]
    public let weakestWeekdays: [HabitWeekday]
    public let suggestions: [Suggestion]
    public let notes: [DayNote]

    public init(period: DayRange, evaluations: [HabitEvaluation], notes: [DayNote],
                dismissals: [HabitID: [SuggestionDismissal]]) {
        self.period = period
        rows = evaluations.compactMap { evaluation in
            guard evaluation.scheduledDays.contains(where: period.contains) else { return nil }
            return HabitPeriodRow(
                habitID: evaluation.id,
                days: period.map { HabitPeriodRow.Day(day: $0, status: evaluation.status(on: $0)) },
                consistency: evaluation.consistency(in: period))
        }
        saves = Insights.saves(evaluations, in: period)
        let active = evaluations.filter(\.history.isActiveNow)
        journeys = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0.journey) })
        weakestWeekdays = active.compactMap { evaluation in
            Insights.weakestWeekday(evaluation, through: period.end)
                .map { HabitWeekday(habitID: evaluation.id, weekday: $0) }
        }
        suggestions = active.compactMap {
            Suggestions.suggestion(for: $0, dismissals: dismissals[$0.id] ?? [])
        }
        self.notes = notes.filter { period.contains($0.day) && !$0.text.isEmpty }.sorted { $0.day < $1.day }
    }
}

public struct WeeklyReport: Hashable, Sendable {
    public let sections: PeriodSections
    /// "Your first week. Patterns show up once there's more to look at."
    public let isFirstWeek: Bool
    /// The last obstacle answer the user wrote, shown with "How did it go?".
    public let previousObstacle: String?

    public init(period: DayRange, evaluations: [HabitEvaluation], notes: [DayNote],
                dismissals: [HabitID: [SuggestionDismissal]] = [:], previousObstacle: String?) {
        sections = PeriodSections(period: period, evaluations: evaluations, notes: notes, dismissals: dismissals)
        let firstUse = evaluations.map(\.history.createdDay).min()
        isFirstWeek = firstUse.map { $0 >= period.start } ?? true
        self.previousObstacle = previousObstacle
    }
}

public struct MonthlyReport: Hashable, Sendable {
    public let sections: PeriodSections
    /// Last 12 weeks; nil until there are 2 full weeks of data.
    public let trend: [Insights.TrendWeek]?
    /// Inactive habits for "Not keeping up with a past habit?" (empty: section hidden).
    public let inactiveHabits: [HabitID]
    /// Reactivate buttons are enabled only with fewer than 5 active habits.
    public let canReactivate: Bool

    public init(period: DayRange, evaluations: [HabitEvaluation], notes: [DayNote],
                dismissals: [HabitID: [SuggestionDismissal]] = [:]) {
        sections = PeriodSections(period: period, evaluations: evaluations, notes: notes, dismissals: dismissals)
        trend = Insights.weeklyTrend(evaluations, through: period.end)
        inactiveHabits = evaluations.filter { !$0.history.isActiveNow }.map(\.id)
        canReactivate = evaluations.count(where: \.history.isActiveNow) < HabitRules.maxActiveHabits
    }
}

/// The per-habit report when a habit reaches its 66th done day.
public struct Day66Report: Hashable, Sendable {
    public let habitID: HabitID
    /// The 66 done days, for the mini heatmap.
    public let doneDays: [DayKey]
    public let reachedOn: DayKey
    /// Calendar days from creation to day 66.
    public let calendarDays: Int
    public let longestStreak: Int
    public let streakBreaks: Int
    public let saves: Int
    public let targetHistory: [TargetChange]
    public let scheduleHistory: [ScheduleChange]
    /// "Your first note vs your latest note", from the habit's life so far.
    public let firstNote: DayNote?
    public let latestNote: DayNote?

    /// Nil if the habit hasn't reached day 66.
    public init?(evaluation: HabitEvaluation, notes: [DayNote]) {
        let journey = evaluation.journey
        guard let reached = journey.dayReached(HabitRules.journeyLength) else { return nil }
        let history = evaluation.history
        habitID = history.id
        doneDays = Array(journey.doneDays.prefix(HabitRules.journeyLength))
        reachedOn = reached
        calendarDays = history.createdDay.days(to: reached) + 1
        longestStreak = evaluation.longestStreak
        streakBreaks = evaluation.breakDays.count
        saves = evaluation.saves
        targetHistory = history.targetChanges
        scheduleHistory = history.scheduleChanges
        let habitNotes = notes.filter { $0.day >= history.createdDay && $0.day <= evaluation.today && !$0.text.isEmpty }
            .sorted { $0.day < $1.day }
        firstNote = habitNotes.first
        latestNote = habitNotes.count > 1 ? habitNotes.last : nil
    }
}
