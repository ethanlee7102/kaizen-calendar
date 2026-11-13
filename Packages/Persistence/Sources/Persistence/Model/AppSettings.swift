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

    /// "My day ends at": 0 (midnight) through 4am.
    public var dayEndHour: Int = 0
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

    /// The clock that turns moments into days with this day-end time.
    public var dayClock: DayClock { DayClock(dayEndHour: dayEndHour) }

    /// Whether every value is in range.
    public var isValid: Bool {
        DayClock.allowedDayEndHours.contains(dayEndHour)
            && (0...23).contains(report.hour) && (0...59).contains(report.minute)
            && (0...23).contains(reminderHour) && (0...59).contains(reminderMinute)
    }
}
