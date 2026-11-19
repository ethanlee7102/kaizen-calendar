import AppShell
import Core
import Foundation
import Persistence

/// How the app was launched. UI tests (AppUITests) launch it in a test mode so they never touch
/// the user's database or note position. Release builds always run normally.
struct LaunchOptions {
    /// An in-memory database and a separate note-position key.
    var isUITesting = false
    /// Start the note from its initial position (UI tests only).
    var resetsPositions = false
    /// Debug only: an in-memory database filled with a sample month, so every mark and line can
    /// be seen (and time-travelled) without touching real data.
    var usesSampleData = false
    /// Data to start with in UI-test mode (`DebugData.Scenario`).
    var seed: String?
    /// A fixed "today" for UI tests, so runs are deterministic.
    var fixedToday: DayKey?
    /// UI tests get report letters only when they ask (`-uiTestReports`): a letter would change
    /// where the notebook opens for every other test.
    var uiTestReports = false
    /// What the pretend notification permission starts as in UI tests (`-uiTestNotifications
    /// notDetermined|denied|allowed`; default allowed, so the reminder prompt doesn't change the
    /// note for every other test).
    var uiTestNotifications: NotificationPermission = .allowed

    static let uiTesting = "-uiTesting"
    static let resetPositions = "-uiTestResetPositions"
    static let seedArgument = "-uiTestSeed"
    static let todayArgument = "-uiTestToday"
    static let sampleData = "-sampleData"
    static let reportsArgument = "-uiTestReports"
    static let notificationsArgument = "-uiTestNotifications"

    static var current: LaunchOptions {
        #if DEBUG
        LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
        LaunchOptions()
        #endif
    }

    init() {}

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        usesSampleData = arguments.contains(Self.sampleData)
        isUITesting = arguments.contains(Self.uiTesting)
        guard isUITesting else { return }
        resetsPositions = arguments.contains(Self.resetPositions)
        seed = value(after: Self.seedArgument)
        fixedToday = value(after: Self.todayArgument).flatMap(DayKey.init)
        uiTestReports = arguments.contains(Self.reportsArgument)
        switch value(after: Self.notificationsArgument) {
        case "notDetermined": uiTestNotifications = .notDetermined
        case "denied": uiTestNotifications = .denied
        default: uiTestNotifications = .allowed
        }
    }

    /// Letters are delivered normally, and in UI tests only when asked for.
    var deliversReports: Bool { !isUITesting || uiTestReports }

    /// The database lives in memory in UI-test and sample-data modes.
    var usesInMemoryDatabase: Bool { isUITesting || usesSampleData }

    func openRepository() throws -> Repository {
        Repository(database: usesInMemoryDatabase ? try AppDatabase.inMemory()
                                                  : try AppDatabase.open(at: AppDatabase.defaultURL()))
    }

    func positionStore() -> PositionStore {
        let store = isUITesting ? PositionStore(key: "uiTests.note.positions") : PositionStore()
        if resetsPositions { store.reset() }
        return store
    }

    /// Where "Drag me anywhere." is remembered: nowhere in the in-memory modes.
    func dragHintStore() -> DragHintStore {
        DragHintStore(defaults: usesInMemoryDatabase ? nil : .standard)
    }

    /// The never-miss-twice reminder. The in-memory modes never schedule real notifications or
    /// ask macOS: a pretend center (sample data starts unasked, so the prompt can be seen).
    func reminderController() -> ReminderController {
        guard usesInMemoryDatabase else {
            return ReminderController(center: SystemReminderCenter(), defaults: .standard)
        }
        let permission: NotificationPermission = isUITesting ? uiTestNotifications : .notDetermined
        return ReminderController(center: FakeReminderCenter(permission: permission), defaults: nil)
    }

    /// Where the welcome-back state is kept: nowhere in the in-memory modes.
    func welcomeBackStore() -> WelcomeBackStore {
        WelcomeBackStore(defaults: usesInMemoryDatabase ? nil : .standard)
    }
}

/// The app's sense of "now": the real clock, or (Debug, in-memory modes only) a fixed day for UI
/// tests and a day offset for time travel.
@MainActor
final class AppClock {
    var fixedDay: DayKey?
    /// Days added to now (Debug time travel).
    var offsetDays = 0
    /// Seconds added on top (Debug ▸ Skip to Next Report).
    var extraSeconds: TimeInterval = 0

    init(fixedDay: DayKey? = nil) { self.fixedDay = fixedDay }

    func now() -> Date {
        // Noon on a fixed day, so the day-end time never moves it to another day.
        let base = fixedDay.map { DayClock().date(on: $0, hour: 12, minute: 0) } ?? Date()
        let shifted = offsetDays == 0 ? base
            : Calendar(identifier: .gregorian).date(byAdding: .day, value: offsetDays, to: base) ?? base
        return shifted.addingTimeInterval(extraSeconds)
    }
}
