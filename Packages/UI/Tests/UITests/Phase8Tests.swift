import Core
import Foundation
import Testing
@testable import UI

/// The never-miss-twice reminder's Settings row and its click (Phase 8).
@Suite struct ReminderUITests {
    @Test func blockedOnlyMattersWhileTheReminderIsOn() {
        var values = SettingsValues()
        values.reminderAccess = .blocked
        #expect(values.reminderBlocked)
        #expect(values.reminderCaption.hasPrefix("Notifications for 66 Days are off in System Settings"))
        values.reminderEnabled = false
        #expect(!values.reminderBlocked)
        #expect(values.reminderCaption == "One notification, only on the day after a miss, if that habit isn’t done yet.")
        values.reminderEnabled = true
        values.reminderAccess = .notAsked
        #expect(!values.reminderBlocked)
    }

    @Test func showTodayOnlyAsksAndTheNotebookOpensTheCalendarAtTodaysMonth() {
        let navigation = NotebookNavigation(defaults: nil, tab: .habits)
        navigation.calendarMode = .year
        navigation.calendarMonth = DayKey("2026-09-01")
        navigation.showToday()
        // Nothing moves until the notebook handles it (a form there keeps its page).
        #expect(navigation.tab == .habits)
        #expect(navigation.todayCardRequested)
        navigation.openToday()
        #expect(navigation.tab == .calendar)
        #expect(navigation.calendarMode == .month)
        #expect(navigation.calendarMonth == nil)
    }
}
