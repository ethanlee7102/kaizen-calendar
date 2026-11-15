import AppShell
import Foundation
import Persistence

/// How the app was launched. UI tests (AppUITests) launch it in a test mode so they never touch
/// the user's database or note position. Release builds always run normally.
struct LaunchOptions {
    /// An in-memory database and a separate note-position key.
    var isUITesting = false
    /// Start the note from its initial position (UI tests only).
    var resetsPositions = false
    /// Placeholder habit rows at launch (UI tests only; Phase 3 placeholder content).
    var placeholderRows = 0

    static let uiTesting = "-uiTesting"
    static let resetPositions = "-uiTestResetPositions"
    static let rows = "-placeholderRows"

    static var current: LaunchOptions {
        #if DEBUG
        LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
        LaunchOptions()
        #endif
    }

    init() {}

    init(arguments: [String]) {
        isUITesting = arguments.contains(Self.uiTesting)
        guard isUITesting else { return }
        resetsPositions = arguments.contains(Self.resetPositions)
        if let index = arguments.firstIndex(of: Self.rows), index + 1 < arguments.count,
           let rows = Int(arguments[index + 1]) {
            placeholderRows = min(max(rows, 0), 5)
        }
    }

    func openRepository() throws -> Repository {
        Repository(database: isUITesting ? try AppDatabase.inMemory() : try AppDatabase.open(at: AppDatabase.defaultURL()))
    }

    func positionStore() -> PositionStore {
        let store = isUITesting ? PositionStore(key: "uiTests.note.positions") : PositionStore()
        if resetsPositions { store.reset() }
        return store
    }
}
