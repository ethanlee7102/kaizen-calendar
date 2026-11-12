import Foundation

/// Turns moments into days, using the user's day-end time ("My day ends at", spec-settings.md).
///
/// With a 2am day end, 1:30am on Tuesday still belongs to Monday. Days follow the Mac's
/// current time zone (spec-edge-states.md, travel); the wall clock decides, so DST changes
/// never shift which day a check-off belongs to. The default time zone follows the Mac
/// automatically (`TimeZone.autoupdatingCurrent`).
public struct DayClock: Sendable {
    /// Hours after midnight when the day ends: 0 (midnight) through 4.
    public static let allowedDayEndHours = 0...4

    public var timeZone: TimeZone
    public let dayEndHour: Int

    public init(timeZone: TimeZone = .autoupdatingCurrent, dayEndHour: Int = 0) {
        precondition(DayClock.allowedDayEndHours.contains(dayEndHour), "Day end must be 0–4am")
        self.timeZone = timeZone
        self.dayEndHour = dayEndHour
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The day a moment belongs to.
    public func day(for date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let calendarDay = DayKey(year: c.year!, month: c.month!, day: c.day!)!
        return c.hour! < dayEndHour ? calendarDay.adding(days: -1) : calendarDay
    }

    /// The calendar date of a moment, ignoring the day-end time (for clock-based events
    /// such as report delivery).
    public func calendarDay(for date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: c.year!, month: c.month!, day: c.day!)!
    }

    /// When `day` begins (its day-end hour). In a DST gap, the next valid moment.
    public func start(of day: DayKey) -> Date {
        date(on: day, hour: dayEndHour, minute: 0)
    }

    /// When `day` ends, which is when the next day begins.
    public func end(of day: DayKey) -> Date { start(of: day.adding(days: 1)) }

    /// A wall-clock time on a calendar date. In a DST gap, the next valid moment.
    public func date(on day: DayKey, hour: Int, minute: Int) -> Date {
        let calendar = calendar
        // Noon always exists, even where DST starts at midnight.
        let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        // .nextTime: a time inside a spring-forward gap becomes the first moment after the gap.
        // .first: a repeated fall-back time uses its first occurrence.
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: noon,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
    }
}

/// A Sunday-first month grid for calendars.
public struct MonthGrid: Hashable, Sendable {
    public let year: Int
    public let month: Int
    /// Rows of 7 cells, Sunday first; nil cells are padding outside the month.
    public let weeks: [[DayKey?]]

    public init(year: Int, month: Int) {
        let first = DayKey(year: year, month: month, day: 1)!
        var cells: [DayKey?] = Array(repeating: nil, count: first.weekday.rawValue)
        cells += (0..<first.daysInMonth).map { Optional(first.adding(days: $0)) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        self.year = year
        self.month = month
        weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    public init(containing day: DayKey) { self.init(year: day.year, month: day.month) }

    public var days: [DayKey] { weeks.flatMap { $0.compactMap { $0 } } }
}
