import Persistence
import Testing

@Suite struct AppDatabaseTests {
    @Test func opensAnInMemoryDatabase() throws {
        let version = try AppDatabase.sqliteVersion()
        #expect(version.hasPrefix("3."))
    }
}
