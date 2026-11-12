import SQLiteData

/// The app's database. Phase 2 adds the schema, migrations and the on-disk location;
/// for now this only proves the SQLiteData dependency builds and runs.
public enum AppDatabase {
    /// The SQLite library version, read from a fresh in-memory database.
    public static func sqliteVersion() throws -> String {
        let database = try DatabaseQueue()
        return try database.read { db in
            try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? ""
        }
    }
}
