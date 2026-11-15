import AppKit
import Foundation
import Testing
@testable import AppShell

@Suite struct NoteWindowModeTests {
    /// The LOCKED configuration from the desktop-window prototype (desktop-window-findings.md).
    @Test func collapsedIsADesktopLevelNoteOnOneDesktop() {
        let mode = NoteWindowMode.collapsed
        #expect(mode.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        #expect(mode.collectionBehavior == [.stationary, .ignoresCycle])
        #expect(!mode.collectionBehavior.contains(.canJoinAllSpaces)) // caused the full-screen blink
    }

    @Test func expandedIsANormalWindowThatStaysOffFullScreenApps() {
        let mode = NoteWindowMode.expanded
        #expect(mode.level == .normal)
        #expect(mode.collectionBehavior == [.managed, .fullScreenNone])
    }
}

@Suite struct DayChangeMonitorTests {
    @Test(arguments: [
        (NSWorkspace.didWakeNotification, true),
        (Notification.Name.NSSystemClockDidChange, false),
        (Notification.Name.NSSystemTimeZoneDidChange, false),
        (Notification.Name.NSCalendarDayChanged, false),
    ])
    func refreshesOnSystemEvents(name: Notification.Name, fromWorkspace: Bool) {
        let system = NotificationCenter(), workspace = NotificationCenter()
        var changes = 0
        let monitor = DayChangeMonitor(
            notificationCenter: system, workspaceNotificationCenter: workspace,
            nextChange: { Date().addingTimeInterval(3600) }, onChange: { changes += 1 })
        monitor.start()
        defer { monitor.stop() }
        (fromWorkspace ? workspace : system).post(name: name, object: nil)
        #expect(changes == 1)
    }

    @Test func ignoresEventsAfterStopping() {
        let system = NotificationCenter()
        var changes = 0
        let monitor = DayChangeMonitor(
            notificationCenter: system, workspaceNotificationCenter: NotificationCenter(),
            nextChange: { Date().addingTimeInterval(3600) }, onChange: { changes += 1 })
        monitor.start()
        monitor.stop()
        system.post(name: .NSSystemClockDidChange, object: nil)
        #expect(changes == 0)
    }

    @Test func firesAtTheDayBoundary() async {
        // The boundary is already here; the timer fires after its safety margin.
        await confirmation(expectedCount: 1) { fired in
            let monitor = DayChangeMonitor(
                notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                nextChange: { Date() }, onChange: { fired() })
            monitor.start()
            try? await Task.sleep(for: .seconds(DayChangeMonitor.margin + 0.5))
            monitor.stop()
        }
    }

    @Test func doesNotFireBeforeTheBoundary() async {
        await confirmation(expectedCount: 0) { fired in
            let monitor = DayChangeMonitor(
                notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                nextChange: { Date().addingTimeInterval(60) }, onChange: { fired() })
            monitor.start()
            try? await Task.sleep(for: .seconds(DayChangeMonitor.margin + 0.5))
            monitor.stop()
        }
    }
}
