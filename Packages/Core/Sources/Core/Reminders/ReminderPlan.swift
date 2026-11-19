import Foundation

/// When and whether tonight's never-miss-twice reminder is scheduled, and when the in-app
/// permission prompt shows (spec-notifications.md). Pure rules: the app applies the plan to
/// macOS's notification center.
public extension NeverMissTwiceReminder {
    /// The habits that qualify today, with their names, in list order.
    static func items(_ evaluations: [HabitEvaluation], name: (HabitID) -> String?) -> [Item] {
        evaluations.filter(qualifies).compactMap { evaluation in
            name(evaluation.id).map { Item(name: $0, streak: evaluation.currentStreak) }
        }
    }

    /// When `today`'s reminder fires: the reminder time inside that day, which runs from the
    /// previous day's end to its own end ("relative to the user's day"). With a 2am day end, a
    /// 1am reminder is the 1am after the calendar date, still part of `today`.
    static func fireDate(on today: DayKey, hour: Int, minute: Int, dayEnd: DayEnd,
                         timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let clock = DayClock(timeZone: timeZone)
        let start = dayEnd.end(of: today.adding(days: -1), timeZone: timeZone)
        let onDate = clock.date(on: today, hour: hour, minute: minute)
        return onDate >= start ? onDate : clock.date(on: today.adding(days: 1), hour: hour, minute: minute)
    }

    /// A reminder handed to macOS: the day it's for and when it fires. Remembered on this Mac,
    /// so a reminder that already fired isn't scheduled again that day (at most one per evening,
    /// even if the time is changed afterwards).
    struct Scheduled: Hashable, Sendable, Codable {
        public let day: DayKey
        public let fireDate: Date

        public init(day: DayKey, fireDate: Date) {
            self.day = day
            self.fireDate = fireDate
        }
    }

    struct Pending: Hashable, Sendable {
        public let scheduled: Scheduled
        public let message: Message
    }

    /// What to do with the reminder waiting in macOS.
    enum PendingAction: Hashable, Sendable {
        /// Schedule this one (replacing any other).
        case schedule(Pending)
        /// Nothing should be waiting.
        case cancel
        /// Today's reminder time has passed and it still applies: don't touch it. macOS may not
        /// have delivered it yet (the Mac slept through the time, or delivery runs a moment
        /// late), and cancelling it now would lose it (Phase 8 review).
        case leave
    }

    /// What should be true in the notification center now.
    struct Plan: Hashable, Sendable {
        public let pending: PendingAction
        /// What to remember on this Mac.
        public let record: Scheduled?
        /// Today's reminder already fired and still applies, so it stays in Notification Center.
        /// Otherwise a delivered one is removed (its habits were done or rested, or it's from an
        /// earlier day).
        public let keepsDelivered: Bool
    }

    /// The plan for `now`.
    /// - Parameters:
    ///   - items: what qualifies today (`items(_:name:)`).
    ///   - isEnabled: the Settings toggle.
    ///   - canNotify: macOS allows 66 Days to notify.
    ///   - fireDate: today's reminder time (`fireDate(on:hour:minute:dayEnd:)`).
    ///   - last: the reminder handed to macOS last time (`Plan.record`).
    static func plan(items: [Item], isEnabled: Bool, canNotify: Bool, today: DayKey, now: Date, fireDate: Date,
                     last: Scheduled?) -> Plan {
        // A reminder whose time has passed has fired (macOS delivers it even if 66 Days quit).
        let fired = last.flatMap { $0.fireDate <= now ? $0 : nil }
        let firedToday = fired?.day == today
        let applies = isEnabled && canNotify && !items.isEmpty
        if applies, firedToday {
            return Plan(pending: .leave, record: fired, keepsDelivered: true)
        }
        guard applies, fireDate > now, let message = message(for: items) else {
            return Plan(pending: .cancel, record: fired, keepsDelivered: false)
        }
        let scheduled = Scheduled(day: today, fireDate: fireDate)
        return Plan(pending: .schedule(Pending(scheduled: scheduled, message: message)), record: scheduled,
                    keepsDelivered: false)
    }

    /// The hours Settings offers for the reminder: noon through the last hour of the day, so every
    /// choice is a real "tonight" that can fire (user's choice after the Phase 8 review). With a
    /// midnight day end: 12pm–11pm; with a 2am day end: 12pm–1am. A stored hour outside that
    /// (the day end changed later) is kept in the list, in day order, so it still shows.
    static func reminderHours(dayEndHour: Int, including stored: Int) -> [Int] {
        let hours = Array(12...23) + Array(0..<dayEndHour)
        guard !hours.contains(stored) else { return hours }
        // Day order: hours from the day end onwards come before noon.
        let position = { (hour: Int) in (hour - dayEndHour + 24) % 24 }
        return (hours + [stored]).sorted { position($0) < position($1) }
    }

    /// The in-app prompt ("Want a gentle reminder tonight so you don't miss twice?") shows the
    /// first time it would be useful: a habit qualifies today, the reminder is on, macOS hasn't
    /// been asked yet, and tonight's reminder time is still ahead (decided in the Phase 8 build:
    /// "tonight" must be true; after the time it waits for the next miss).
    static func showsPrompt(anyQualifies: Bool, isEnabled: Bool, permissionUndecided: Bool, now: Date,
                            fireDate: Date) -> Bool {
        anyQualifies && isEnabled && permissionUndecided && now < fireDate
    }
}
