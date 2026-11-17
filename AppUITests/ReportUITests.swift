import AppKit
import XCTest

/// Letters and suggestions in the real app (build plan Phase 6): the envelope on the note opens
/// its letter, answers save, Done files it; the day-66 letter arrives with the 66th check-off
/// and its decision graduates the habit; a suggestion is accepted from a habit's page.
///
/// All on Saturday Nov 14, 2026, with letters delivered as the seeded days passed
/// (`DebugData.Scenario.letters` / `.day66` in the app).
final class ReportUITests: NoteUITestCase {
    /// Seed "letters": Read since Oct 4; the Nov 8 letter (Nov 1–7) is in the envelope, and the
    /// Nov 1 letter has an obstacle answer.
    @MainActor func testTheEnvelopeOpensTheLetterAndDoneFilesIt() {
        launch(seed: "letters", reports: true)
        let envelope = app.buttons["note.envelope"]
        XCTAssertTrue(envelope.waitForExistence(timeout: 5), "A letter is waiting")
        clickAtScreenPoint(of: envelope)

        XCTAssertTrue(wait { self.text("letter.title") == "Your week, Nov 1–7" }, "Straight into the letter")
        XCTAssertTrue(tab("reports").isSelected)
        XCTAssertTrue(wait { !envelope.exists }, "Opening it takes the envelope off the note")
        XCTAssertTrue(app.descendants(matching: .any)["letter.previousObstacle"].exists, "Last week's answer comes back")

        // "Keep the same" copies last week's answer, and it's saved.
        scrollTo(app.buttons["letter.keepSame"]).click()
        let field = app.descendants(matching: .any)["letter.field.obstacle"]
        XCTAssertTrue(wait { (field.value as? String) == "Late meetings. Read at lunch instead." })

        // Typed text is kept when the letter is filed. (The Phase 6 review's "Done within 600 ms
        // of typing" case can't be reproduced here: XCUITest is slower than that; the field now
        // saves every change.)
        field.click()
        app.typeText(" Or before work.")
        app.typeKey(.downArrow, modifierFlags: .command)
        XCTAssertTrue(tab("reports").isSelected, "Arrows in a field move the cursor, not the tab")
        scrollTo(app.buttons["letter.done"]).click()
        XCTAssertTrue(app.descendants(matching: .any)["reports"].waitForExistence(timeout: 5), "Back to the list")
        // Filed: opened again, it's read-only with the answer.
        let letter = app.buttons.matching(identifier: "reports.letter").firstMatch
        XCTAssertTrue(letter.waitForExistence(timeout: 5), "The archive lists its letters")
        letter.click()
        XCTAssertTrue(wait { self.text("letter.answer.obstacle") == "Late meetings. Read at lunch instead. Or before work." })
        XCTAssertFalse(app.buttons["letter.done"].exists)
    }

    /// Seed "day66": Walk has 65 done days; checking it off today brings the day-66 letter.
    @MainActor func testTheDay66LetterArrivesAndGraduates() {
        launch(seed: "day66", reports: true)
        clickAtScreenPoint(of: app.buttons["leaf.Walk"])
        let envelope = app.buttons["note.envelope"]
        XCTAssertTrue(wait { envelope.exists && envelope.label.contains("Day 66: Walk") }, "The day-66 letter arrived")
        clickAtScreenPoint(of: envelope)
        XCTAssertTrue(wait { self.text("letter.title") == "Day 66: Walk" })

        scrollTo(app.buttons["letter.automaticity.5"]).click()
        XCTAssertTrue(wait { self.text("letter.recommendation").hasPrefix("That sounds automatic.") })
        scrollTo(app.buttons["letter.decide.graduate"]).click()
        XCTAssertTrue(wait { self.text("letter.decision") == "You chose: Graduate ✓66." })
        XCTAssertFalse(app.buttons["letter.decide.keepGoing"].exists, "One decision per letter")

        tab("habits").click()
        XCTAssertTrue(wait { self.text("habit.inactive").hasPrefix("Graduated ✓66") }, "Walk graduated")
    }

    /// Seed "notebook": Read (10 pages) has done 13 of its last 14 days, its miss recovered.
    @MainActor func testAcceptASuggestionOnTheHabitPage() {
        launch(seed: "notebook")
        expandWithButton()
        tab("habits").click()
        let row = app.buttons["habits.row.Read"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let accept = scrollTo(app.buttons["suggestion.accept"])
        XCTAssertEqual(text("suggestion.change"), "11 pages instead of 10, from today.")
        accept.click()
        XCTAssertTrue(wait { self.text("habit.detail").hasPrefix("11 pages") }, "The new target, from today")
        XCTAssertFalse(app.buttons["suggestion.accept"].exists, "No suggestion right after a change")
    }

    /// Scrolls the notebook's page down until `element` can be clicked.
    @MainActor @discardableResult
    private func scrollTo(_ element: XCUIElement) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        // Scrolled at a point in the page's left margin: a text field being edited has its own
        // scroll view, which would take the scroll if it were under the pointer.
        let margin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 14, dy: 300))
        for _ in 0..<12 where !element.isHittable {
            margin.scroll(byDeltaX: 0, deltaY: -150)
        }
        XCTAssertTrue(element.isHittable, "\(element.identifier) is on screen")
        return element
    }
}
