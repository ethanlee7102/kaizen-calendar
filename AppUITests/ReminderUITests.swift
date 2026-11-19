import AppKit
import XCTest

/// The never-miss-twice reminder (Phase 8, spec-notifications.md) with a pretend notification
/// center: the in-app prompt, its two answers, the Settings row when macOS blocks it, and what a
/// click on the reminder opens (Debug ▸ Click the Reminder: UI tests can't click a real one).
///
/// The "flows" seed: Read missed yesterday, so today (Sat Nov 14, at noon) is a danger day and
/// tonight's 8pm reminder is still ahead.
final class ReminderUITests: NoteUITestCase {
    @MainActor private var prompt: XCUIElement { app.descendants(matching: .any)["note.reminderPrompt"] }

    @MainActor func testThePromptShowsOnlyBeforeMacOSWasAsked() {
        launch(seed: "flows")
        XCTAssertTrue(app.buttons["row.Read.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(prompt.exists, "Already allowed: no prompt")
    }

    @MainActor func testYesAsksMacOSAndThePromptGoes() {
        launch(seed: "flows", notifications: "notDetermined")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "A danger day before 8pm, never asked: the prompt shows")
        clickAtScreenPoint(of: app.buttons["note.reminderYes"])
        XCTAssertTrue(wait { !self.prompt.exists }, "Answered")
        // Still on in Settings.
        expandWithButton()
        tab("settings").click()
        let toggle = app.descendants(matching: .any)["settings.reminder"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "on")
        XCTAssertFalse(app.buttons["settings.openNotificationSettings"].exists, "Allowed: nothing to fix")
    }

    @MainActor func testNoThanksTurnsTheReminderOff() {
        launch(seed: "flows", notifications: "notDetermined")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        clickAtScreenPoint(of: app.buttons["note.reminderNo"])
        XCTAssertTrue(wait { !self.prompt.exists }, "Answered")
        expandWithButton()
        tab("settings").click()
        let toggle = app.descendants(matching: .any)["settings.reminder"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { (toggle.value as? String) == "off" }, "No thanks turns it off in Settings")
    }

    @MainActor func testSettingsExplainsABlockedReminder() {
        launch(seed: "flows", notifications: "denied")
        XCTAssertTrue(app.buttons["row.Read.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(prompt.exists, "Blocked: the note doesn't ask")
        expandWithButton()
        tab("settings").click()
        XCTAssertTrue(app.buttons["settings.openNotificationSettings"].waitForExistence(timeout: 5))
        // Turned off, there's nothing to fix.
        let toggle = app.descendants(matching: .any)["settings.reminder"]
        toggle.click()
        XCTAssertTrue(wait { (toggle.value as? String) == "off" })
        XCTAssertFalse(app.buttons["settings.openNotificationSettings"].exists)
    }

    @MainActor func testAClickOpensTodaysDayCard() {
        launch(seed: "flows")
        clickTheReminder()
        XCTAssertTrue(wait { (try? self.noteWindow().frame.size) == self.expandedSize }, "The notebook opens")
        XCTAssertTrue(app.buttons["dayCard.leaf.Read"].waitForExistence(timeout: 5), "with today's card open")
        XCTAssertEqual(app.buttons["dayCard.leaf.Read"].value as? String, "Not yet")
        assertCalendarBehindTheCard()
    }

    /// A waiting letter usually opens the notebook at Reports; the reminder's click wins.
    @MainActor func testAClickWinsOverAWaitingLetter() {
        launch(seed: "letters", reports: true)
        XCTAssertTrue(app.buttons["note.envelope"].waitForExistence(timeout: 5), "A letter is waiting")
        clickTheReminder()
        XCTAssertTrue(app.buttons["dayCard.leaf.Read"].waitForExistence(timeout: 5), "Today's card")
        assertCalendarBehindTheCard()
    }

    /// An open card hides the tabs from accessibility: close it (Esc), then check the tab.
    @MainActor private func assertCalendarBehindTheCard() {
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wait { !self.app.buttons["dayCard.leaf.Read"].exists }, "Esc closes the card")
        XCTAssertTrue(wait { self.tab("calendar").isSelected }, "at the Calendar")
    }

    @MainActor private func clickTheReminder() {
        app.activate()
        let debug = app.menuBars.menuBarItems["Debug"]
        XCTAssertTrue(debug.waitForExistence(timeout: 5))
        debug.click()
        app.menuBars.menuItems["Click the Reminder"].click()
    }
}
