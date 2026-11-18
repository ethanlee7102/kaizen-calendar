import AppKit
import XCTest

/// Onboarding and The Science in the real app (build plan Phase 7).
///
/// Onboarding tests start from the "onboarding" seed: an empty database that hasn't been through
/// onboarding (every other seed has). The Science test uses the "flows" seed, where Read missed
/// yesterday, so its row shows "Never miss twice. Today counts." with an info button.
final class OnboardingUITests: NoteUITestCase {
    @MainActor func testFirstLaunchWalksThroughOnboardingIntoTheNote() throws {
        launch(seed: "onboarding")
        XCTAssertTrue(wait { self.isExpanded }, "The first launch opens the notebook")
        let begin = app.buttons["onboarding.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5), "at the welcome page")
        XCTAssertFalse(tab("calendar").exists, "No notebook tabs during onboarding")

        // The example info button shows the pattern, without the Science-page link here.
        app.buttons["onboarding.why66"].click()
        XCTAssertTrue(element("info.why66").waitForExistence(timeout: 5), "The example i opens its explanation")
        XCTAssertFalse(app.buttons["info.more.why66"].exists, "No link out of onboarding")
        begin.click()

        // Page 2: the first habit (Next waits for one).
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "Next needs a habit")
        typeInto("habitForm.name", "Read")
        typeInto("habitForm.target", "10")
        typeInto("habitForm.unit", "pages")
        app.buttons["habitForm.add"].click()
        XCTAssertTrue(element("onboarding.habit.Read").waitForExistence(timeout: 5), "The habit is listed")
        XCTAssertTrue(app.buttons["onboarding.addAnother"].exists, "Add another, until three")
        XCTAssertTrue(wait { next.isEnabled })
        next.click()

        // Page 3: open at login (on by default) and the day end.
        let finish = app.buttons["onboarding.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertEqual(isOn("onboarding.openAtLogin"), true, "On by default")
        app.buttons["onboarding.dayEnd.2am"].click()
        finish.click()

        // Folds into the note, with the one-time hint.
        XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel }, "Finish folds into the note")
        XCTAssertTrue(app.buttons["row.Read.name"].waitForExistence(timeout: 5), "The habit is on the note")
        XCTAssertTrue(element("note.dragHint").waitForExistence(timeout: 5), "Drag me anywhere.")

        // Dragging the note retires the hint for good.
        try dragNote(toCorner: .bottomLeft, inset: 40)
        XCTAssertTrue(wait { !self.element("note.dragHint").exists }, "The first drag retires the hint")

