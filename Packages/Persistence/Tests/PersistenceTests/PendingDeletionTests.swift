import Core
import Foundation
@testable import Persistence
import Testing

@MainActor
@Suite struct PendingDeletionTests {
    struct Busy: Error {}

    /// Phase 5 review: a restore that throws must not lose the deletion.
    @Test func aFailedUndoKeepsTheDeletionForAnotherTry() throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-10"))
        let pending = PendingDeletion()
        pending.start(try repo.deleteHabit(id))

        #expect(throws: Busy.self) { try pending.undo { _ in throw Busy() } }
        #expect(pending.deleted?.id == id, "still undoable")

        let restored = try pending.undo { try repo.restore($0, today: d("2026-11-14")) }
        #expect(restored == id)
        #expect(pending.deleted == nil)
        #expect(try repo.appData().habit(id) != nil)
        #expect(try pending.undo { _ in Issue.record("nothing left to undo") } == nil)
    }

    @Test func theUndoExpires() async throws {
        let repo = try makeRepository()
        let id = try repo.addHabit(name: "Read", kind: .yesNo, schedule: .everyDay, today: d("2026-11-10"))
        let pending = PendingDeletion(window: .milliseconds(50))
        pending.start(try repo.deleteHabit(id))
        for _ in 0..<100 where pending.deleted != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(pending.deleted == nil)
    }
}

/// "My day ends at" starts with the next day (user's choice after the Phase 5 review).
@MainActor
@Suite struct DayEndSettingTests {
    /// Tuesday Nov 17, 00:30 in the Mac's time zone.
    static let halfPastMidnight = DayClock().date(on: d("2026-11-17"), hour: 0, minute: 30)

    @Test func choosingALaterHourAfterMidnightKeepsTodayAndIsStored() async throws {
        let repo = try makeRepository()
        let model = AppModel(repository: repo, now: { Self.halfPastMidnight })
        #expect(model.today == d("2026-11-17"))

        try repo.setDayEndHour(1, now: Self.halfPastMidnight)
        let settings = try repo.appData().settings
        #expect(settings.dayEndHour == 0)
        #expect(settings.dayEndChange == DayEnd.Change(hour: 1, after: d("2026-11-17")))
        #expect(settings.dayEnd.chosenHour == 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.today == d("2026-11-17"), "today didn't move back to Monday")

        // Picking midnight again the same day cancels it.
        try repo.setDayEndHour(0, now: Self.halfPastMidnight)
        #expect(try repo.appData().settings.dayEndChange == nil)
        #expect(throws: Repository.Failure.invalidSettings) { try repo.setDayEndHour(5, now: Self.halfPastMidnight) }
    }

    @Test func aStoredChangeWithABadValueFallsBackAndIsReported() throws {
        let repo = try makeRepository()
        try repo.setDayEndHour(2, now: Self.halfPastMidnight)
        try repo.execute(#"UPDATE "appSettings" SET "pendingDayEndAfter" = 'soon'"#)
        let data = try repo.appData()
        #expect(data.settings.dayEndChange == nil)
        #expect(data.problems.map(\.error) == [.badDay(table: "appSettings", value: "soon")])
    }
}
