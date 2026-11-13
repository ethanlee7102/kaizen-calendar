import Foundation
import SQLiteData

/// Opens the app's SQLite database and brings its schema up to date.
public enum AppDatabase {
    /// `~/Library/Application Support/66 Days/66Days.sqlite`. In the sandboxed app this is
    /// inside the app's container. (An App Group path comes later, for the iPhone widget.)
    public static func defaultURL() throws -> URL {
        let folder = URL.applicationSupportDirectory.appending(path: "66 Days", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "66Days.sqlite")
    }

    /// The database file at `url`, created and migrated if needed.
    public static func open(at url: URL) throws -> any DatabaseWriter {
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        try Schema.migrator.migrate(pool)
        return pool
    }

    /// A fresh in-memory database, for tests and previews.
    public static func inMemory() throws -> any DatabaseWriter {
        let queue = try DatabaseQueue(configuration: configuration)
        try Schema.migrator.migrate(queue)
        return queue
    }

    static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "66 Days"
        return configuration
    }
}
