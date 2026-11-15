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
final class WindowShellUITests: XCTestCase {
    // Computed, not stored: stored MainActor values would make XCTestCase's inherited
    // initializers MainActor-isolated, which Swift 6 rejects. XCUIApplication instances for the
    // same bundle all refer to the same app.
    @MainActor private var app: XCUIApplication { XCUIApplication() }
    @MainActor private var collapsedLevel: Int { Int(CGWindowLevelForKey(.desktopIconWindow)) + 1 }
    @MainActor private var expandedSize: CGSize { CGSize(width: 880, height: 620) }

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
        launch(rows: 1)
        bringAnotherAppToFront()
        let checkbox = app.checkBoxes["Habit 1"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        // Based on Calculator's window, so if XCUITest activates an app before clicking, it's
        // Calculator, never 66 Days: any focus change is then the note's doing.
        clickAtScreenPoint(of: checkbox, from: otherApp.windows.firstMatch)
        XCTAssertTrue(wait { (checkbox.value as? Int) == 1 }, "One click checks it off")
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
        setPlaceholderRows(5)
        XCTAssertTrue(wait { (try? self.noteWindow().frame.height) ?? 0 > short.height + 100 })
        let tall = try noteWindow().frame
        XCTAssertEqual(tall.minY, short.minY, accuracy: 1)
        XCTAssertEqual(tall.maxX, short.maxX, accuracy: 1)
        assertOnScreen(tall)

        // Bottom-left: shrinks towards the bottom, bottom edge stays.
        try dragNote(toCorner: .bottomLeft, inset: 40)
        let bottom = try noteWindow().frame
        setPlaceholderRows(0)
        XCTAssertTrue(wait { (try? self.noteWindow().frame.height) ?? .infinity < bottom.height - 100 })
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
        XCTAssertEqual(expanded.minX, dragged.minX, accuracy: 1, "Grows out of the note's bottom-left corner")
        XCTAssertEqual(expanded.maxY, dragged.maxY, accuracy: 1)
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
            XCTAssertEqual(expanded.frame.maxX, collapsed.maxX, accuracy: 1, "\(name): grows out of the top-right")
            XCTAssertEqual(expanded.frame.minY, collapsed.minY, accuracy: 1, "\(name)")
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
        bringAnotherAppToFront()
        let text = app.staticTexts.containing(NSPredicate(format: "value CONTAINS 'notebook opens here'")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
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

    // MARK: Helpers

    private struct WindowInfo {
        var frame: CGRect
        var layer: Int
    }

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    @MainActor private func launch(rows: Int = 0, resetPositions: Bool = true) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-placeholderRows", "\(rows)"]
            + (resetPositions ? ["-uiTestResetPositions"] : [])
        app.launch()
        XCTAssertTrue(wait(timeout: 10) { (try? self.noteWindow()) != nil }, "The note appears")
        addTeardownBlock { @MainActor in self.app.terminate() }
        clearTheDesktop()
    }

    @MainActor private func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.ethanlee7102.66days")
            .first { !$0.isTerminated }
    }

