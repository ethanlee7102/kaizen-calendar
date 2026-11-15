import AppKit
import Observation
import SwiftUI

/// Owns the note's two windows: the collapsed note on the desktop (`NotePanel`) and the notebook
/// (`NotebookWindow`). Expands the note into the notebook and folds it back, remembers where the
/// user put the note, and keeps both on screen.
///
/// Content views get the controller from the environment (`@Environment(NoteWindowController.self)`)
/// to read `isExpanded` and call `expand()` / `collapse()`.
///
/// Behavior (desktop-window-findings.md, spec-expanded-structure.md, spec-edge-states.md):
/// - Collapsed: desktop-level, one desktop only, first shown on a regular desktop (never on a
///   full-screen app's space, `RegularDesktopGate`). Its height follows its content; it grows
///   away from its saved corner and is kept fully on screen.
/// - Only the user's drags of the collapsed note save a position, per display. Display changes
///   re-place it from the saved positions (fallback to the main display, return on replug).
/// - Expanded: a separate ordinary window that grows out of the note's corner, kept on screen, in
///   front and focused. Esc, Close (⌘W), Hide (⌘H) and leaving its desktop collapse it. While it's
///   open, the note stays ordered in (so it keeps its desktop) but invisible and click-through.
@Observable
public final class NoteWindowController {
    /// Whether the notebook is open.
    public private(set) var isExpanded = false

    @ObservationIgnored private let panel = NotePanel()
    @ObservationIgnored private let notebook = NotebookWindow()
    @ObservationIgnored private let desktopGate = RegularDesktopGate()
    @ObservationIgnored private let store: PositionStore
    @ObservationIgnored private let collapsedWidth: CGFloat
    @ObservationIgnored private let expandedSize: CGSize
    /// The collapsed content's height, as last measured.
    @ObservationIgnored private var collapsedHeight: CGFloat = 1
    /// True while the controller itself moves the panel, so those moves are never saved.
    @ObservationIgnored private var isPlacing = false
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var isShown = false
    @ObservationIgnored private var drag = DragSaveTracker()
    /// The scheduled settle check of a user drag.
    @ObservationIgnored private var pendingSettle: Task<Void, Never>?
    /// The last other app that was active, to hand focus back to when the notebook folds.
    @ObservationIgnored private var lastOtherApp: NSRunningApplication?

    public init(collapsedWidth: CGFloat, expandedSize: CGSize, store: PositionStore = PositionStore()) {
        self.collapsedWidth = collapsedWidth
        self.expandedSize = expandedSize
        self.store = store
        notebook.onClose = { [weak self] in self?.collapse() }
    }

    /// Puts the collapsed note on the desktop with this content. Call once, at launch.
    ///
    /// `collapsed` is laid out at the note's width and its ideal height (the note never
    /// scrolls); `expanded` fills the notebook.
    public func show(collapsed: some View, expanded: some View) {
        // A flag, not `panel.contentView == nil`: every NSPanel starts with a default content
        // view (that check crashed every launch).
        guard !isShown else { return assertionFailure("show(collapsed:expanded:) is called once") }
        isShown = true
        let host = NSHostingView(rootView: CollapsedContainer(
            controller: self, width: collapsedWidth, content: collapsed))
        host.sizingOptions = [] // the controller sizes the panel
        panel.contentView = host
        collapsedHeight = max(host.fittingSize.height, 1)
        let notebookHost = NSHostingView(rootView: expanded
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Under the hidden title bar too: otherwise the strip shows the window's background.
            .ignoresSafeArea()
            .environment(self))
        notebookHost.sizingOptions = []
        notebook.contentView = notebookHost

        placeCollapsed()
        observe()
        // Shown on the desktop that's active once it's a regular desktop: right away from a
        // desktop or at login; after macOS switches away from a full-screen app otherwise.
        desktopGate.whenOnRegularDesktop { [weak self] in self?.panel.orderFrontRegardless() }
    }

    // MARK: Expand / collapse

    /// Opens the notebook in front and focused. Also what a Dock click does (decided in the
    /// Phase 3 build).
    public func expand() {
        guard !isExpanded else {
            NSApp.activate()
            notebook.makeKeyAndOrderFront(nil)
            return
        }
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        pendingSettle?.cancel()
        pendingSettle = nil
        if drag.finish() { saveCurrentPosition() }
        isExpanded = true
        notebook.setFrame(NoteGeometry.expandedFrame(from: panel.frame, size: expandedSize, in: visibleFrame),
                          display: true)
        // Never ordered out: ordering it in again would attach it to whatever space is active.
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        NSApp.activate()
        notebook.makeKeyAndOrderFront(nil)
    }

    /// Folds the notebook back into the note at its saved spot, and hands focus back to the app
    /// you were using.
    public func collapse() {
        collapse(handingFocusBack: true)
    }

    /// `handingFocusBack` is false when you switched desktops: macOS has already chosen what's
    /// active there, and activating the previous app could switch you back (decided in the
    /// Phase 3 review, with the user).
    private func collapse(handingFocusBack: Bool) {
        guard isExpanded else { return }
        isExpanded = false
        notebook.makeFirstResponder(nil)
        notebook.orderOut(nil)
        placeCollapsed()
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        // The notebook was on a regular desktop, so a note still waiting for one can show now.
        desktopGate.fulfill()
        if handingFocusBack { handFocusBack() }
    }

