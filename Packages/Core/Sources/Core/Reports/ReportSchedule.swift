import Foundation

/// When reports arrive and which days they cover (spec-reports.md, decided 2026-11-11):
/// - Weekly: on the delivery day (default Sunday 6pm), covering the most recent finished
///   Sunday–Saturday week.
/// - Monthly: on the last delivery day of the month, instead of the weekly one, covering every
///   finished week since the previous monthly report.
/// - If the Mac was off, missed reports are delivered when the app runs again: the newest goes
///   in the envelope, older ones go to the archive unread.
public struct ReportSettings: Hashable, Sendable, Codable {
    public var weekday: Weekday
    public var hour: Int
    public var minute: Int

    public init(weekday: Weekday = .sunday, hour: Int = 18, minute: Int = 0) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

public enum PeriodicReportKind: String, Hashable, Sendable, Codable {
    case weekly, monthly
}

public struct DueReport: Hashable, Sendable {
    public let kind: PeriodicReportKind
    /// The calendar day it's delivered on.
    public let deliveryDay: DayKey
    /// The days it covers (whole Sunday–Saturday weeks).
    public let period: DayRange
    /// "Your November": monthly reports are named after the delivery month.
    public var titleMonth: Int { deliveryDay.month }
}

public struct ReportSchedule: Sendable {
    public let settings: ReportSettings
    public let clock: DayClock

    public init(settings: ReportSettings = ReportSettings(), clock: DayClock) {
        self.settings = settings
        self.clock = clock
    }

    /// The moment a report is delivered on `day` (wall clock, ignoring the day-end time).
    public func deliveryTime(on day: DayKey) -> Date {
        clock.date(on: day, hour: settings.hour, minute: settings.minute)
    }

    /// Whether `day` is the last delivery day of its month (the monthly report's day).
    public func isMonthlyDeliveryDay(_ day: DayKey) -> Bool {
        day.weekday == settings.weekday && day.adding(days: 7).month != day.month
    }

    /// The most recent finished Sunday–Saturday week before `day`.
    public static func weekCovered(byDeliveryOn day: DayKey) -> DayRange {
        let end = day.adding(days: -(day.weekday.rawValue + 1))
        return DayRange(end.adding(days: -6), end)
    }

    /// Reports due up to `now`, oldest first. Each week is covered by at most one weekly
    /// report, even if the delivery day changes in Settings.
    /// - Parameters:
    ///   - lastCoveredWeekEnd: the last day (a Saturday) covered by any weekly or monthly
    ///     report already made; nil before the first report.
    ///   - lastMonthlyPeriodEnd: where the previous monthly report's period ended.
    ///   - firstUseDay: the first habit's creation day; weeks before it are skipped.
    public func dueReports(lastCoveredWeekEnd: DayKey?, lastMonthlyPeriodEnd: DayKey?,
                           firstUseDay: DayKey, now: Date) -> [DueReport] {
        let today = clock.calendarDay(for: now)
        var day = (lastCoveredWeekEnd ?? firstUseDay.adding(days: -1)).adding(days: 1)
        // Jump to the first delivery weekday.
        day = day.adding(days: (settings.weekday.rawValue - day.weekday.rawValue + 7) % 7)

        var monthlyEnd = lastMonthlyPeriodEnd
        var due: [DueReport] = []
        while day <= today, deliveryTime(on: day) <= now {
            let week = ReportSchedule.weekCovered(byDeliveryOn: day)
            let alreadyCovered = lastCoveredWeekEnd.map { week.end <= $0 } ?? false
            if week.end >= firstUseDay, !alreadyCovered {
                if isMonthlyDeliveryDay(day) {
                    let start = monthlyEnd.map { $0.adding(days: 1) } ?? firstUseDay.startOfWeek
                    due.append(DueReport(kind: .monthly, deliveryDay: day, period: DayRange(start, week.end)))
                    monthlyEnd = week.end
                } else {
                    due.append(DueReport(kind: .weekly, deliveryDay: day, period: week))
                }
            }
            day = day.adding(days: 7)
        }
        return due
    }
}

/// The automaticity check on the day-66 report and its re-checks (spec-reports.md).
public enum Automaticity {
    /// "I do this automatically.", 1 (Not at all) … 5 (Completely).
    public enum Answer: Int, CaseIterable, Hashable, Sendable, Codable {
        case notAtAll = 1, aLittle, somewhat, mostly, completely

        public var label: String {
            switch self {
            case .notAtAll: "Not at all"
            case .aLittle: "A little"
            case .somewhat: "Somewhat"
            case .mostly: "Mostly"
            case .completely: "Completely"
            }
        }
    }

    public enum Recommendation: Hashable, Sendable {
        /// 4–5: move to inactive as Graduated ✓66.
        case graduate
        /// 1–3: keep going; the check returns in about 3 weeks.
        case keepGoing
    }

    public static func recommendation(for answer: Answer) -> Recommendation {
        answer.rawValue >= 4 ? .graduate : .keepGoing
    }

    /// After "Keep going", the check returns about every 3 weeks.
    public static func nextCheckDay(after lastCheck: DayKey) -> DayKey {
        lastCheck.adding(days: HabitRules.automaticityRecheckDays)
    }

    public static func isRecheckDue(lastCheck: DayKey, today: DayKey) -> Bool {
        today >= nextCheckDay(after: lastCheck)
    }
}
