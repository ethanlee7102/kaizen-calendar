/// Insights appear only when the data supports them (memory/insight-thresholds.md). Each one
/// has an explicit "show when" rule; nil means "say nothing".
public enum Insights {
    // MARK: Weakest weekday

    public static let weakestWeekdayMinMisses = 3
    public static let weakestWeekdayRateMultiple = 2.0
    public static let weakestWeekdayMinDays = 28
    /// The rolling window it looks at, so an old bad stretch doesn't follow the habit forever.
    public static let weakestWeekdayWindowDays = 56

    /// The weekday a habit is missed most, normalized by how often it's scheduled. Shown only
    /// if that weekday has ≥ 3 misses, a miss rate ≥ 2× the habit's overall rate, and the habit
    /// has ≥ 4 weeks of data. Looks at the last 8 weeks up to `through`, and only at weekdays
    /// still in the schedule (decided 2026-11-12).
    public static func weakestWeekday(_ evaluation: HabitEvaluation, through: DayKey) -> Weekday? {
        guard evaluation.history.createdDay.days(to: through) + 1 >= weakestWeekdayMinDays else { return nil }
        let since = through.adding(days: -(weakestWeekdayWindowDays - 1))
        let scheduled = evaluation.history.schedule(on: through).days
        let decided = evaluation.decidedDays.filter { $0 >= since && $0 <= through }
        guard !decided.isEmpty else { return nil }
        let overallMisses = decided.count { evaluation.status(on: $0).isMiss }
        let overallRate = Double(overallMisses) / Double(decided.count)
        guard overallRate > 0 else { return nil }

        var best: (weekday: Weekday, rate: Double)?
        for weekday in scheduled.weekdays {
            let onWeekday = decided.filter { $0.weekday == weekday }
            let misses = onWeekday.count { evaluation.status(on: $0).isMiss }
            guard misses >= weakestWeekdayMinMisses else { continue }
            let rate = Double(misses) / Double(onWeekday.count)
            guard rate >= weakestWeekdayRateMultiple * overallRate else { continue }
            if best == nil || rate > best!.rate { best = (weekday, rate) }
        }
        return best?.weekday
    }

    // MARK: Never-miss-twice saves

    public struct Saves: Hashable, Sendable, Codable {
        public let misses: Int
        public let recovered: Int
        /// "No misses this week." when there were none.
        public var noMisses: Bool { misses == 0 }
        /// "Missed N times, recovered every time."
        public var recoveredEveryTime: Bool { misses > 0 && misses == recovered }
    }

    public static func saves(_ evaluations: [HabitEvaluation], in period: DayRange) -> Saves {
        var misses = 0
        var recovered = 0
        for evaluation in evaluations {
            for day in evaluation.scheduledDays where period.contains(day) {
                switch evaluation.status(on: day) {
                case .missed: misses += 1
                case .missedRecovered: misses += 1; recovered += 1
                default: break
                }
            }
        }
        return Saves(misses: misses, recovered: recovered)
    }

    // MARK: Month summary line

    public static let monthSummaryMinScheduledDays = 7

    public struct MonthSummary: Hashable, Sendable {
        public let consistency: Consistency
        /// Shown only when ≥ 1.
        public let missesRecovered: Int
    }

    /// "November · 92% consistency · 3 misses recovered" (spec-calendar-and-goal-detail.md).
    /// Hidden until the month so far has ≥ 7 scheduled days.
    public static func monthSummary(_ evaluations: [HabitEvaluation], month: DayKey, today: DayKey) -> MonthSummary? {
        let end = min(month.lastOfMonth, today)
        guard month.firstOfMonth <= end else { return nil }
        let range = DayRange(month.firstOfMonth, end)
        let consistency = evaluations.reduce(Consistency.zero) { $0 + $1.consistency(in: range) }
        guard consistency.scheduled >= monthSummaryMinScheduledDays else { return nil }
        return MonthSummary(consistency: consistency, missesRecovered: saves(evaluations, in: range).recovered)
    }

    // MARK: Weekly consistency trend

    /// The trend graph appears after this many full weeks of data.
    public static let trendMinFullWeeks = 2

    public struct TrendWeek: Hashable, Sendable, Codable {
        /// Sunday–Saturday.
        public let week: DayRange
        public let consistency: Consistency
        public let recoveredMisses: [DayKey]
        /// Misses not recovered: they broke the streak (or are still waiting on the next day).
        public let unrecoveredMisses: [DayKey]
    }

    /// Weekly completion rate (rest excluded) for the `weeks` full Sunday–Saturday weeks
    /// ending on or before `through`, oldest first. Nil until there are 2 full weeks of data.
    public static func weeklyTrend(_ evaluations: [HabitEvaluation], through: DayKey, weeks: Int = 12) -> [TrendWeek]? {
        guard let start = evaluations.map(\.history.createdDay).min() else { return nil }
        let lastWeekEnd = through.endOfWeek == through ? through : through.startOfWeek.adding(days: -1)
        let firstFullWeekStart = start == start.startOfWeek ? start : start.endOfWeek.adding(days: 1)
        let fullWeeks = (firstFullWeekStart.days(to: lastWeekEnd) + 1) / 7
        guard fullWeeks >= trendMinFullWeeks else { return nil }

        return (0..<min(weeks, fullWeeks)).reversed().map { back in
            let end = lastWeekEnd.adding(days: -7 * back)
            let week = DayRange(end.adding(days: -6), end)
            var recovered: [DayKey] = []
            var breaking: [DayKey] = []
            for evaluation in evaluations {
                for day in evaluation.scheduledDays where week.contains(day) {
                    switch evaluation.status(on: day) {
                    case .missedRecovered: recovered.append(day)
                    case .missed: breaking.append(day)
                    default: break
                    }
                }
            }
            return TrendWeek(week: week,
                             consistency: evaluations.reduce(.zero) { $0 + $1.consistency(in: week) },
                             recoveredMisses: recovered.sorted(), unrecoveredMisses: breaking.sorted())
        }
    }
}

/// "Welcome back. Streaks start over; your journey doesn't." (spec-edge-states.md): shown
/// once when the app wasn't opened for several days and a streak broke meanwhile.
public enum WelcomeBack {
    /// Shown when the app wasn't opened on more than this many whole days in between.
    public static let minDaysAway = 2

    public static func shouldShow(lastOpenedDay: DayKey, evaluations: [HabitEvaluation], today: DayKey) -> Bool {
        let daysNotOpened = lastOpenedDay.days(to: today) - 1
        guard daysNotOpened > minDaysAway else { return false }
        // A break on the last day opened still happened while away: that day's miss only
        // became final after it ended.
        return evaluations.contains { evaluation in
            evaluation.breakDays.contains { $0 >= lastOpenedDay }
        }
    }
}
