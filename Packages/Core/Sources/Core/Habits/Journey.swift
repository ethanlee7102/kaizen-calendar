/// "Day X of 66": how far a habit has formed. Counts done days and never resets
/// (memory/journey-vs-streak.md); after 66 it becomes "Day N ✓66" (memory/after-day-66.md).
public struct Journey: Hashable, Sendable {
    /// Done days in order.
    public let doneDays: [DayKey]

    public init(doneDays: [DayKey]) { self.doneDays = doneDays }

    public var count: Int { doneDays.count }
    public var hasReached66: Bool { count >= HabitRules.journeyLength }

    /// Brush-circle fill, 0...1 (full from day 66 on).
    public var progress: Double { min(1, Double(count) / Double(HabitRules.journeyLength)) }

    /// The day the journey reached `dayNumber` (e.g. 66), if it has.
    public func dayReached(_ dayNumber: Int) -> DayKey? {
        dayNumber >= 1 && dayNumber <= count ? doneDays[dayNumber - 1] : nil
    }

    /// The next milestone ahead: 66, then 100, 254, 365. Nil after 365.
    public var nextMilestone: Int? { HabitRules.milestones.first { $0 > count } }

    /// Milestones reached so far.
    public var reachedMilestones: [Int] { HabitRules.milestones.filter { $0 <= count } }
}