    /// `NSApp.deactivate()` alone doesn't reliably activate another app under macOS 14+
    /// cooperative activation (found by the Phase 3 UI tests), so the last app you used is
    /// activated directly.
    private func handFocusBack() {
        guard NSApp.isActive else { return }
        if let app = lastOtherApp, !app.isTerminated, app.activate(from: .current, options: []) { return }
        NSApp.deactivate()
    }

    private func otherAppActivated(pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lastOtherApp = NSRunningApplication(processIdentifier: pid)
    }

    public func toggle() {
        isExpanded ? collapse() : expand()
    }

    /// Forgets every saved position and moves the note to the top-right of the main display
    /// ("Reset note position", spec-settings.md).
    public func resetPosition() {
        store.reset()
        placeCollapsed()
    }

    // MARK: Placement

    private var collapsedSize: CGSize {
        CGSize(width: collapsedWidth, height: collapsedHeight)
    }

    /// Puts the collapsed note where the saved positions say.
    private func placeCollapsed() {
        guard let frame = store.positions.frame(size: collapsedSize, displays: Display.connected) else { return }
        setFrame(frame)
    }

    private func setFrame(_ frame: CGRect) {
        isPlacing = true
        defer { isPlacing = false }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// The collapsed content's height changed (a habit was added, a line swapped in). The note
    /// grows away from its saved corner and stays on screen (`NoteGeometry.collapsedFrame`).
    func collapsedContentHeightChanged(to height: CGFloat) {
        let height = max(height.rounded(.up), 1)
        guard height != collapsedHeight else { return }
        collapsedHeight = height
        guard let frame = NoteGeometry.collapsedFrame(
            afterHeightChangeTo: collapsedSize, current: panel.frame, currentDisplay: panel.screen?.display,
            positions: store.positions, displays: Display.connected, isDragging: drag.isDragging)
        else { return }
        setFrame(frame)
    }

    /// Only a user drag (left mouse held) chooses a new spot; moves by the system and by the
    /// controller never do (`DragSaveTracker`). The spot is saved once the moves settle and the
    /// button is up (Phase 3 UI tests and review: the last move can arrive after the release,
    /// and a drag held still before the release must not leave a drag "open").
    private func noteMoved() {
        guard !isPlacing, !isExpanded else { return }
        if drag.moved(buttonDown: Self.isLeftButtonDown) { scheduleSettleCheck() }
    }

    static let dragSettleTime = Duration.milliseconds(250)

    private static var isLeftButtonDown: Bool { NSEvent.pressedMouseButtons & 1 == 1 }

    private func scheduleSettleCheck() {
        pendingSettle?.cancel()
        pendingSettle = Task { [weak self] in
            try? await Task.sleep(for: Self.dragSettleTime)
            guard !Task.isCancelled else { return }
            self?.dragSettled()
        }
    }

    private func dragSettled() {
        pendingSettle = nil
        switch drag.settled(buttonDown: Self.isLeftButtonDown) {
        case .save: saveCurrentPosition()
        case .waitForRelease: scheduleSettleCheck()
        case .nothing: break
        }
    }

    private func saveCurrentPosition() {
        guard !isExpanded, let display = panel.screen?.display else { return }
        var positions = store.positions
        positions.save(frame: panel.frame, on: display)
        store.positions = positions
    }

    private func displaysChanged() {
        if isExpanded, let visibleFrame = (notebook.screen ?? NSScreen.main)?.visibleFrame {
            notebook.setFrame(NoteGeometry.clamp(notebook.frame, to: visibleFrame), display: true)
        }
        // Mid-drag, the user's drop wins: it's saved when the drag settles.
        if !drag.isDragging { placeCollapsed() }
    }

    private func activeSpaceChanged() {
        // Leaving the notebook's desktop folds it back. Opening it from a full-screen app makes
        // macOS switch to a desktop first; the notebook is on that one, so it stays open.
        if isExpanded && !notebook.isOnActiveSpace { collapse(handingFocusBack: false) }
    }

    // MARK: Observation

    private func observe() {
        let center = NotificationCenter.default
        on(NSWindow.didMoveNotification, object: panel, in: center) { $0.noteMoved() }
        on(NSApplication.didChangeScreenParametersNotification, in: center) { $0.displaysChanged() }
        on(NSApplication.willHideNotification, in: center) { $0.collapse() }
        on(NSWorkspace.activeSpaceDidChangeNotification, in: NSWorkspace.shared.notificationCenter) {
            $0.activeSpaceChanged()
        }
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.otherAppActivated(pid: pid) }
        }
        observers.append((NSWorkspace.shared.notificationCenter, token))
        if let front = NSWorkspace.shared.frontmostApplication { otherAppActivated(pid: front.processIdentifier) }
    }

    private func on(_ name: Notification.Name, object: AnyObject? = nil, in center: NotificationCenter,
                    _ handler: @escaping @MainActor (NoteWindowController) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }
}

/// Lays out the note's content at its width and ideal height (the note never scrolls) and
/// reports the height, so the panel follows it.
private struct CollapsedContainer<Content: View>: View {
    let controller: NoteWindowController
    let width: CGFloat
    let content: Content

    var body: some View {
        content
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                controller.collapsedContentHeightChanged(to: height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(controller)
    }
}
