/// A calendar day ("2026-11-08"), independent of time zones and clocks.
///
/// Every fact in 66 Days is keyed by the day it belongs to, never by a timestamp (D5 in
/// research/technical-decisions.md). Day arithmetic uses the proleptic Gregorian calendar
/// through Julian Day Numbers, so it's exact and never touches DST or time-zone rules.
public struct DayKey: Hashable, Comparable, Strideable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int
    /// Julian Day Number: consecutive days have consecutive numbers.
    public let julianDay: Int

    /// Returns nil for dates that don't exist (e.g. February 30).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= DayKey.daysIn(month: month, year: year) else {
            return nil
        }
        self.init(julianDay: DayKey.julianDay(year: year, month: month, day: day))
    }

    public init(julianDay: Int) {
        // Fliegel & Van Flandern's inverse conversion.
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146_097
        let c = a - 146_097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        day = e - (153 * m + 2) / 5 + 1
        month = m + 3 - 12 * (m / 10)
        year = 100 * b + d - 4800 + m / 10
        self.julianDay = julianDay
    }

    /// Parses "yyyy-MM-dd".
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// "yyyy-MM-dd", the stored form.
    public var description: String {
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public var weekday: Weekday {
        // JDN + 1 mod 7: 0 = Sunday.
        Weekday(rawValue: (julianDay + 1) % 7)!
    }

    public func adding(days: Int) -> DayKey { DayKey(julianDay: julianDay + days) }

    /// Days from `self` to `other` (positive when `other` is later).
    public func days(to other: DayKey) -> Int { other.julianDay - julianDay }

    public var firstOfMonth: DayKey { DayKey(year: year, month: month, day: 1)! }
    public var lastOfMonth: DayKey { DayKey(year: year, month: month, day: daysInMonth)! }
    public var daysInMonth: Int { DayKey.daysIn(month: month, year: year) }

    /// The Sunday that starts this day's Sunday–Saturday week.
    public var startOfWeek: DayKey { adding(days: -weekday.rawValue) }
    /// The Saturday that ends this day's Sunday–Saturday week.
    public var endOfWeek: DayKey { startOfWeek.adding(days: 6) }

    // MARK: Strideable, Comparable

    public func distance(to other: DayKey) -> Int { days(to: other) }
    public func advanced(by n: Int) -> DayKey { adding(days: n) }
    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.julianDay < rhs.julianDay }

    // MARK: Helpers

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func julianDay(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }
}

extension DayKey: Codable {
    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not a yyyy-MM-dd day: \(string)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A closed range of days, e.g. a report period. Both ends are included.
public struct DayRange: Hashable, Sendable, Codable, Sequence, CustomStringConvertible {
    public let start: DayKey
    public let end: DayKey

    public init(_ start: DayKey, _ end: DayKey) {
        precondition(start <= end, "DayRange start \(start) is after end \(end)")
        self.start = start
        self.end = end
    }

    public var count: Int { start.days(to: end) + 1 }
    public func contains(_ day: DayKey) -> Bool { day >= start && day <= end }
    public func makeIterator() -> ClosedRange<DayKey>.Iterator { (start...end).makeIterator() }
    public var description: String { "\(start)…\(end)" }

    private enum CodingKeys: String, CodingKey { case start, end }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(DayKey.self, forKey: .start)
        let end = try container.decode(DayKey.self, forKey: .end)
        guard start <= end else {
            throw DecodingError.dataCorruptedError(forKey: .end, in: container,
                                                   debugDescription: "DayRange end is before its start")
        }
        self.init(start, end)
    }
}
