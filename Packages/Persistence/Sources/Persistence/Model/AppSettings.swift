import Core

/// Settings that belong to the user's data and will sync between their devices later
/// (spec-settings.md). Device-only things (note position, the global shortcut, the
/// notification-prompt answer) live in UserDefaults in the app, not here.
public struct AppSettings: Hashable, Sendable {
    public enum ReduceMotion: String, CaseIterable, Hashable, Sendable, Codable {
        case matchSystem, on, off
    }

    public enum Appearance: String, CaseIterable, Hashable, Sendable, Codable {
        case light, dark, matchSystem
    }

    /// "My day ends at" in effect: 0 (midnight) through 4am.
    public var dayEndHour: Int = 0
    /// A newly chosen hour that starts with the next day (`DayEnd`). Change the setting with
    /// `Repository.setDayEndHour`, which applies that rule.
    public var dayEndChange: DayEnd.Change?
    /// Weekly report day and time (default Sunday 6pm).
    public var report = ReportSettings()
    /// The never-miss-twice reminder (default on, 8pm).
    public var reminderEnabled = true
    public var reminderHour = 20
    public var reminderMinute = 0
    public var soundsEnabled = true
    public var reduceMotion: ReduceMotion = .matchSystem
    /// Default light (decided 2026-11-10); only offered once Dark mode is unlocked.
    public var appearance: Appearance = .light

    public init() {}

    /// Turns moments into days with the day-end time, including a change that starts tomorrow.
    public var dayEnd: DayEnd {
        get { DayEnd(hour: dayEndHour, change: dayEndChange) }
        set {
            dayEndHour = newValue.hour
            dayEndChange = newValue.change
        }
    }

    /// Whether every value is in range.
    public var isValid: Bool {
        DayClock.allowedDayEndHours.contains(dayEndHour)
            && dayEndChange.map { DayClock.allowedDayEndHours.contains($0.hour) } ?? true
            && (0...23).contains(report.hour) && (0...59).contains(report.minute)
            && (0...23).contains(reminderHour) && (0...59).contains(reminderMinute)
    }
}
