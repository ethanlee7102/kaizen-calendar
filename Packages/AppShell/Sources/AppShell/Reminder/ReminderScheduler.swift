import Foundation
import Observation
import os

/// Keeps macOS's notification center matching what the app wants: the one never-miss-twice
/// reminder waiting (or none), a fired one kept or removed, and the permission as macOS has it
/// (spec-notifications.md). The rules for what to want are Core's `NeverMissTwiceReminder.plan`.
///
/// Calls to the center run one after another in the order made, so a quick check-off and
/// uncheck can never leave the older answer in place.
@Observable
public final class ReminderScheduler {
    /// Nil until it has been read once.
    public private(set) var permission: NotificationPermission?
    /// The system dialog is up (after "Yes, remind me").
    public private(set) var isAskingPermission = false

    @ObservationIgnored public let center: ReminderCenter
    @ObservationIgnored private var applied: Applied?
    @ObservationIgnored private var queue: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.ethanlee7102.66days", category: "reminder")

    /// What to do with the reminder waiting in macOS.
    public enum PendingChange: Equatable, Sendable {
        case schedule(ReminderRequest)
        case cancel
        /// Don't touch it: its time has passed and it still applies, but macOS may not have
        /// delivered it yet (Phase 8 review).
        case leave
    }

    private struct Applied: Equatable {
        let pending: PendingChange
        let keepsDelivered: Bool
    }

    public init(center: ReminderCenter) {
        self.center = center
    }

    /// Reads the permission again (the user can change it in System Settings at any time).
    public func refreshPermission() {
        enqueue { [center] in
            let current = await center.permission()
            if self.permission != current { self.permission = current }
        }
    }

    /// Shows macOS's permission dialog if it was never shown, then reads the answer. Not on the
    /// queue: the dialog waits for the user, and scheduling mustn't wait with it (Phase 8 review).
    public func requestPermission() {
        guard !isAskingPermission else { return }
        isAskingPermission = true
        Task { [center] in
            if await center.permission() == .notDetermined { _ = await center.requestPermission() }
            // The answer first, then the flag: otherwise the prompt could flash back for a moment.
            let current = await center.permission()
            if self.permission != current { self.permission = current }
            self.isAskingPermission = false
        }
    }

    /// `pending`: what to do with the waiting reminder. `keepsDelivered`: a reminder that already
    /// fired today still applies; otherwise it's removed from Notification Center.
    public func apply(pending: PendingChange, keepsDelivered: Bool) {
        let wanted = Applied(pending: pending, keepsDelivered: keepsDelivered)
        guard wanted != applied else { return }
        applied = wanted
        enqueue { [center] in
            switch pending {
            case .schedule(let request):
                do {
                    try await center.schedule(request)
                } catch {
                    Self.log.error("Couldn't schedule the reminder: \(String(describing: error), privacy: .public)")
                    // Try again with the next change.
                    if self.applied == wanted { self.applied = nil }
                }
            case .cancel:
                center.removePending()
            case .leave:
                break
            }
            if !keepsDelivered { center.removeDelivered() }
        }
    }

    /// Waits for every call made so far (tests).
    public func settled() async {
        await queue?.value
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }
}
