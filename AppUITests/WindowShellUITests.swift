import AppKit
import XCTest

/// The window shell's behavior in the real app (build plan Phase 3; the desktop-window
/// prototype's checklist, as far as XCUITest can drive it). Desktops/Spaces, Show Desktop, Stage
/// Manager, full-screen apps and monitor plugging stay a manual checklist.
///
/// The app runs in UI-test mode (`-uiTesting`): an in-memory database and its own position key,
/// so the user's data and note position are never touched. Window frames and levels come from
/// the window server (`CGWindowListCopyWindowInfo`), in global top-left coordinates.
// Default isolation is nonisolated in this target: a MainActor XCTestCase subclass can't inherit
// XCTestCase's nonisolated initializers in Swift 6. Every test and helper is @MainActor instead.
final class WindowShellUITests: NoteUITestCase {

    // MARK: Collapsed note

    @MainActor func testCollapsedNoteSitsOnTheDesktopLayerAtTheTopRight() throws {
        launch()
        let note = try noteWindow()
        XCTAssertEqual(note.layer, collapsedLevel)
        XCTAssertEqual(note.frame.width, 300)
        let screen = visibleFrame(of: note.frame)
        XCTAssertEqual(note.frame.maxX, screen.maxX - 24, accuracy: 1)
        XCTAssertEqual(note.frame.minY, screen.minY + 24, accuracy: 1) // top-left coordinates
    }

