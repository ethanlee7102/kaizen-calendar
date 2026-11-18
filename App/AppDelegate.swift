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
    private let navigation: NotebookNavigation
    private let deletion = PendingDeletion()
    private let loginItem: LoginItemSwitch
    private let dragHint: DragHintStore
    /// Onboarding's page, kept while the app runs (collapsing and reopening comes back to it).
    private let onboarding = OnboardingFlow()
    private var dayMonitor: DayChangeMonitor?
    private var reportMonitor: DayChangeMonitor?

    init(options: LaunchOptions) {
        self.options = options
        note = NoteWindowController(collapsedWidth: Metrics.noteWidth, expandedSize: Metrics.expandedSize,
                                    store: options.positionStore())
        clock = AppClock(fixedDay: options.fixedToday)
        welcomeBack = options.welcomeBackStore()
        navigation = NotebookNavigation(defaults: options.usesInMemoryDatabase ? nil : .standard)
        loginItem = LoginItemSwitch(fake: options.isUITesting)
        dragHint = options.dragHintStore()
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

        // Light only until Dark mode is unlocked (spec-stamp-book.md); `watchAppearance` follows
        // the setting after that.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.mainMenu = MainMenu.make(note: note, navigation: navigation, debug: debugActions(model: model))
        note.show(
            collapsed: NoteScreen(model: model, welcomeBack: welcomeBack, navigation: navigation, dragHint: dragHint),
            expanded: NotebookScreen(model: model, welcomeBack: welcomeBack, navigation: navigation, deletion: deletion,
                                     loginItem: loginItem, onboarding: onboarding, dragHint: dragHint))
        NoteShortcut.onPress { [note] in note.toggle() }
        // The first drag retires "Drag me anywhere." (spec-onboarding.md).
        note.onUserDrag = { [dragHint] in dragHint.finish() }
        if case .success(let model) = model {
            openOnboarding(model)
            watchTheDay(model)
            watchAppearance(model)
            recordUnlocks(model)
            if options.deliversReports { watchReports(model) }
        }
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
                let dayEnd = model.data.settings.dayEnd
                return dayEnd.end(of: dayEnd.day(for: Date()))
            },
            onChange: { model.refreshToday() })
        monitor.start()
        dayMonitor = monitor
        Task { [weak monitor, welcomeBack] in
            // `model.data` changes with every write, so this emits often: act only when today or
            // the day-end hour actually changed (Phase 4 review).
            var last: (DayKey, DayEnd)?
            for await (today, dayEnd) in Observations({ (model.today, model.data.settings.dayEnd) }) {
                if let last, last == (today, dayEnd) { continue }
                last = (today, dayEnd)
                monitor?.reschedule()
                welcomeBack.check(today, evaluations: model.evaluations)
            }
        }
    }

    /// Launching before onboarding is finished opens the notebook into it (spec-onboarding.md),
    /// once the data has loaded: an unreadable database is never mistaken for a first launch
    /// (Phase 7 review).
    private func openOnboarding(_ model: AppModel) {
        Task { [note] in
            for await needed in Observations({ model.needsOnboarding }) where needed {
                note.expand()
                break
            }
        }
    }

    /// Delivers report letters when they're due (spec-reports.md, Delivery): at launch (catching
    /// up after the Mac was off), at the report time, on wake and clock changes, and after any
    /// change to the data or the day (a 66th done day, a new day for a re-check, a new report
    /// time). Delivery is idempotent, so checking often is safe.
    private func watchReports(_ model: AppModel) {
        let monitor = DayChangeMonitor(
            nextChange: {
                ReportSchedule(settings: model.data.settings.report, clock: DayClock()).nextDeliveryTime(after: Date())
            },
            onChange: { Writes.deliverReports(model) })
        monitor.start()
        reportMonitor = monitor
        Task { [weak monitor] in
            var lastSettings: ReportSettings?
            for await (_, _, settings) in Observations({ (model.data, model.today, model.data.settings.report) }) {
                Writes.deliverReports(model)
                if settings != lastSettings {
                    lastSettings = settings
                    monitor?.reschedule()
                }
            }
        }
    }

    /// Light / Dark / Match system, once Dark mode is unlocked (spec-settings.md). Set on the app,
    /// so both windows and every color token follow it.
    private func watchAppearance(_ model: AppModel) {
        Task {
            for await appearance in Observations({ model.effectiveAppearance }) {
                let name: NSAppearance.Name? = switch appearance {
                case .light: .aqua
                case .dark: .darkAqua
                case .matchSystem: nil
                }
                let new = name.flatMap(NSAppearance.init(named:))
                if NSApp.appearance?.name != new?.name { NSApp.appearance = new }
            }
        }
    }

    /// Stores unlocks as soon as the stamp count earns them (spec-stamp-book.md): the note then
    /// shows "You found something" and the Stamp book tab its "1 new" marker. Never taken back.
    private func recordUnlocks(_ model: AppModel) {
        Task {
            for await unlocks in Observations({ model.newUnlocks }) where !unlocks.isEmpty {
                Writes.attempt("unlock") { try model.repository.recordUnlocks(unlocks, at: Date()) }
            }
        }
    }

    private func debugActions(model: Result<AppModel, DatabaseOpenError>) -> MainMenu.DebugActions? {
        #if DEBUG
        guard case .success(let model) = model else { return nil }
        let inMemory = options.usesInMemoryDatabase
        return MainMenu.DebugActions(
            refreshToday: { model.refreshToday() },
            // Jumps the clock just past the next report time, so a letter arrives now.
            skipToNextReport: inMemory ? { [clock] in
                let schedule = ReportSchedule(settings: model.data.settings.report, clock: DayClock())
                let next = schedule.nextDeliveryTime(after: clock.now())
                clock.extraSeconds += next.timeIntervalSince(clock.now()) + 60
                model.refreshToday()
                Writes.deliverReports(model)
            } : nil,
            // Only on in-memory data: these would rewrite or time-shift real history.
            replaceHabits: inMemory ? { [clock] count in
                do {
                    try DebugData.replaceHabits(with: count, in: model.repository, today: DayClock().day(for: clock.now()))
                } catch {
                    NSSound.beep()
                }
            } : nil,
            moveToday: inMemory ? { [clock] days in
                if let days {
                    clock.offsetDays += days
                } else {
                    clock.offsetDays = 0
                    clock.extraSeconds = 0
                }
                model.refreshToday()
                Writes.deliverReports(model)
            } : nil)
        #else
        nil
        #endif
    }
}

struct DatabaseOpenError: Error {
    let message: String
}
