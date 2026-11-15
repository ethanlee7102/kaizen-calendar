import AppKit

/// Tells the app when "today" may have changed: at the next day boundary, after the Mac wakes,
/// and when the clock, time zone or calendar day changes (build plan, Phase 3).
///
/// The app answers with `AppModel.refreshToday()`. `nextChange` says when the current day ends
/// (`DayClock.end(of: today)`, which includes the day-end time); call `reschedule()` when that
/// answer changes for another reason, such as a new day-end setting.
public final class DayChangeMonitor {
    private let nextChange: () -> Date
    private let onChange: () -> Void
    private let now: () -> Date
    private let centers: (system: NotificationCenter, workspace: NotificationCenter)
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Task<Void, Never>?

    /// The timer fires this long after the boundary, so a slightly early wake-up never lands on
    /// the old day.
    static let margin: TimeInterval = 1

    public init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping () -> Date = Date.init,
        nextChange: @escaping () -> Date,
        onChange: @escaping () -> Void
    ) {
        centers = (notificationCenter, workspaceNotificationCenter)
        self.now = now
        self.nextChange = nextChange
        self.onChange = onChange
    }

    /// Starts listening and schedules the first boundary.
    public func start() {
        guard observers.isEmpty else { return }
        on(NSWorkspace.didWakeNotification, in: centers.workspace)
        on(.NSSystemClockDidChange, in: centers.system)
        on(.NSSystemTimeZoneDidChange, in: centers.system)
        on(.NSCalendarDayChanged, in: centers.system)
        reschedule()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    /// Schedules the timer for the next boundary. The sleep runs on the continuous clock, which
    /// keeps counting while the Mac sleeps; wake and clock changes reschedule it anyway.
    public func reschedule() {
        timer?.cancel()
        let delay = max(nextChange().timeIntervalSince(now()), 0) + Self.margin
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.changed()
        }
    }

    private func changed() {
        onChange()
        reschedule()
    }

    private func on(_ name: Notification.Name, in center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        observers.append((center, token))
    }
}
