import AppKit
import UserNotifications

/// Whether macOS lets 66 Days show notifications.
public enum NotificationPermission: Sendable, Equatable {
    /// Never asked: the system dialog can still be shown.
    case notDetermined
    /// Turned off (in the dialog or in System Settings). Only System Settings can change it now.
    case denied
    case allowed
}

/// One notification waiting to fire.
public struct ReminderRequest: Hashable, Sendable {
    public let title: String
    public let body: String
    public let date: Date

    public init(title: String, body: String, date: Date) {
        self.title = title
        self.body = body
        self.date = date
    }
}

/// What 66 Days needs from macOS's notification center: one reminder, its permission, and the
/// click. A fake (`FakeReminderCenter`) stands in for UI tests and sample data, so they never
/// schedule real notifications or ask for permission.
public protocol ReminderCenter: AnyObject {
    /// The reminder was clicked.
    var onOpen: (() -> Void)? { get set }
    func permission() async -> NotificationPermission
    /// Shows macOS's permission dialog (only while `.notDetermined`). True if allowed.
    func requestPermission() async -> Bool
    /// Replaces the waiting reminder (there's only ever one).
    func schedule(_ request: ReminderRequest) async throws
    func removePending()
    /// Removes a reminder that already fired from Notification Center.
    func removeDelivered()
}

/// macOS's notification center (UserNotifications).
public final class SystemReminderCenter: NSObject, ReminderCenter, UNUserNotificationCenterDelegate {
    public var onOpen: (() -> Void)?

    /// The one reminder's identifier: scheduling again replaces it.
    nonisolated static let identifier = "neverMissTwice"

    private var center: UNUserNotificationCenter { .current() }

    /// Becomes the notification center's delegate at once, so a click that launched the app is
    /// still delivered.
    override public init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    public func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed // authorized, provisional, ephemeral
        }
    }

    public func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func schedule(_ request: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    public func removePending() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    public func removeDelivered() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    /// Opens Notifications › 66 Days in System Settings (after "Don't Allow", only there can it
    /// be turned on).
    public static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown as a banner even while 66 Days is the active app.
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                                   willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                                   didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.identifier,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { onOpen?() }
    }
}

/// Stands in for macOS's notification center (UI tests, sample data): remembers what would be
/// scheduled and answers the permission dialog with `grants`.
public final class FakeReminderCenter: ReminderCenter {
    public var onOpen: (() -> Void)?
    public var currentPermission: NotificationPermission
    /// The answer to the (pretend) system dialog.
    public var grants: Bool
    public private(set) var pending: ReminderRequest?
    public private(set) var delivered = false
    public private(set) var permissionRequests = 0

    public init(permission: NotificationPermission, grants: Bool = true) {
        currentPermission = permission
        self.grants = grants
    }

    public func permission() async -> NotificationPermission { currentPermission }

    public func requestPermission() async -> Bool {
        permissionRequests += 1
        if currentPermission == .notDetermined { currentPermission = grants ? .allowed : .denied }
        return currentPermission == .allowed
    }

    public func schedule(_ request: ReminderRequest) async throws { pending = request }
    public func removePending() { pending = nil }
    public func removeDelivered() { delivered = false }

    /// Pretends the waiting reminder fired.
    public func deliverPending() {
        guard pending != nil else { return }
        pending = nil
        delivered = true
    }
}
