import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = NoteState()
    private let positions = PositionStore()
    private var window: NoteWindow!
    private var statusItem: NSStatusItem!
    private var observers: [NSObjectProtocol] = []
    private var suppressSave = false
    /// Adaptive mode: becomes true once a second desktop has been seen (until next launch).
    private var adaptiveAllDesktops = false

    private let collapsedSize = NSSize(width: 240, height: 220)
    private let expandedSize = NSSize(width: 520, height: 680)

    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/66DaysPrototype.log")

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NoteWindow(size: collapsedSize)
        let host = NSHostingView(rootView: NoteView(
            state: state,
            onToggleExpand: { [weak self] in self?.toggleExpanded() },
            onConfigChanged: { [weak self] in self?.configChanged() },
            onMarker: { [weak self] text in self?.addMarker(text) }
        ))
        host.sizingOptions = []
        window.contentView = host

        applyConfig()
        restorePosition(reason: "launch")
        window.orderFrontRegardless()

        setUpStatusItem()
        observe()
        log("=== Launched. \(state.config.summary)")
        log("Displays: \(describeScreens())")
    }

    // MARK: Window config

    /// Collapsed: the configured desktop-level sticky note.
    /// Expanded: an ordinary window that belongs only to the desktop it was opened on
    /// (so it never follows you onto other desktops or full-screen apps).
    private func applyConfig() {
        if state.expanded {
            window.level = .normal
            window.collectionBehavior = [.managed, .fullScreenNone]
        } else {
            window.level = state.config.level.level
            window.collectionBehavior = effectiveBehavior()
        }
        updateStatusText()
        rebuildMenu()
    }

    private func effectiveBehavior() -> NSWindow.CollectionBehavior {
        var b = state.config.collectionBehavior
        if state.config.spaces == .adaptive && adaptiveAllDesktops { b.insert(.canJoinAllSpaces) }
        return b
    }

    private var spacesDescription: String {
        guard state.config.spaces == .adaptive else { return state.config.spaces.rawValue }
        return adaptiveAllDesktops ? "adaptive (all desktops)" : "adaptive (one desktop)"
    }

    private func updateStatusText() {
        let screen = window.screen?.localizedName ?? "?"
        state.status = "\(state.config.level.title) · \(spacesDescription) · \(state.config.missionControl.rawValue)\nDisplay: \(screen)"
    }

    // MARK: Expand / collapse

    private func toggleExpanded() {
        suppressSave = true
        defer { suppressSave = false }

        state.expanded.toggle()
        if state.expanded {
            let f = window.frame
            var nf = NSRect(x: f.minX, y: f.maxY - expandedSize.height,
                            width: expandedSize.width, height: expandedSize.height)
            if let vf = window.screen?.visibleFrame { nf = clamp(nf, to: vf) }
            applyConfig()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.setFrame(nf, display: true, animate: true)
            log("Expanded (normal window on this desktop only, activated)")
        } else {
            applyConfig()
            restorePosition(reason: "collapse")
            log("Collapsed (level → \(state.config.level.title))")
        }
        updateStatusText()
    }

    // MARK: Position

    private func restorePosition(reason: String) {
        guard !state.expanded else { return }
        suppressSave = true
        defer { suppressSave = false }
        let (frame, description) = positions.frame(for: collapsedSize)
        window.setFrame(frame, display: true)
        log("Restore position (\(reason)): \(description)")
        updateStatusText()
    }

    private func windowDidMove() {
        // Only a user drag (left mouse held) counts as choosing a new spot.
        // System moves (display unplugged, resolution change) must not overwrite the saved home.
        let userDrag = NSEvent.pressedMouseButtons & 1 == 1
        if userDrag && !suppressSave && !state.expanded {
            log("Moved by user → \(positions.save(window))")
        }
        updateStatusText()
    }

    // MARK: Adaptive desktops

    /// After a Space change, if the note isn't visible because we landed on another *desktop*
    /// (not a full-screen app), switch the note to all desktops. Waits briefly so the window list
    /// reflects the new Space.
    private func scheduleAdaptiveCheck() {
        guard state.config.spaces == .adaptive, !adaptiveAllDesktops else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.runAdaptiveCheck()
        }
    }

    private func runAdaptiveCheck() {
        guard state.config.spaces == .adaptive, !adaptiveAllDesktops, !state.expanded else { return }
        // isOnActiveSpace is unreliable with several displays (a swipe on another display makes it false).
        // Ask the window server directly whether the note is still on screen.
        if noteIsOnScreen() {
            log("Adaptive: Space changed on another display (note still on screen) → nothing to do")
            return
        }
        let (fullScreen, detail) = activeSpaceLooksFullScreen()
        if fullScreen {
            log("Adaptive: left the note's desktop → full-screen app (\(detail)); keeping one-desktop mode")
        } else {
            adaptiveAllDesktops = true
            applyConfig()
            window.orderFrontRegardless()
            log("Adaptive: second desktop detected (\(detail)) → switched to all desktops")
        }
    }

    private func noteIsOnScreen() -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return true }
        let id = window.windowNumber
        return info.contains { ($0[kCGWindowNumber as String] as? Int) == id }
    }

    /// Public, permission-free heuristic: a native full-screen app has a normal-layer window covering
    /// the note's entire display (including the menu bar area).
    private func activeSpaceLooksFullScreen() -> (Bool, String) {
        guard let number = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return (false, "note has no display") }
        let display = CGDisplayBounds(number.uint32Value)
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return (false, "no window list") }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int) != myPID,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let covers = abs(bounds.minX - display.minX) < 2 && abs(bounds.minY - display.minY) < 2
                && abs(bounds.width - display.width) < 2 && abs(bounds.height - display.height) < 2
            if covers {
                return (true, "\(w[kCGWindowOwnerName as String] as? String ?? "?") covers the display")
            }
        }
        // Diagnostics: every on-screen window that overlaps the note's display, with layer and bounds.
        let overlapping = info.compactMap { w -> String? in
            guard let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.intersects(display)
            else { return nil }
            let name = w[kCGWindowOwnerName as String] as? String ?? "?"
            let layer = w[kCGWindowLayer as String] as? Int ?? -999
            return "\(name)[layer \(layer)] \(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))x\(Int(bounds.height))"
        }.joined(separator: " | ")
        return (false, "no window covers display \(NSStringFromRect(display)); overlapping: \(overlapping)")
    }

    // MARK: Observation (what we're testing)

    private func observe() {
        let nc = NotificationCenter.default
        func on(_ name: Notification.Name, object: Any? = nil, center: NotificationCenter = nc,
                _ handler: @escaping @MainActor (AppDelegate) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self)
                }
            })
        }

        on(NSWindow.didMoveNotification, object: window) { $0.windowDidMove() }
        on(NSWindow.didChangeScreenNotification, object: window) {
            $0.log("Window changed display → \($0.window.screen?.localizedName ?? "none")")
            $0.updateStatusText()
        }
        on(NSWindow.didChangeOcclusionStateNotification, object: window) {
            $0.log("Occlusion: visible=\($0.window.occlusionState.contains(.visible))")
        }
        on(NSApplication.didChangeScreenParametersNotification) {
            $0.log("Displays changed: \($0.describeScreens())")
            $0.restorePosition(reason: "displays changed")
        }
        on(NSWorkspace.activeSpaceDidChangeNotification, center: NSWorkspace.shared.notificationCenter) {
            $0.log("Space changed. onActiveSpace=\($0.window.isOnActiveSpace) visible=\($0.window.occlusionState.contains(.visible))")
            if $0.state.expanded {
                $0.log("Auto-collapse: left the desktop while expanded")
                $0.toggleExpanded()
            }
            $0.scheduleAdaptiveCheck()
        }
    }

    // MARK: Menu bar (debug controls)

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "66"
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        menu.addItem(submenu("Window Level", LevelOption.allCases.map {
            item($0.title, #selector(selectLevel(_:)), $0.rawValue, on: state.config.level == $0)
        }))
        menu.addItem(submenu("Spaces", SpacesOption.allCases.map {
            item($0.rawValue, #selector(selectSpaces(_:)), $0.rawValue, on: state.config.spaces == $0)
        }))
        menu.addItem(submenu("Mission Control", MissionControlOption.allCases.map {
            item($0.rawValue, #selector(selectMissionControl(_:)), $0.rawValue, on: state.config.missionControl == $0)
        }))
        menu.addItem(submenu("Flags", FlagOption.allCases.map {
            item($0.rawValue, #selector(toggleFlag(_:)), $0.rawValue, on: state.config.flags.contains($0))
        }))
        menu.addItem(.separator())
        menu.addItem(item(state.expanded ? "Collapse" : "Expand", #selector(menuToggleExpanded), nil))
        menu.addItem(item("Log Current State", #selector(logState), nil))
        menu.addItem(item("Add Test Marker…", #selector(promptMarker), nil))
        menu.addItem(item("Reset Saved Position", #selector(resetPosition), nil))
        menu.addItem(item("Reveal Log File", #selector(revealLog), nil))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, _ action: Selector, _ value: String?, on: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.representedObject = value
        i.state = on ? .on : .off
        return i
    }

    @objc private func selectLevel(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String, let o = LevelOption(rawValue: v) else { return }
        state.config.level = o
        configChanged()
    }

    @objc private func selectSpaces(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String, let o = SpacesOption(rawValue: v) else { return }
        state.config.spaces = o
        configChanged()
    }

    @objc private func selectMissionControl(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String, let o = MissionControlOption(rawValue: v) else { return }
        state.config.missionControl = o
        configChanged()
    }

    @objc private func toggleFlag(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String, let o = FlagOption(rawValue: v) else { return }
        if state.config.flags.contains(o) { state.config.flags.remove(o) } else { state.config.flags.insert(o) }
        configChanged()
    }

    private func configChanged() {
        applyConfig()
        if !state.expanded { window.orderFrontRegardless() }
        log("Config → \(state.config.summary)")
    }

    @objc private func menuToggleExpanded() {
        toggleExpanded()
        rebuildMenu()
    }

    @objc private func logState() {
        log("STATE \(state.config.summary) rawLevel=\(window.level.rawValue) frame=\(NSStringFromRect(window.frame)) display=\(window.screen?.localizedName ?? "none") visible=\(window.occlusionState.contains(.visible)) onActiveSpace=\(window.isOnActiveSpace) expanded=\(state.expanded)")
    }

    @objc private func promptMarker() {
        let alert = NSAlert()
        alert.messageText = "Test marker"
        alert.informativeText = "Describe what you're about to test (it goes into the log)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
            addMarker(field.stringValue)
        }
    }

    private func addMarker(_ text: String) {
        log(">>> TEST: \(text)")
        logState()
    }

    @objc private func resetPosition() {
        positions.reset()
        restorePosition(reason: "reset")
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    // MARK: Logging

    private func describeScreens() -> String {
        NSScreen.screens.map { "\($0.localizedName) \(NSStringFromRect($0.frame))" }.joined(separator: " | ")
    }

    private func log(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(time)] \(message)"
        print(line)
        state.log.append(line)
        if state.log.count > 300 { state.log.removeFirst(state.log.count - 300) }

        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