    @MainActor func testFirstClickChecksOffWithoutTakingFocus() throws {
        launch(seed: "habits:1")
        bringAnotherAppToFront()
        let leaf = app.buttons["leaf.Read"]
        XCTAssertTrue(leaf.waitForExistence(timeout: 5))
        // Based on Calculator's window, so if XCUITest activates an app before clicking, it's
        // Calculator, never 66 Days: any focus change is then the note's doing.
        clickAtScreenPoint(of: leaf, from: otherApp.windows.firstMatch)
        XCTAssertTrue(wait { (leaf.value as? String) == "done" }, "One click checks it off")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5)) // a late activation would show by now
        XCTAssertTrue(anotherAppIsInFront(), "The app you were in keeps focus")
    }

    @MainActor func testHideKeepsTheCollapsedNoteOnTheDesktop() throws {
        launch()
        let before = try noteWindow()
        // From the menu, so the hide surely reaches the app (macOS doesn't mark the app hidden
        // when its only window can't hide, so that can't be checked).
        app.activate()
        app.menuBars.menuItems["Hide 66 Days"].click()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let after = try noteWindow() // only finds on-screen windows
        XCTAssertEqual(after.frame, before.frame)
    }

    @MainActor func testNoteGrowsAwayFromItsCornerAndStaysOnScreen() throws {
        launch()
        // Top-right (initial): grows downwards, top edge stays.
        let short = try noteWindow().frame
        setTestHabits(5)
        XCTAssertTrue(wait { (try? self.noteWindow().frame.height) ?? 0 > short.height + 100 })
        let tall = try noteWindow().frame
        XCTAssertEqual(tall.minY, short.minY, accuracy: 1)
        XCTAssertEqual(tall.maxX, short.maxX, accuracy: 1)
        assertOnScreen(tall)

        // Bottom-left: shrinks towards the bottom, bottom edge stays. With 2 habits, not 5: a
        // 5-habit note nearly fills CI's 1024×768 screen, so dragged to the bottom its center is
        // above the middle and the app (rightly) anchors it to the top corner (CI, PR #5).
        setTestHabits(2)
        try dragNote(toCorner: .bottomLeft, inset: 40)
        let bottom = try noteWindow().frame
        XCTAssertGreaterThan(bottom.midY, visibleFrame(of: bottom).midY, "In the bottom half, so anchored to the bottom")
        setTestHabits(0)
        XCTAssertTrue(wait { (try? self.noteWindow().frame.height) ?? .infinity < bottom.height - 40 })
        let shrunk = try noteWindow().frame
        XCTAssertEqual(shrunk.maxY, bottom.maxY, accuracy: 1)
        XCTAssertEqual(shrunk.minX, bottom.minX, accuracy: 1)
    }

    // MARK: Position

    @MainActor func testDraggedPositionIsKeptAcrossExpandAndRelaunch() throws {
        launch()
        try dragNote(toCorner: .bottomLeft, inset: 60)
        let dragged = try noteWindow().frame

        expandWithButton()
        let expanded = try noteWindow().frame
        // Out of the note's bottom-left corner, then kept on screen (on a short screen, such as
        // CI's 1024×768, keeping it on screen moves it down).
        let expected = clampedToScreen(CGRect(x: dragged.minX, y: dragged.maxY - expandedSize.height,
                                              width: expandedSize.width, height: expandedSize.height))
        XCTAssertEqual(expanded.minX, expected.minX, accuracy: 1, "Grows out of the note's bottom-left corner: \(expanded) vs \(expected)")
        XCTAssertEqual(expanded.minY, expected.minY, accuracy: 1, "\(expanded) vs \(expected)")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wait { (try? self.noteWindow().frame) == dragged }, "Collapses back to the dragged spot")

        app.terminate()
        launch(resetPositions: false)
        XCTAssertTrue(wait { (try? self.noteWindow().frame) == dragged }, "Comes back after a relaunch")
    }

    // MARK: Expanded notebook

    @MainActor func testExpandAndEveryWayToCollapse() throws {
        launch()
        let collapsed = try noteWindow().frame
        let ways: [(String, () -> Void)] = [
            ("Collapse button", { self.app.buttons["Collapse"].click() }),
            ("Esc", { self.app.typeKey(.escape, modifierFlags: []) }),
            ("⌘W", { self.app.typeKey("w", modifierFlags: .command) }),
            ("⌘H", { self.app.typeKey("h", modifierFlags: .command) }),
        ]
        for (name, collapse) in ways {
            bringAnotherAppToFront() // you're in another app and click Expand on the note
            expandWithButton()
            let expanded = try noteWindow()
            XCTAssertEqual(expanded.layer, 0, "\(name): expanded is a normal window")
            XCTAssertEqual(expanded.frame.size, expandedSize, "\(name)")
            let expected = clampedToScreen(CGRect(x: collapsed.maxX - expandedSize.width, y: collapsed.minY,
                                                  width: expandedSize.width, height: expandedSize.height))
            XCTAssertEqual(expanded.frame.minX, expected.minX, accuracy: 1, "\(name): grows out of the top-right")
            XCTAssertEqual(expanded.frame.minY, expected.minY, accuracy: 1, "\(name)")
            assertOnScreen(expanded.frame)
            XCTAssertEqual(app.state, .runningForeground, "\(name): in front and focused")

            collapse()
            XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel }, "\(name): collapses")
            XCTAssertEqual(try noteWindow().frame, collapsed, "\(name): back at its spot")
            XCTAssertTrue(wait { self.anotherAppIsInFront() }, "\(name): focus goes back to the app you were in")
        }
    }

    @MainActor func testNotebookStaysOnScreenFromEveryCorner() throws {
        launch()
        var tested = 0
        for corner in Corner.allCases {
            // Desktop widgets sit one level above the note and cover it, so a corner they occupy
            // can't be tested here (CI has no widgets, so it covers every corner).
            if let blocked = try widgetsCover(corner) {
                print("Skipping \(corner): desktop widgets at \(blocked)")
                continue
            }
            // Near the corner is enough here (XCUITest drags can overshoot a few points).
            try dragNote(toCorner: corner, inset: 0, tolerance: 16)
            // From the Window menu: in a corner, desktop widgets can cover the note's button.
            app.activate()
            app.menuBars.menuItems["Expand Note"].click()
            XCTAssertTrue(wait { (try? self.noteWindow().frame.size) == self.expandedSize }, "\(corner): expands")
            let expanded = try noteWindow().frame
            XCTAssertEqual(expanded.size, expandedSize, "\(corner)")
            assertOnScreen(expanded, "\(corner)")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel })
            tested += 1
        }
        if tested == 0 { throw XCTSkip("Desktop widgets cover every corner; nothing was tested") }
    }

    /// Clicking the open notebook while another app is active brings 66 Days to the front, so Esc
    /// then hands focus back. (It failed while the notebook was the non-activating note panel;
    /// fixed by making the notebook a separate ordinary window, Phase 3 research.)
    @MainActor func testClickingTheOpenNotebookFromAnotherAppFocusesIt() throws {
        launch()
        bringAnotherAppToFront()
        expandWithButton()
        let text = app.staticTexts.containing(NSPredicate(format: "value CONTAINS 'notebook opens here'")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        bringAnotherAppToFront(keepingClear: text.frame)
        clickAtScreenPoint(of: text, from: otherApp.windows.firstMatch)
        XCTAssertTrue(wait { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.ethanlee7102.66days" },
                      "Clicking the notebook brings 66 Days to the front")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wait { (try? self.noteWindow().layer) == self.collapsedLevel }, "Esc collapses")
        XCTAssertTrue(wait { self.anotherAppIsInFront() }, "Focus goes back to the app you were in")
    }

    @MainActor func testOpeningTheAppAgainExpandsTheNote() async throws {
        launch()
        bringAnotherAppToFront()
        let url = try XCTUnwrap(runningApp()?.bundleURL)
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        XCTAssertTrue(wait { (try? self.noteWindow().frame.size) == self.expandedSize }, "Reopen (Dock click) expands")
        XCTAssertTrue(wait { self.app.state == .runningForeground })
    }
}
