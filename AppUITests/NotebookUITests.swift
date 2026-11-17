import AppKit
import XCTest

/// The notebook's key flows in the real app (build plan Phase 5): tabs and arrow keys, the
/// Calendar's day card, the Habits tab (edit, move to inactive and reactivate, delete and undo),
/// Settings, and the routes into it from the menu and the note.
///
/// Every run starts from the "notebook" seed on Saturday Nov 14, 2026
/// (`DebugData.Scenario.notebook` in the app):
/// - Read (10 pages, daily, from Oct 25): done every day but Nov 8 (recovered Nov 9), open today.
/// - Walk (yes/no, daily, from Oct 25): done every day, open today.
/// - Stretch (yes/no): paused on Oct 30.
///
/// The notebook is an ordinary window and 66 Days is in front while it's open, so plain XCUITest
/// clicks and typing work here (unlike on the desktop-level note).
final class NotebookUITests: NoteUITestCase {
    @MainActor func testTabsArrowKeysAndReopeningAtTheLastTab() {
        launch(seed: "notebook")
        expandWithButton()
        XCTAssertTrue(app.staticTexts["calendar.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab("calendar").isSelected, "Opens at the Calendar the first time")

        tab("habits").click()
        XCTAssertTrue(wait { self.tab("habits").isSelected })
        XCTAssertTrue(app.staticTexts["habit.name"].waitForExistence(timeout: 5))

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(wait { self.tab("reports").isSelected }, "Down arrow: the next tab")
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(wait { self.tab("habits").isSelected }, "Up arrow: the previous tab")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel }, "Esc collapses")
        expandWithButton()
        XCTAssertTrue(wait { self.tab("habits").isSelected }, "Reopens to the last tab")
    }

    @MainActor func testBackfillFromTheCalendarsDayCard() {
        launch(seed: "notebook")
        expandWithButton()
        let yesterday = app.buttons["calendar.day.2026-11-13"]
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        let settingsTab = tab("settings").frame
        yesterday.click()
        let leaf = app.buttons["dayCard.leaf.Walk"]
        XCTAssertTrue(leaf.waitForExistence(timeout: 5), "The day card opened")
        XCTAssertEqual(leaf.value as? String, "Done")
        leaf.click()
        XCTAssertTrue(wait { (leaf.value as? String) == "Missed" }, "Unchecked yesterday from the calendar")
        // While a card is open, the tabs wait too (Phase 5 review).
        // Clicked where it is on screen: the modal card hides the tabs from accessibility, but a
        // mouse click could still reach them.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: settingsTab.midX - window.frame.minX, dy: settingsTab.midY - window.frame.minY))
            .click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(leaf.exists, "The card stays open")
        app.buttons["Close"].click()
        XCTAssertTrue(wait { !leaf.exists }, "The card closed")
        XCTAssertTrue(wait { self.isExpanded }, "Closing the card leaves the notebook open")
        XCTAssertTrue(tab("calendar").isSelected, "The click on Settings under the card did nothing")
        XCTAssertTrue(tab("settings").isEnabled, "and the tabs work again")
    }

    @MainActor func testEditAHabit() {
        launch(seed: "notebook")
        openHabit("Walk")
        app.buttons["habit.edit"].click()
        let name = app.textFields["editForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Walk outside")
        app.buttons["form.save"].click()
        XCTAssertTrue(wait { self.text("habit.name") == "Walk outside" })
        XCTAssertTrue(app.buttons["habits.row.Walk outside"].exists, "The list follows")
    }

    @MainActor func testMoveToInactiveThenReactivate() {
        launch(seed: "notebook")
        openHabit("Walk")
        app.descendants(matching: .any)["habit.more"].firstMatch.click()
        app.menuItems["Move to Inactive"].click()
        let inactive = app.staticTexts["habit.inactive"]
        XCTAssertTrue(inactive.waitForExistence(timeout: 5))
        XCTAssertEqual(text("habit.inactive"), "Paused since Nov 14")
        XCTAssertFalse(app.buttons["habit.edit"].exists, "Inactive habits are read-only")

        app.buttons["habit.reactivate"].click()
        XCTAssertTrue(app.buttons["habit.edit"].waitForExistence(timeout: 5), "Active again")
        XCTAssertFalse(app.staticTexts["habit.inactive"].exists)
    }

    @MainActor func testDeleteAndUndo() {
        launch(seed: "notebook")
        openHabit("Walk")
        app.descendants(matching: .any)["habit.more"].firstMatch.click()
        app.menuItems["Delete…"].click()
        let delete = app.buttons["deleteCard.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Asks first")
        delete.click()
        XCTAssertTrue(wait { !self.app.buttons["habits.row.Walk"].exists }, "Deleted")

        let undo = app.buttons["notebook.undoDelete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Undo is offered")
        undo.click()
        XCTAssertTrue(app.buttons["habits.row.Walk"].waitForExistence(timeout: 5), "Undo brings it back")
        XCTAssertTrue(wait { self.text("habit.name") == "Walk" }, "and shows it")
    }

    @MainActor func testSettingsFromTheMenuAndAnInstantSave() {
        launch(seed: "notebook")
        app.activate()
        app.menuBars.menuBarItems["66 Days"].click()
        app.menuBars.menuItems["Settings…"].click()
        XCTAssertTrue(wait { self.isExpanded }, "Settings… opens the notebook")
        XCTAssertTrue(wait { self.tab("settings").isSelected }, "at Settings")

        let twoAM = app.buttons["settings.dayEnd.2am"]
        XCTAssertTrue(twoAM.waitForExistence(timeout: 5))
        XCTAssertFalse(twoAM.isSelected)
        twoAM.click()
        XCTAssertTrue(wait { twoAM.isSelected }, "Saved instantly")
        XCTAssertTrue(app.buttons["settings.dayEnd.Midnight"].exists)
        XCTAssertFalse(app.buttons["settings.dayEnd.Midnight"].isSelected)
    }

    // MARK: Helpers

    @MainActor private var isExpanded: Bool { (try? noteWindow().frame.size) == expandedSize }

    /// A text's words: SwiftUI exposes them as the value or (for some texts, such as headers) the label.
    @MainActor private func text(_ identifier: String) -> String {
        let element = app.staticTexts[identifier]
        guard element.exists else { return "" }
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    @MainActor private func tab(_ name: String) -> XCUIElement { app.buttons["tab.\(name)"] }

    @MainActor private func openHabit(_ name: String) {
        expandWithButton()
        tab("habits").click()
        let row = app.buttons["habits.row.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(wait { self.text("habit.name") == name }, "\(name)'s page")
    }
}