    /// The app's visible window as the window server sees it: the note when collapsed, the
    /// notebook when expanded (menu bar windows, open menus and the transparent note are skipped).
    @MainActor private func noteWindow() throws -> WindowInfo {
        let pid = try XCTUnwrap(runningApp()?.processIdentifier)
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer <= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 300, frame.height > 60, // the app's per-display menu bar windows are 30pt
                  window[kCGWindowIsOnscreen as String] as? Bool == true,
                  // The note stays ordered in, transparent, while the notebook is open.
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            return WindowInfo(frame: frame, layer: layer)
        }
        throw NoNoteWindow()
    }

    private struct NoNoteWindow: Error {}

    /// Displays' visible frames (no menu bar or Dock) in global top-left coordinates.
    @MainActor private func visibleFrames() -> [CGRect] {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map {
            let v = $0.visibleFrame
            return CGRect(x: v.minX, y: mainHeight - v.maxY, width: v.width, height: v.height)
        }
    }

    @MainActor private func visibleFrame(of rect: CGRect) -> CGRect {
        visibleFrames().max { overlap($0, rect) < overlap($1, rect) } ?? .zero
    }

    @MainActor private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    @MainActor private func assertOnScreen(_ rect: CGRect, _ message: String = "", line: UInt = #line) {
        let screen = visibleFrame(of: rect).insetBy(dx: -1, dy: -1)
        XCTAssertTrue(screen.contains(rect), "\(message) \(rect) is outside \(screen)", line: line)
    }

    @MainActor private func expandWithButton() {
        let expand = app.buttons["Expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        clickAtScreenPoint(of: expand)
        XCTAssertTrue(wait { (try? self.noteWindow().frame.size) == self.expandedSize }, "Expands")
    }

    /// Calculator stands in for "the app you're using". Not Finder: while Finder is active,
    /// macOS brings desktop widgets forward and XCUITest treats the note as covered. Not the test
    /// runner: it has no windows and can't become the front app.
    @MainActor private var otherApp: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.calculator") }

    @MainActor private func bringAnotherAppToFront() {
        let other = otherApp
        if other.state == .notRunning {
            other.launch()
            addTeardownBlock { @MainActor in other.terminate() }
        }
        other.activate()
        XCTAssertTrue(wait { self.anotherAppIsInFront() })
        moveOtherAppOffTheNote()
    }

    @MainActor private func anotherAppIsInFront() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.calculator"
    }

    /// Drags Calculator's window by its title bar to the opposite side of the screen if it
    /// covers the note.
    @MainActor private func moveOtherAppOffTheNote() {
        guard let note = try? noteWindow().frame else { return }
        let window = otherApp.windows.firstMatch
        guard window.exists, window.frame.intersects(note.insetBy(dx: -20, dy: -20)) else { return }
        let screen = visibleFrame(of: note)
        let titleBar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 10))
        let targetX = note.midX > screen.midX ? screen.minX + 40 : screen.maxX - 40 - window.frame.width
        let targetY = note.midY > screen.midY ? screen.minY + 40 : screen.maxY - 40 - window.frame.height
        titleBar.press(forDuration: 0.3, thenDragTo: titleBar.withOffset(CGVector(
            dx: targetX - window.frame.minX, dy: targetY - window.frame.minY)))
        XCTAssertTrue(wait { !window.frame.intersects(note) }, "Calculator moved off the note")
    }

    /// The note lives under every app window, so the tests hide other apps while they run (the
    /// note has to be uncovered to be clicked and dragged) and unhide them afterwards.
    @MainActor private func clearTheDesktop() {
        let own = [ProcessInfo.processInfo.processIdentifier, runningApp()?.processIdentifier]
        let hidden = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && !own.contains($0.processIdentifier)
        }
        hidden.forEach { $0.hide() }
        addTeardownBlock { @MainActor in hidden.forEach { $0.unhide() } }
        _ = wait(timeout: 3) { hidden.allSatisfy(\.isHidden) }
    }

    @MainActor private func setPlaceholderRows(_ rows: Int) {
        app.activate()
        let debug = app.menuBars.menuBarItems["Debug"]
        XCTAssertTrue(debug.waitForExistence(timeout: 5))
        debug.click()
        app.menuBars.menuItems["Placeholder Habit Rows"].click()
        app.menuBars.menuItems["\(rows)"].click()
    }

    /// The desktop widgets' frames, if any of them overlaps where the note would go in `corner`.
    @MainActor private func widgetsCover(_ corner: Corner) throws -> [CGRect]? {
        let note = try noteWindow().frame
        let screen = visibleFrame(of: note)
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let spot = CGRect(x: left ? screen.minX : screen.maxX - note.width,
                          y: top ? screen.minY : screen.maxY - note.height,
                          width: note.width, height: note.height)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let widgets = windows.compactMap { window -> CGRect? in
            guard (window[kCGWindowOwnerName as String] as? String) == "Notification Center",
                  let layer = window[kCGWindowLayer as String] as? Int, layer > collapsedLevel, layer < 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        let covering = widgets.filter { $0.intersects(spot) }
        return covering.isEmpty ? nil : covering
    }

    /// Drags the collapsed note by its paper margin so it ends `inset` points from a corner of
    /// its display's visible frame.
    @MainActor private func dragNote(toCorner corner: Corner, inset: CGFloat, tolerance: CGFloat = 2) throws {
        let initial = try noteWindow().frame
        let screen = visibleFrame(of: initial)
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let target = CGPoint(x: left ? screen.minX + inset : screen.maxX - inset - initial.width,
                             y: top ? screen.minY + inset : screen.maxY - inset - initial.height)
        let title = app.staticTexts["66 Days"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // A second attempt from wherever the note ended up, like a person re-dragging: long
        // synthesized drags occasionally stop short (seen once across a three-display setup).
        var arrived = false
        for _ in 1...2 where !arrived {
            let start = try noteWindow().frame
            // The paper margin left of the title: not a control, so it drags the window.
            let grab = title.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: -10, dy: 0))
            // Slow, with a hold at the end, like a person placing the note (fast XCUITest drags
            // overshoot at screen edges).
            grab.press(forDuration: 0.3,
                       thenDragTo: grab.withOffset(CGVector(dx: target.x - start.minX, dy: target.y - start.minY)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            arrived = wait {
                guard let frame = try? self.noteWindow().frame else { return false }
                return abs(frame.minX - target.x) <= tolerance && abs(frame.minY - target.y) <= tolerance
            }
        }
        XCTAssertTrue(arrived, "Dragged to \(corner): wanted \(target) from \(initial), got \(String(describing: try? noteWindow().frame))")
    }

    /// Clicks the screen point at the center of `element`, without XCUITest's hittability check.
    /// While another app is active, macOS's desktop-widget layer makes XCUITest think the
    /// desktop-level note is covered; a real click at that point still reaches the note, which
    /// is what these tests check.
    @MainActor private func clickAtScreenPoint(of element: XCUIElement, from base: XCUIElement? = nil) {
        let base = base ?? app.menuBars.firstMatch
        XCTAssertTrue(base.waitForExistence(timeout: 5))
        let origin = base.frame.origin
        let target = CGPoint(x: element.frame.midX, y: element.frame.midY)
        base.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.x - origin.x, dy: target.y - origin.y))
            .click()
    }

    @MainActor private func wait(timeout: TimeInterval = 5, until condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