        // From now on the notebook is the notebook, with the choices from page 3 applied.
        expandWithButton()
        XCTAssertTrue(tab("calendar").waitForExistence(timeout: 5), "The normal notebook after onboarding")
        tab("settings").click()
        XCTAssertEqual(isOn("settings.openAtLogin"), true, "Open at login was turned on")
        XCTAssertTrue(app.buttons["settings.dayEnd.2am"].isSelected, "The day end was set (from tomorrow)")
    }

    @MainActor func testLeavingOnboardingResumesItAndSkipFinishesIt() {
        launch(seed: "onboarding")
        let begin = app.buttons["onboarding.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.click()
        typeInto("habitForm.name", "Walk")
        app.buttons["Just do it"].click()
        app.buttons["habitForm.add"].click()
        XCTAssertTrue(element("onboarding.habit.Walk").waitForExistence(timeout: 5))

        // Esc folds it: the note works meanwhile, and no hint yet.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel }, "Esc collapses")
        XCTAssertTrue(app.buttons["row.Walk.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("note.dragHint").exists, "The hint waits for the end of onboarding")

        // Reopening comes back to onboarding, on page 2 with the habit listed.
        expandWithButton()
        XCTAssertTrue(element("onboarding.habit.Walk").waitForExistence(timeout: 5), "Resumes at the first habit")
        XCTAssertEqual(text("onboarding.position"), "Page 2 of 3")
        app.buttons["onboarding.next"].click()

        // Skip finishes it without turning on open at login.
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.click()
        XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel }, "Skip folds into the note")
        let dismiss = app.buttons["note.dismissDragHint"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "Drag me anywhere.")
        clickAtScreenPoint(of: dismiss)
        XCTAssertTrue(wait { !self.element("note.dragHint").exists }, "× retires the hint")

        expandWithButton()
        XCTAssertTrue(tab("settings").waitForExistence(timeout: 5), "Onboarding is done")
        tab("settings").click()
        XCTAssertEqual(isOn("settings.openAtLogin"), false, "Skip leaves open at login off")
    }

    /// An info box's "More on The Science page →" opens the notebook at that entry.
    @MainActor func testAnInfoButtonLeadsToItsEntryOnTheSciencePage() {
        launch(seed: "flows")
        let info = app.buttons["row.Read.info"]
        XCTAssertTrue(info.waitForExistence(timeout: 5), "The danger line has an info button")
        clickAtScreenPoint(of: info)
        let more = app.buttons["info.more.neverMissTwice"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "The info box opened with its link")
        clickAtScreenPoint(of: more)
        let clicked = Date()

        XCTAssertTrue(wait { self.isExpanded }, "The notebook opens")
        XCTAssertTrue(wait { self.tab("science").isSelected }, "at The Science")
        let entry = element("science.neverMissTwice")
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(wait { window.contains(CGPoint(x: entry.frame.midX, y: entry.frame.minY + 4)) },
                      "Scrolled to the entry: \(entry.frame) in \(window)")
        // Highlighted for a moment, not just a flash (Phase 7 review: clearing the request
        // cancelled the highlight's timer).
        // The highlight starts after the click and lasts 2.5 s, so it can't end sooner than that
        // after the click. (Timed from the click: XCUITest's own queries take a while.)
        XCTAssertTrue(wait { (entry.value as? String) == "highlighted" }, "The entry is highlighted")
        XCTAssertTrue(wait(timeout: 8) { (entry.value as? String ?? "") != "highlighted" }, "then it fades")
        let lasted = Date().timeIntervalSince(clicked)
        XCTAssertGreaterThanOrEqual(lasted, 2.4, "Highlighted for a moment, not a flash")
    }

    /// The link also works from a card in the notebook, and closes the card (Phase 7 review:
    /// the cards didn't get the link).
    @MainActor func testTheLinkWorksFromACardInTheNotebook() {
        launch(seed: "notebook")
        expandWithButton()
        tab("habits").click()
        let new = app.buttons["habits.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.click()
        let why = app.buttons["Start smaller than you think"]
        XCTAssertTrue(why.waitForExistence(timeout: 5), "The form's hint has its info button")
        why.click()
        let more = app.buttons["info.more.startSmall"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "The info box in the card has the link")
        more.click()
        XCTAssertTrue(wait { self.tab("science").isSelected }, "Opens The Science")
        XCTAssertTrue(element("science.startSmall").waitForExistence(timeout: 5))
        XCTAssertFalse(element("habitForm").exists, "The card closed")
    }

    /// While onboarding is unfinished the note works, but its info boxes have no link: the
    /// notebook would show onboarding, not The Science (Phase 7 review).
    @MainActor func testNoScienceLinkOnTheNoteDuringOnboarding() {
        launch(seed: "onboarding")
        XCTAssertTrue(app.buttons["onboarding.begin"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel }, "Esc collapses")
        let add = app.buttons["note.addHabit"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        clickAtScreenPoint(of: add)
        let why = app.buttons["Start smaller than you think"]
        XCTAssertTrue(why.waitForExistence(timeout: 5))
        clickAtScreenPoint(of: why)
        XCTAssertTrue(element("info.startSmall").waitForExistence(timeout: 5), "The explanation opens")
        XCTAssertFalse(app.buttons["info.more.startSmall"].exists, "without the link")
    }

    // MARK: Helpers

    @MainActor private var isExpanded: Bool { (try? noteWindow().frame.size) == expandedSize }

    @MainActor private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// A paper toggle's state. It has the toggle trait, so XCUITest may see a switch (value 1/0)
    /// rather than a button with our "on"/"off" value.
    @MainActor private func isOn(_ identifier: String) -> Bool? {
        let toggle = element(identifier)
        guard toggle.waitForExistence(timeout: 5) else { return nil }
        switch toggle.value {
        case let text as String: return text == "on" || text == "1"
        case let number as NSNumber: return number.boolValue
        default: return nil
        }
    }

    /// The notebook is an ordinary window and 66 Days is in front, so plain clicks and typing work.
    @MainActor private func typeInto(_ identifier: String, _ text: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(identifier) exists")
        field.click()
        app.typeText(text)
    }
}
