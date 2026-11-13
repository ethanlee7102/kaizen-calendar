import Core
import Foundation
@testable import Persistence
import SQLiteData
import Testing

@Suite struct SchemaTests {
    static let tables = [
        "activePeriods", "appSettings", "automaticityChecks", "dayNotes", "firstTimeNotesSeen", "habitDays",
        "habits", "milestonesSeen", "reportAnswers", "reports", "scheduleChanges", "suggestionDismissals",
        "targetChanges", "unlocks",
    ]

    @Test func migratesAnEmptyDatabase() throws {
        let database = try AppDatabase.inMemory()
        let tables = try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table'
                AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name
                """)
        }
        #expect(tables == Self.tables)
        #expect(try database.read { try Bool.fetchOne($0, sql: "PRAGMA foreign_keys") } == true)
    }

    @Test func opensAFileAndReopensIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "66days-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "test.sqlite")

        let id = try Repository(database: try AppDatabase.open(at: url))
            .addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-13"))
        // Migrating again is a no-op and the data is still there.
        let reopened = Repository(database: try AppDatabase.open(at: url))
        #expect(try reopened.appData().habits.map(\.id) == [id])
    }

    /// CloudKit sync (SQLiteData) refuses UNIQUE constraints other than the primary key
    /// (rows that must be unique use `StableID` instead), and every table needs one primary key.
    @Test func schemaStaysCloudKitReady() throws {
        let database = try AppDatabase.inMemory()
        try database.read { db in
            for table in Self.tables {
                let uniqueOrigins = try String.fetchAll(db, sql: "SELECT origin FROM pragma_index_list(?) WHERE \"unique\" = 1",
                                                        arguments: [table])
                #expect(uniqueOrigins.allSatisfy { $0 == "pk" }, "\(table) has a UNIQUE constraint")
                let primaryKeys = try Int.fetchOne(db, sql: "SELECT count(*) FROM pragma_table_info(?) WHERE pk > 0", arguments: [table])
                #expect(primaryKeys == 1, "\(table) needs one primary key")
                let reserved: Set<String> = ["creationDate", "creatorUserRecordID", "etag", "lastModifiedUserRecordID",
                                             "modificationDate", "modifiedByDevice", "recordChangeTag", "recordID", "recordType"]
                for column in try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table]) {
                    #expect(!reserved.contains(column), "\(table) uses a reserved CloudKit name")
                }
                // SQLiteData's sync engine supports only CASCADE, SET NULL and SET DEFAULT.
                for action in try String.fetchAll(db, sql: "SELECT on_delete FROM pragma_foreign_key_list(?)", arguments: [table]) {
                    #expect(["CASCADE", "SET NULL", "SET DEFAULT"].contains(action), "\(table): ON DELETE \(action)")
                }
            }
        }
    }
}

@Suite struct StableIDTests {
    @Test func sameInputsGiveTheSameVersion5ID() {
        let a = StableID.make("day", "abc", "2026-11-08")
        #expect(a == StableID.make("day", "abc", "2026-11-08"))
        #expect(a != StableID.make("day", "abc", "2026-11-09"))
        #expect(a != StableID.make("note", "abc", "2026-11-08"))
        let text = a.uuidString
        #expect(text[text.index(text.startIndex, offsetBy: 14)] == "5")
        #expect("89AB".contains(text[text.index(text.startIndex, offsetBy: 19)]))
    }

    /// Stored IDs depend on these exact values: changing the namespace or the hashing would
    /// make old rows unmatchable (duplicates after sync). Expected values come from Python's
    /// `uuid.uuid5`, an independent RFC 9562 implementation.
    @Test func idsMatchTheRFCAndNeverChange() {
        #expect(StableID.make("settings").uuidString == "9E2C69E1-43C7-5C00-8E8A-C55452CCAA05")
        let habit = HabitID(UUID(uuidString: "6F0F5C3E-2B7D-4C1A-9E2F-0D1A2B3C4D5E")!)
        #expect(RowID.habitDay(habit, d("2026-11-08")) == "ea93aaf7-7b36-576a-bccf-739d6c4b287c")
    }
}
