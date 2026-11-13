import Core
import Foundation
@testable import Persistence
import Testing

@Suite struct ExportTests {
    static let exportedAt = Date(timeIntervalSince1970: 1_794_585_600) // 2026-11-13T16:00:00Z

    /// Two habits (one paused, with a target change, rest, check, dismissal), a note, a letter
    /// with an answer, and changed settings.
    static func seeded() throws -> (Repository, read: HabitID, walk: HabitID) {
        let repo = try makeRepository()
        let read = try repo.addHabit(name: "Read", identity: "a reader", kind: .amount(unit: "pages"), target: 10,
                                     schedule: .everyDay, today: d("2026-11-01"))
        let walk = try repo.addHabit(name: "Walk", kind: .yesNo, schedule: Schedule([.monday, .wednesday, .friday])!,
                                     today: d("2026-11-02"))
        try repo.changeTarget(of: read, to: 12, today: d("2026-11-05"), source: .suggested)
        for day in ["2026-11-01", "2026-11-02", "2026-11-04"] { try repo.setDone(true, habit: read, on: d(day), today: d(day)) }
        try repo.setRested(true, habit: read, today: d("2026-11-05"))
        try repo.setDone(true, habit: walk, on: d("2026-11-02"), today: d("2026-11-02"))
        try repo.deactivate(walk, today: d("2026-11-06"))
        try repo.dismissSuggestion(.levelUp, habit: read, today: d("2026-11-06"))
        try repo.recordAutomaticityCheck(.mostly, habit: read, today: d("2026-11-07"))
        try repo.setNote("Read before bed", on: d("2026-11-04"), today: d("2026-11-04"))
        try repo.updateSettings { $0.dayEndHour = 2; $0.reminderEnabled = false }
        let clock = DayClock(timeZone: TimeZone(identifier: "UTC")!)
        let due = ReportSchedule(clock: clock).dueReports(lastCoveredWeekEnd: nil, lastMonthlyPeriodEnd: nil, firstUseDay: d("2026-11-01"),
                                                          now: clock.date(on: d("2026-11-08"), hour: 19, minute: 0))
        let report = try repo.deliver(ReportSnapshot.weekly(due[0], data: try repo.appData(), previousObstacle: nil),
                                      at: Date(timeIntervalSince1970: 1_794_164_400))
        try repo.setAnswer("Late meetings. Read at lunch.", to: .obstacle, report: report)
        return (repo, read, walk)
    }

    /// The exported file's exact format. A change here is a format change: bump
    /// `DataExport.currentVersion` if a field is renamed or removed.
    @Test func exportFormat() throws {
        let (repo, read, walk) = try Self.seeded()
        let json = String(decoding: try repo.export(at: Self.exportedAt), as: UTF8.self)
        #expect(json == Self.expected.replacingOccurrences(of: "<READ>", with: read.key)
            .replacingOccurrences(of: "<WALK>", with: walk.key))
    }

    @Test func roundTripsAndExportsEvenUnreadableHabits() throws {
        let (repo, read, _) = try Self.seeded()
        try repo.execute("UPDATE habitDays SET state = 'skipped' WHERE day = '2026-11-01'")
        #expect((try? repo.appData().habit(read)?.history.get()) == nil) // unreadable in the app…
        let export = try JSONDecoder.export.decode(DataExport.self, from: try repo.export(at: Self.exportedAt))
        // …but still exported as stored (the unknown state isn't "done").
        #expect(export.habits.first { $0.id == read.key }?.done == ["2026-11-02", "2026-11-04"])
        #expect(export.version == 1)
    }

    static let expected = """
        {
          "exportedAt" : "2026-11-13T16:00:00Z",
          "format" : "66 Days export",
          "habits" : [
            {
              "activePeriods" : [
                {
                  "start" : "2026-11-01"
                }
              ],
              "automaticityChecks" : [
                {
                  "answer" : 4,
                  "day" : "2026-11-07"
                }
              ],
              "createdDay" : "2026-11-01",
              "done" : [
                "2026-11-01",
                "2026-11-02",
                "2026-11-04"
              ],
              "id" : "<READ>",
              "identity" : "a reader",
              "kind" : "amount",
              "name" : "Read",
              "rested" : [
                "2026-11-05"
              ],
              "schedules" : [
                {
                  "days" : [
                    "Sun",
                    "Mon",
                    "Tue",
                    "Wed",
                    "Thu",
                    "Fri",
                    "Sat"
                  ],
                  "from" : "2026-11-01",
                  "source" : "initial"
                }
              ],
              "suggestionsDismissed" : [
                {
                  "day" : "2026-11-06",
                  "kind" : "levelUp"
                }
              ],
              "targets" : [
                {
                  "amount" : 10,
                  "from" : "2026-11-01",
                  "source" : "initial"
                },
                {
                  "amount" : 12,
                  "from" : "2026-11-05",
                  "source" : "suggested"
                }
              ],
              "unit" : "pages"
            },
            {
              "activePeriods" : [
                {
                  "end" : "2026-11-06",
                  "endReason" : "paused",
                  "start" : "2026-11-02"
                }
              ],
              "automaticityChecks" : [

              ],
              "createdDay" : "2026-11-02",
              "done" : [
                "2026-11-02"
              ],
              "id" : "<WALK>",
              "kind" : "yesNo",
              "name" : "Walk",
              "rested" : [

              ],
              "schedules" : [
                {
                  "days" : [
                    "Mon",
                    "Wed",
                    "Fri"
                  ],
                  "from" : "2026-11-02",
                  "source" : "initial"
                }
              ],
              "suggestionsDismissed" : [

              ],
              "targets" : [

              ]
            }
          ],
          "notes" : [
            {
              "day" : "2026-11-04",
              "text" : "Read before bed"
            }
          ],
          "reports" : [
            {
              "answers" : {
                "obstacle" : "Late meetings. Read at lunch."
              },
              "deliveryDay" : "2026-11-08",
              "kind" : "weekly",
              "periodEnd" : "2026-11-07",
              "periodStart" : "2026-11-01"
            }
          ],
          "settings" : {
            "appearance" : "light",
            "dayEndHour" : 2,
            "reduceMotion" : "matchSystem",
            "reminder" : "off",
            "sounds" : true,
            "weeklyReport" : "Sun 18:00"
          },
          "version" : 1
        }
        """
}

extension JSONDecoder {
    static var export: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
