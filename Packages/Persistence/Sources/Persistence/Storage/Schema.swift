import SQLiteData

/// Database migrations. Each one runs once, in order, and is never edited after it ships;
/// later changes are new migrations. Follow the CloudKit rules in `Records.swift`.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1: habits, history, notes, reports, settings") { db in
            try createVersion1(db)
        }
        // "My day ends at" changes start with the next day (Phase 5 review, user's choice): the
        // chosen hour and the day it was chosen on, while the old hour still applies.
        migrator.registerMigration("v2: pending day-end change") { db in
            try #sql(#"ALTER TABLE "appSettings" ADD COLUMN "pendingDayEndHour" INTEGER"#).execute(db)
            try #sql(#"ALTER TABLE "appSettings" ADD COLUMN "pendingDayEndAfter" TEXT"#).execute(db)
        }
        // Phase 7: first-time notes were dropped (info buttons cover them; user's choice), and
        // onboarding is remembered as one row. A database that already has habits was set up
        // before onboarding existed, so it counts as onboarded.
        migrator.registerMigration("v3: onboarding, no first-time notes") { db in
            try #sql(#"DROP TABLE "firstTimeNotesSeen""#).execute(db)
            try #sql("""
                CREATE TABLE "onboarding" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "completedAt" TEXT NOT NULL
                ) STRICT
                """).execute(db)
            try db.execute(
                sql: """
                    INSERT INTO "onboarding" ("id", "completedAt")
                    SELECT ?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE EXISTS (SELECT 1 FROM "habits")
                    """,
                // `RowID.onboarding`, written out: a shipped migration must not depend on code
                // that could change (pinned by `idsMatchTheRFCAndNeverChange`).
                arguments: ["5a0140d9-6abe-5bdd-aae3-967e4b23515d"])
        }
        return migrator
    }

    private static func createVersion1(_ db: Database) throws {
        // Days are "yyyy-MM-dd" text: it sorts in date order, so range queries and indexes
        // work, and it stays readable in the file and in exports.
        try #sql("""
            CREATE TABLE "habits" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "name" TEXT NOT NULL,
              "identity" TEXT NOT NULL DEFAULT '',
              "kind" TEXT NOT NULL,
              "unit" TEXT NOT NULL DEFAULT '',
              "sortOrder" INTEGER NOT NULL DEFAULT 0,
              "createdDay" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "scheduleChanges" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "habitID" TEXT NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
              "day" TEXT NOT NULL,
              "weekdays" INTEGER NOT NULL CHECK ("weekdays" BETWEEN 1 AND 127),
              "source" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "targetChanges" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "habitID" TEXT NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
              "day" TEXT NOT NULL,
              "amount" INTEGER NOT NULL CHECK ("amount" >= 1),
              "source" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "activePeriods" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "habitID" TEXT NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
              "start" TEXT NOT NULL,
              "end" TEXT,
              "endReason" TEXT
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "habitDays" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "habitID" TEXT NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
              "day" TEXT NOT NULL,
              "state" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "dayNotes" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "day" TEXT NOT NULL,
              "text" TEXT NOT NULL DEFAULT ''
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "reports" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "kind" TEXT NOT NULL,
              "periodStart" TEXT,
              "periodEnd" TEXT,
              "habitID" TEXT REFERENCES "habits"("id") ON DELETE SET NULL,
              "deliveryDay" TEXT NOT NULL,
              "deliveredAt" TEXT NOT NULL,
              "openedAt" TEXT,
              "filedAt" TEXT,
              "snapshot" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "reportAnswers" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "reportID" TEXT NOT NULL REFERENCES "reports"("id") ON DELETE CASCADE,
              "question" TEXT NOT NULL,
              "text" TEXT NOT NULL DEFAULT ''
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "automaticityChecks" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "habitID" TEXT NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
              "day" TEXT NOT NULL,
              "answer" INTEGER NOT NULL CHECK ("answer" BETWEEN 1 AND 5)
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "suggestionDismissals" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "habitID" TEXT NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
              "kind" TEXT NOT NULL,
              "day" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "milestonesSeen" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "habitID" TEXT NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
              "milestone" INTEGER NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "firstTimeNotesSeen" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "note" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "unlocks" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "unlock" TEXT NOT NULL,
              "unlockedAt" TEXT NOT NULL,
              "noticeDismissedAt" TEXT,
              "seenAt" TEXT
            ) STRICT
            """).execute(db)

        try #sql("""
            CREATE TABLE "appSettings" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "dayEndHour" INTEGER NOT NULL,
              "reportWeekday" INTEGER NOT NULL,
              "reportHour" INTEGER NOT NULL,
              "reportMinute" INTEGER NOT NULL,
              "reminderEnabled" INTEGER NOT NULL,
              "reminderHour" INTEGER NOT NULL,
              "reminderMinute" INTEGER NOT NULL,
              "soundsEnabled" INTEGER NOT NULL,
              "reduceMotion" TEXT NOT NULL,
              "appearance" TEXT NOT NULL
            ) STRICT
            """).execute(db)

        // Lookups by habit (and day). Not UNIQUE: see `StableID`.
        for (table, columns) in [
            ("scheduleChanges", #""habitID", "day""#),
            ("targetChanges", #""habitID", "day""#),
            ("activePeriods", #""habitID", "start""#),
            ("habitDays", #""habitID", "day""#),
            ("dayNotes", #""day""#),
            ("reports", #""deliveredAt""#),
            ("reports", #""habitID""#),
            ("reportAnswers", #""reportID""#),
            ("automaticityChecks", #""habitID""#),
            ("suggestionDismissals", #""habitID""#),
            ("milestonesSeen", #""habitID""#),
        ] {
            let name = "index_\(table)_on_" + columns.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: ", ", with: "_")
            try db.execute(sql: #"CREATE INDEX "\#(name)" ON "\#(table)"(\#(columns))"#)
        }
    }
}
