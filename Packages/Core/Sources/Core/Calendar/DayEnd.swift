import Foundation

/// "My day ends at" over time: the hour in effect, and a newly chosen hour that starts with the
/// next day (user's choice after the Phase 5 review, 2026-11-16). Changing it never moves today
/// backwards: at 00:30 on Tuesday with a midnight day end, choosing 1am keeps today Tuesday (it
/// would otherwise become Monday again and hide Tuesday's check-offs); the new hour first
/// applies to Wednesday.
public struct DayEnd: Hashable, Sendable, Codable {
    /// The hour in effect (0 = midnight … 4am).
    public var hour: Int
    /// A chosen hour that applies from the day after `after`.
    public var change: Change?

    public struct Change: Hashable, Sendable, Codable {
        public var hour: Int
        /// The day it was chosen on: the last day that keeps the old hour.
        public var after: DayKey

        public init(hour: Int, after: DayKey) {
            self.hour = hour
            self.after = after
        }
    }

    public init(hour: Int = 0, change: Change? = nil) {
        self.hour = hour
        self.change = change
    }

    /// The hour the user chose (what Settings shows).
    public var chosenHour: Int { change?.hour ?? hour }

    /// The day a moment belongs to.
    ///
    /// Up to the end of `change.after`, the old hour decides. After that, the new hour does, but
    /// never earlier than the day after `after`: with a later new hour (midnight → 1am), the
    /// first moments after the old boundary would otherwise go back to `after`.
    public func day(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> DayKey {
        let old = DayClock(timeZone: timeZone, dayEndHour: hour).day(for: date)
        guard let change, old > change.after else { return old }
        return max(DayClock(timeZone: timeZone, dayEndHour: change.hour).day(for: date), change.after.adding(days: 1))
    }

    /// When `day` ends (when the next day begins).
    public func end(of day: DayKey, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let hour = change.map { day <= $0.after ? self.hour : $0.hour } ?? self.hour
        return DayClock(timeZone: timeZone, dayEndHour: hour).end(of: day)
    }

    /// The setting after choosing `newHour` at `date`. A change already in effect is folded in
    /// first; choosing again on the same day replaces that day's choice.
    public func changing(to newHour: Int, at date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> DayEnd {
        precondition(DayClock.allowedDayEndHours.contains(newHour), "Day end must be 0–4am")
        let today = day(for: date, timeZone: timeZone)
        var result = self
        // Settled: the new hour alone gives a day after `after`, so the old hour is no longer
        // needed. (Within the few hours between the old and new boundary it isn't settled yet.)
        if let change, DayClock(timeZone: timeZone, dayEndHour: change.hour).day(for: date) > change.after {
            result = DayEnd(hour: change.hour)
        }
        if var change = result.change {
            change.hour = newHour
            // Changing back on the same day cancels it.
            result.change = newHour == result.hour && today <= change.after ? nil : change
        } else if newHour != result.hour {
            result.change = Change(hour: newHour, after: today)
        }
        return result
    }

    /// The chosen hour hasn't started yet (it starts tomorrow).
    public func startsLater(today: DayKey) -> Bool {
        change.map { today <= $0.after } ?? false
    }
}
