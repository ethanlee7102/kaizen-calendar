import AppKit
import XCTest

/// Shared helpers for the XCUITests: launching the app in UI-test mode, finding its windows
/// through the window server, clicking screen points, and keeping other apps out of the way.
///
/// Default isolation is nonisolated in this target: a MainActor XCTestCase subclass can't inherit
/// XCTestCase's nonisolated initializers in Swift 6. Every helper is @MainActor instead.
class NoteUITestCase: XCTestCase {
    // Computed, not stored: stored MainActor values would make XCTestCase's inherited
    // initializers MainActor-isolated, which Swift 6 rejects. XCUIApplication instances for the
    // same bundle all refer to the same app.
    @MainActor var app: XCUIApplication { XCUIApplication() }
    @MainActor var collapsedLevel: Int { Int(CGWindowLevelForKey(.desktopIconWindow)) + 1 }
    @MainActor var expandedSize: CGSize { CGSize(width: 880, height: 620) }

    // MARK: Helpers

    struct WindowInfo {
        var frame: CGRect
        var layer: Int
    }

    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    /// Launches the app in UI-test mode with `seed` data (`DebugData.Scenario` in the app) on a
    /// fixed today, Saturday Nov 14, 2026.
    /// `reports`: deliver report letters (off by default: a letter changes where the notebook
    /// opens).
    /// `notifications`: the pretend notification permission (notDetermined, denied or allowed).
    @MainActor func launch(seed: String = "empty", today: String = NoteUITestCase.today, resetPositions: Bool = true,
                           reports: Bool = false, notifications: String = "allowed") {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestSeed", seed, "-uiTestToday", today,
                               "-uiTestNotifications", notifications]
            + (resetPositions ? ["-uiTestResetPositions"] : []) + (reports ? ["-uiTestReports"] : [])
        app.launch()
        XCTAssertTrue(wait(timeout: 10) { (try? self.noteWindow()) != nil }, "The note appears")
        addTeardownBlock { @MainActor in self.app.terminate() }
        clearTheDesktop()
    }

    /// Every UI test runs on this day (a Saturday).
    nonisolated static let today = "2026-11-14"

    @MainActor func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.ethanlee7102.66days")
            .first { !$0.isTerminated }
    }

    /// The app's visible window as the window server sees it: the note when collapsed, the
    /// notebook when expanded (menu bar windows, open menus and the transparent note are skipped).
    @MainActor func noteWindow() throws -> WindowInfo {
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
    @MainActor func visibleFrames() -> [CGRect] {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map {
            let v = $0.visibleFrame
            return CGRect(x: v.minX, y: mainHeight - v.maxY, width: v.width, height: v.height)
        }
    }

    @MainActor func visibleFrame(of rect: CGRect) -> CGRect {
        visibleFrames().max { overlap($0, rect) < overlap($1, rect) } ?? .zero
    }

    @MainActor func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// `rect` moved into its display's visible frame the way the app keeps the notebook on screen
    /// (`NoteGeometry.clamp`, in top-left coordinates: the left and top edges win).
    @MainActor func clampedToScreen(_ rect: CGRect) -> CGRect {
        let screen = visibleFrame(of: rect)
        var result = rect
        result.origin.x = max(min(rect.minX, screen.maxX - rect.width), screen.minX)
        result.origin.y = max(min(rect.minY, screen.maxY - rect.height), screen.minY)
        return result
    }

    @MainActor func assertOnScreen(_ rect: CGRect, _ message: String = "", line: UInt = #line) {
        let screen = visibleFrame(of: rect).insetBy(dx: -1, dy: -1)
        XCTAssertTrue(screen.contains(rect), "\(message) \(rect) is outside \(screen)", line: line)
    }

    @MainActor func expandWithButton() {
        let expand = app.buttons["Expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        clickAtScreenPoint(of: expand)
        XCTAssertTrue(wait { (try? self.noteWindow().frame.size) == self.expandedSize }, "Expands")
    }

    /// Calculator stands in for "the app you're using". Not Finder: while Finder is active,
    /// macOS brings desktop widgets forward and XCUITest treats the note as covered. Not the test
    /// runner: it has no windows and can't become the front app.
    @MainActor var otherApp: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.calculator") }

    /// `keepingClear`: the area Calculator must not cover (default: the app's visible window).
    @MainActor func bringAnotherAppToFront(keepingClear area: CGRect? = nil) {
        let other = otherApp
        if other.state == .notRunning {
            other.launch()
            addTeardownBlock { @MainActor in other.terminate() }
        }
        other.activate()
        XCTAssertTrue(wait { self.anotherAppIsInFront() })
        if let area = area ?? (try? noteWindow().frame) { moveOtherApp(awayFrom: area) }
    }

    @MainActor func anotherAppIsInFront() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.calculator"
    }

    /// Drags Calculator's window by its title bar to the first screen corner where it doesn't
    /// cover `area` (on a small screen, such as CI's 1024×768, it can't avoid the whole notebook,
    /// only the spot a test clicks).
    @MainActor func moveOtherApp(awayFrom area: CGRect) {
        let window = otherApp.windows.firstMatch
        guard window.exists, window.frame.intersects(area) else { return }
        let size = window.frame.size
        let screen = visibleFrame(of: area)
        let corners = [CGPoint(x: screen.minX + 20, y: screen.maxY - 20 - size.height),
                       CGPoint(x: screen.maxX - 20 - size.width, y: screen.maxY - 20 - size.height),
                       CGPoint(x: screen.minX + 20, y: screen.minY + 20),
                       CGPoint(x: screen.maxX - 20 - size.width, y: screen.minY + 20)]
        guard let target = corners.first(where: { !CGRect(origin: $0, size: size).intersects(area) }) else {
            return XCTFail("No screen corner leaves \(area) uncovered")
        }
        let titleBar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 10))
        titleBar.press(forDuration: 0.3, thenDragTo: titleBar.withOffset(CGVector(
            dx: target.x - window.frame.minX, dy: target.y - window.frame.minY)))
        XCTAssertTrue(wait { !window.frame.intersects(area) }, "Calculator moved off \(area)")
    }

    /// The note lives under every app window, so the tests hide other apps while they run (the
    /// note has to be uncovered to be clicked and dragged) and unhide them afterwards.
    @MainActor func clearTheDesktop() {
        let own = [ProcessInfo.processInfo.processIdentifier, runningApp()?.processIdentifier]
        let hidden = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && !own.contains($0.processIdentifier)
        }
        hidden.forEach { $0.hide() }
        addTeardownBlock { @MainActor in hidden.forEach { $0.unhide() } }
        _ = wait(timeout: 3) { hidden.allSatisfy(\.isHidden) }
    }

    /// Replaces the habits with `count` new ones (Debug ▸ Test Habits, UI-test mode only).
    @MainActor func setTestHabits(_ count: Int) {
        app.activate()
        let debug = app.menuBars.menuBarItems["Debug"]
        XCTAssertTrue(debug.waitForExistence(timeout: 5))
        debug.click()
        app.menuBars.menuItems["Test Habits"].click()
        app.menuBars.menuItems["\(count)"].click()
    }

    /// The desktop widgets' frames, if any of them overlaps where the note would go in `corner`.
    @MainActor func widgetsCover(_ corner: Corner) throws -> [CGRect]? {
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
    @MainActor func dragNote(toCorner corner: Corner, inset: CGFloat, tolerance: CGFloat = 2) throws {
        let initial = try noteWindow().frame
        let screen = visibleFrame(of: initial)
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let target = CGPoint(x: left ? screen.minX + inset : screen.maxX - inset - initial.width,
                             y: top ? screen.minY + inset : screen.maxY - inset - initial.height)
        let title = app.staticTexts["note.month"]
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
    @MainActor func clickAtScreenPoint(of element: XCUIElement, from base: XCUIElement? = nil) {
        let base = base ?? app.menuBars.firstMatch
        XCTAssertTrue(base.waitForExistence(timeout: 5))
        let origin = base.frame.origin
        let target = CGPoint(x: element.frame.midX, y: element.frame.midY)
        base.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.x - origin.x, dy: target.y - origin.y))
            .click()
    }

    /// A text's words: SwiftUI exposes them as the value or (for some texts, such as headers) the label.
    @MainActor func text(_ identifier: String) -> String {
        let element = app.staticTexts[identifier]
        guard element.exists else { return "" }
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    /// A notebook divider tab.
    @MainActor func tab(_ name: String) -> XCUIElement { app.buttons["tab.\(name)"] }

    @MainActor func wait(timeout: TimeInterval = 5, until condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
