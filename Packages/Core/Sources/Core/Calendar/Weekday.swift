/// Days of the week. Weeks start on Sunday everywhere in 66 Days.
public enum Weekday: Int, CaseIterable, Comparable, Sendable, Codable {
    case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Weekday letters in display order: S M T W T F S.
    public var letter: String { ["S", "M", "T", "W", "T", "F", "S"][rawValue] }
    public var shortName: String { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][rawValue] }
}

/// A set of weekdays (bit 0 = Sunday).
public struct WeekdaySet: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue & 0b111_1111 }

    public init(_ weekday: Weekday) { self.init(rawValue: 1 << UInt8(weekday.rawValue)) }

    public init<S: Sequence>(_ weekdays: S) where S.Element == Weekday {
        self.init(rawValue: weekdays.reduce(0) { $0 | (1 << UInt8($1.rawValue)) })
    }

    public static let all = WeekdaySet(rawValue: 0b111_1111)

    public func contains(_ weekday: Weekday) -> Bool { contains(WeekdaySet(weekday)) }
    public var count: Int { rawValue.nonzeroBitCount }

    /// Members in Sunday-first order.
    public var weekdays: [Weekday] { Weekday.allCases.filter { contains($0) } }
}

/// When a habit is scheduled: every day, or specific weekdays (never "N times a week";
/// see memory/streak-rules.md). Always has at least one day.
public struct Schedule: Hashable, Sendable, Codable {
    public let days: WeekdaySet

    public init(from decoder: Decoder) throws {
        let days = try decoder.singleValueContainer().decode(WeekdaySet.self)
        guard !days.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "A schedule needs at least one day"))
        }
        self.days = days
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(days)
    }

    public init?(days: WeekdaySet) {
        guard !days.isEmpty else { return nil }
        self.days = days
    }

    public init?<S: Sequence>(_ weekdays: S) where S.Element == Weekday {
        self.init(days: WeekdaySet(weekdays))
    }

    public static let everyDay = Schedule(days: .all)!

    public var isEveryDay: Bool { days == .all }
    public var daysPerWeek: Int { days.count }
    public func includes(_ day: DayKey) -> Bool { days.contains(day.weekday) }
}
