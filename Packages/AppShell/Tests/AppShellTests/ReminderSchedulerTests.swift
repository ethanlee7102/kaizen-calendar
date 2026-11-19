import Foundation
import Testing
@testable import AppShell

/// Counts calls and can fail scheduling, to check what the scheduler sends to macOS.
private final class RecordingCenter: ReminderCenter {
    var onOpen: (() -> Void)?
    var currentPermission: NotificationPermission = .allowed
    var grants = true
    var failsToSchedule = false
    var log: [String] = []

    func permission() async -> NotificationPermission { currentPermission }
    func requestPermission() async -> Bool {
        log.append("request")
        currentPermission = grants ? .allowed : .denied
        return grants
    }
    func schedule(_ request: ReminderRequest) async throws {
        // Yield, so a later call would overtake this one if the scheduler didn't keep the order.
        await Task.yield()
        if failsToSchedule { throw CancellationError() }
        log.append("schedule \(request.title)")
    }
    func removePending() { log.append("removePending") }
    func removeDelivered() { log.append("removeDelivered") }
}

@Suite struct ReminderSchedulerTests {
    let read = ReminderRequest(title: "Read", body: "b", date: Date(timeIntervalSince1970: 1_000))
    let walk = ReminderRequest(title: "Walk", body: "b", date: Date(timeIntervalSince1970: 1_000))

    @Test func appliesInOrderAndSkipsRepeats() async {
        let center = RecordingCenter()
        let scheduler = ReminderScheduler(center: center)
        scheduler.apply(pending: .schedule(read), keepsDelivered: false)
        scheduler.apply(pending: .schedule(read), keepsDelivered: false) // no change: nothing sent
        scheduler.apply(pending: .cancel, keepsDelivered: false)
        scheduler.apply(pending: .schedule(walk), keepsDelivered: true)
        scheduler.apply(pending: .leave, keepsDelivered: true) // fired, still applies: untouched
        await scheduler.settled()
        #expect(center.log == ["schedule Read", "removeDelivered", "removePending", "removeDelivered", "schedule Walk"])
    }

    @Test func aFailedScheduleIsTriedAgain() async {
        let center = RecordingCenter()
        center.failsToSchedule = true
        let scheduler = ReminderScheduler(center: center)
        scheduler.apply(pending: .schedule(read), keepsDelivered: true)
        await scheduler.settled()
        center.failsToSchedule = false
        scheduler.apply(pending: .schedule(read), keepsDelivered: true)
        await scheduler.settled()
        #expect(center.log == ["schedule Read"])
    }

    @Test func permissionIsReadAndAskedOnlyOnce() async {
        let center = RecordingCenter()
        center.currentPermission = .notDetermined
        let scheduler = ReminderScheduler(center: center)
        #expect(scheduler.permission == nil)
        scheduler.refreshPermission()
        await scheduler.settled()
        #expect(scheduler.permission == .notDetermined)
        scheduler.requestPermission()
        #expect(scheduler.isAskingPermission)
        await waitUntil { scheduler.permission == .allowed }
        #expect(!scheduler.isAskingPermission)
        // Already decided: the dialog isn't shown again.
        scheduler.requestPermission()
        await waitUntil { !scheduler.isAskingPermission }
        #expect(center.log == ["request"])
    }

    /// Phase 8 review: the dialog waits for the user; scheduling meanwhile must not wait with it.
    @Test func schedulingDoesNotWaitForThePermissionDialog() async {
        let center = BlockingDialogCenter()
        let scheduler = ReminderScheduler(center: center)
        scheduler.requestPermission()
        await waitUntil { center.dialogShown }
        scheduler.apply(pending: .schedule(read), keepsDelivered: true)
        // Not `settled()`: if scheduling waited for the dialog, that would never return.
        await waitUntil { center.scheduled == ["Read"] }
        #expect(center.scheduled == ["Read"], "Scheduled while the dialog is still up")
        center.answer()
        await waitUntil { !scheduler.isAskingPermission }
    }

    @Test func fakeCenterAnswersTheDialog() async {
        let denying = FakeReminderCenter(permission: .notDetermined, grants: false)
        #expect(await denying.requestPermission() == false)
        #expect(await denying.permission() == .denied)
        let fake = FakeReminderCenter(permission: .allowed)
        try? await fake.schedule(read)
        #expect(fake.pending == read)
        fake.deliverPending()
        #expect(fake.pending == nil && fake.delivered)
    }
}

/// A dialog that stays up until `answer()`.
private final class BlockingDialogCenter: ReminderCenter {
    var onOpen: (() -> Void)?
    var dialogShown = false
    var scheduled: [String] = []
    private var continuation: CheckedContinuation<Bool, Never>?

    func permission() async -> NotificationPermission { .notDetermined }
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation = $0; dialogShown = true }
    }
    func answer() { continuation?.resume(returning: true) }
    func schedule(_ request: ReminderRequest) async throws { scheduled.append(request.title) }
    func removePending() {}
    func removeDelivered() {}
}

@MainActor private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}
