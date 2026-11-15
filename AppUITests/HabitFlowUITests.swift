import AppKit
import XCTest

/// The note's key flows in the real app (build plan Phase 4): add a habit, check off and uncheck,
/// recover a danger day, backfill within 2 days, "Change anyway" on an older day, rest today (and
/// not on a danger day), and the daily note.
///
/// Every run starts from the same data on the same day: the "flows" seed on Saturday
/// Nov 14, 2026 (`DebugData.Scenario.flows` in the app):
/// - Read (10 pages, daily): done every day but Nov 9 (recovered on Nov 10) and yesterday, Nov 13,
///   so today is a danger day.
/// - Walk (yes/no, daily): done every day, open today.
///
/// Clicks go to screen points (`clickAtScreenPoint`): XCUITest's hittability check is fooled by
/// the desktop layer the note lives on.
final class HabitFlowUITests: NoteUITestCase {
    @MainActor func testAddAHabit() {
        launch()
        click("note.addHabit")
        XCTAssertTrue(app.descendants(matching: .any)["habitForm"].waitForExistence(timeout: 5), "The form opened")
        type("Read", into: app.textFields["habitForm.name"])
        type("10", into: app.textFields["habitForm.target"])
        let add = app.buttons["habitForm.add"]
        XCTAssertFalse(add.isEnabled, "A target needs its unit too")
        type("pages", into: app.textFields["habitForm.unit"])
        XCTAssertTrue(wait { add.isEnabled })
        clickAtScreenPoint(of: add)

        let row = app.buttons["row.Read.name"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("10 pages · starts today"), row.label)
        XCTAssertFalse(app.descendants(matching: .any)["habitForm"].exists, "The form closed")
    }

    @MainActor func testCheckOffAndUncheckToday() {
        launch(seed: "flows")
        let walk = app.buttons["leaf.Walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        XCTAssertEqual(walk.value as? String, "not done")
        XCTAssertTrue(todayLine.contains("0 of 2 done"), todayLine)

        clickAtScreenPoint(of: walk)
        XCTAssertTrue(wait { (walk.value as? String) == "done" })
        XCTAssertTrue(wait { self.todayLine.contains("1 of 2 done") }, todayLine)

        clickAtScreenPoint(of: walk)
        XCTAssertTrue(wait { (walk.value as? String) == "not done" }, "Clicking a checked leaf unchecks it")
        XCTAssertTrue(wait { self.todayLine.contains("0 of 2 done") }, todayLine)
    }

    @MainActor func testCheckingOffOnADangerDayRecovers() {
        launch(seed: "flows")
        let row = app.buttons["row.Read.name"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Never miss twice. Today counts."), row.label)
        clickAtScreenPoint(of: app.buttons["leaf.Read"])
        XCTAssertTrue(wait { row.label.contains("Recovered. You didn’t miss twice.") }, row.label)
    }

    @MainActor func testBackfillYesterday() {
        launch(seed: "flows")
        click("day.2026-11-13")
        let read = app.buttons["dayCard.leaf.Read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertEqual(read.value as? String, "Missed")
        XCTAssertTrue(read.isEnabled, "Yesterday is editable")
        clickAtScreenPoint(of: read)
        XCTAssertTrue(wait { (read.value as? String) == "Done" })

        closeCard()
        let row = app.buttons["row.Read.name"]
        XCTAssertTrue(wait { !row.label.contains("Never miss twice") }, "No longer a danger day: \(row.label)")
    }

    @MainActor func testChangeAnywayOnAnOlderDay() {
        launch(seed: "flows")
        click("day.2026-11-09")
        let read = app.buttons["dayCard.leaf.Read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertEqual(read.value as? String, "Missed, then recovered")
        XCTAssertFalse(read.isEnabled, "5 days ago is read-only")

        click("dayCard.changeAnyway")
        click("dayCard.confirmChange")
        XCTAssertTrue(wait { read.isEnabled }, "Unlocked after confirming")
        clickAtScreenPoint(of: read)
        XCTAssertTrue(wait { (read.value as? String) == "Done" })
    }

    @MainActor func testRestTodayButNotOnADangerDay() {
        launch(seed: "flows")
        click("day.\(Self.today)")
        let rest = app.buttons["dayCard.rest.Walk"]
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dayCard.rest.Read"].exists, "Read missed yesterday: today must be done, not rested")

        clickAtScreenPoint(of: rest)
        XCTAssertTrue(wait { rest.label == "Undo rest" }, rest.label)
        XCTAssertEqual(app.buttons["dayCard.leaf.Walk"].value as? String, "Rest day")

        closeCard()
        let row = app.buttons["row.Walk.name"]
        XCTAssertTrue(wait { row.label.contains("Rest day. Streak paused.") }, row.label)
        XCTAssertTrue(todayLine.contains("0 of 1 done"), "A rested habit doesn't count: \(todayLine)")
    }

    @MainActor func testDailyNoteAfterEverythingIsDone() {
        launch(seed: "flows")
        let note = app.textFields["note.dailyNote"]
        XCTAssertFalse(note.exists, "Only once everything today is done")
        clickAtScreenPoint(of: app.buttons["leaf.Walk"])
        clickAtScreenPoint(of: app.buttons["leaf.Read"])
        XCTAssertTrue(wait { self.todayLine.contains("All done") }, todayLine)
        XCTAssertTrue(note.waitForExistence(timeout: 5))

        type("Walk after lunch\r", into: note)
        click("day.\(Self.today)")
        let cardNote = app.textFields["dayCard.note"]
        XCTAssertTrue(cardNote.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { (cardNote.value as? String) == "Walk after lunch" }, "The same note as in today's card")
    }

    /// Phase 4 review: opening the form from the note while another app is in front left the
    /// keyboard with that app (and the name field never got focus), so typing went there. Checks
    /// that the field gets keyboard focus while Calculator stays in front. Actually typing and
    /// Esc are a hand check: keys synthesized into a background app's process arrive unreliably.
    @MainActor func testTheFormTakesTheKeyboardWhileAnotherAppIsInFront() {
        launch(seed: "flows")
        bringAnotherAppToFront()
        clickAtScreenPoint(of: app.buttons["note.addHabit"], from: otherApp.windows.firstMatch)
        let name = app.textFields["habitForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { (name.value(forKey: "hasKeyboardFocus") as? Bool) == true }, "The name field has the keyboard")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5)) // a late activation would show by now
        XCTAssertTrue(anotherAppIsInFront(), "Without bringing 66 Days to the front")
    }

    // MARK: Helpers

    @MainActor private var todayLine: String { app.descendants(matching: .any)["note.today"].label }

    @MainActor private func click(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(identifier) exists")
        clickAtScreenPoint(of: element)
    }

    @MainActor private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(field) exists")
        clickAtScreenPoint(of: field)
        app.typeText(text)
    }

    @MainActor private func closeCard() {
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        clickAtScreenPoint(of: close)
        XCTAssertTrue(wait { !close.exists }, "The card closed")
    }
}
