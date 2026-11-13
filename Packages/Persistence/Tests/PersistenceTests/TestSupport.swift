import Core
import Foundation
@testable import Persistence
import SQLiteData

/// "2026-11-08" → DayKey. Crashes on bad input (tests only).
func d(_ string: String) -> DayKey { DayKey(string)! }

func makeRepository() throws -> Repository {
    Repository(database: try AppDatabase.inMemory())
}

extension Repository {
    /// The habit's history as stored, or a test failure.
    func history(_ id: HabitID) throws -> HabitHistory {
        try appData().habit(id)!.history.get()
    }

    func execute(_ sql: String) throws {
        try database.write { try $0.execute(sql: sql) }
    }
}
