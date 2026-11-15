import AppKit
import AppShell
import Persistence
import SwiftUI
import UI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let note: NoteWindowController
    private let placeholder = PlaceholderState()
    private var dayMonitor: DayChangeMonitor?

    init(options: LaunchOptions) {
        self.options = options
        note = NoteWindowController(collapsedWidth: Metrics.noteWidth, expandedSize: Metrics.expandedSize,
                                    store: options.positionStore())
        placeholder.rows = options.placeholderRows
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FontRegistry.registerAll()
        } catch {
            assertionFailure("Couldn't register the bundled fonts: \(error)")
        }
        let model = Result {
            AppModel(repository: try options.openRepository())
        }.mapError { DatabaseOpenError(message: "\($0)") }

        NSApp.mainMenu = MainMenu.make(note: note, debug: debugActions(model: model))
        note.show(
            collapsed: PlaceholderNote(model: model, state: placeholder).appearance(),
            expanded: PlaceholderNotebook(model: model).appearance())
        if case .success(let model) = model { watchTheDay(model) }
    }

    /// Clicking the Dock icon (or opening the app again) opens the notebook (decided in the
    /// Phase 3 build; spec-expanded-structure.md).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        note.expand()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Keeps `AppModel.today` current: at the day boundary (with the day-end time), on wake, and
    /// on clock or time-zone changes. The boundary is rescheduled when today or the day-end
    /// setting changes.
    private func watchTheDay(_ model: AppModel) {
        let monitor = DayChangeMonitor(
            // From the clock, not `model.today`, so the boundary is always in the future even if
            // today didn't move (Phase 3 review: otherwise the timer could fire every second).
            nextChange: {
                let clock = model.data.settings.dayClock
                return clock.end(of: clock.day(for: Date()))
            },
            onChange: { model.refreshToday() })
        monitor.start()
        dayMonitor = monitor
        Task { [weak monitor] in
            for await _ in Observations({ (model.today, model.data.settings.dayEndHour) }) {
                monitor?.reschedule()
            }
        }
    }

    private func debugActions(model: Result<AppModel, DatabaseOpenError>) -> MainMenu.DebugActions? {
        #if DEBUG
        MainMenu.DebugActions(
            placeholderRows: { [placeholder] in placeholder.rows },
            setPlaceholderRows: { [placeholder] in placeholder.rows = $0 },
            refreshToday: { if case .success(let model) = model { model.refreshToday() } })
        #else
        nil
        #endif
    }
}

struct DatabaseOpenError: Error {
    let message: String
}

private extension View {
    /// The Appearance setting defaults to Light, and dark mode is an unlock (spec-settings.md,
    /// spec-stamp-book.md). Phase 5 wires the setting.
    func appearance() -> some View {
        preferredColorScheme(.light)
    }
}
