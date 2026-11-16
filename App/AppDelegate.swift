import AppKit
import AppShell
import Core
import Persistence
import SwiftUI
import UI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let note: NoteWindowController
    private let clock: AppClock
    private let welcomeBack: WelcomeBackStore
    private var dayMonitor: DayChangeMonitor?

    init(options: LaunchOptions) {
        self.options = options
        note = NoteWindowController(collapsedWidth: Metrics.noteWidth, expandedSize: Metrics.expandedSize,
                                    store: options.positionStore())
        clock = AppClock(fixedDay: options.fixedToday)
        welcomeBack = options.welcomeBackStore()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FontRegistry.registerAll()
        } catch {
            assertionFailure("Couldn't register the bundled fonts: \(error)")
        }
        let model = Result {
            let repository = try options.openRepository()
            try seed(repository)
            return AppModel(repository: repository, now: { [clock] in clock.now() })
        }.mapError { DatabaseOpenError(message: "\($0)") }

        NSApp.mainMenu = MainMenu.make(note: note, debug: debugActions(model: model))
        note.show(
            collapsed: NoteScreen(model: model, welcomeBack: welcomeBack).appearance(),
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

    /// Debug data for UI tests and the sample-data mode (in-memory databases only).
    private func seed(_ repository: Repository) throws {
        #if DEBUG
        guard options.usesInMemoryDatabase else { return }
        let today = DayClock().day(for: clock.now())
        if options.usesSampleData {
            try DebugData.seed(.sample, into: repository, today: today)
        } else if let text = options.seed {
            guard let scenario = DebugData.Scenario(text) else {
                throw DatabaseOpenError(message: "Unknown UI-test seed: \(text)")
            }
            try DebugData.seed(scenario, into: repository, today: today)
        }
        #endif
    }

    /// Keeps `AppModel.today` current: at the day boundary (with the day-end time), on wake, and
    /// on clock or time-zone changes. The boundary is rescheduled when today or the day-end
    /// setting changes. Launch and each new day also check whether "Welcome back" is due.
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
        Task { [weak monitor, welcomeBack] in
            // `model.data` changes with every write, so this emits often: act only when today or
            // the day-end hour actually changed (Phase 4 review).
            var last: (DayKey, Int)?
            for await (today, hour) in Observations({ (model.today, model.data.settings.dayEndHour) }) {
                if let last, last == (today, hour) { continue }
                last = (today, hour)
                monitor?.reschedule()
                welcomeBack.check(today, evaluations: model.evaluations)
            }
        }
    }

    private func debugActions(model: Result<AppModel, DatabaseOpenError>) -> MainMenu.DebugActions? {
        #if DEBUG
        guard case .success(let model) = model else { return nil }
        let inMemory = options.usesInMemoryDatabase
        return MainMenu.DebugActions(
            refreshToday: { model.refreshToday() },
            // Only on in-memory data: these would rewrite or time-shift real history.
            replaceHabits: inMemory ? { [clock] count in
                do {
                    try DebugData.replaceHabits(with: count, in: model.repository, today: DayClock().day(for: clock.now()))
                } catch {
                    NSSound.beep()
                }
            } : nil,
            moveToday: inMemory ? { [clock] days in
                if let days { clock.offsetDays += days } else { clock.offsetDays = 0 }
                model.refreshToday()
            } : nil)
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
