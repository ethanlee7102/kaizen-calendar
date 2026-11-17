#if DEBUG
import Core
import Foundation
import Persistence

/// Debug-only data for UI tests (`-uiTestSeed <scenario>`) and the sample-data mode
/// (`-sampleData`). Everything is written through the real `Repository`, stepping "today" through
/// past days, so the data is exactly what daily use would have made. Only used with an in-memory
/// database.
enum DebugData {
    enum Scenario {
        /// No habits.
        case empty
        /// `n` daily habits created today (Read, Walk, Floss, Stretch, Journal).
        case habits(Int)
        /// The habit-flow UI tests (`HabitFlowUITests`), as of `today`:
        /// - Read (10 pages, daily, 10 days old): done every day except 5 days ago (recovered the
        ///   next day) and yesterday, so today is a danger day.
        /// - Walk (yes/no, daily, 10 days old): done every day, pending today.
        case flows
        /// The notebook UI tests (`NotebookUITests`), as of `today`:
        /// - Read (10 pages, daily, 20 days old): done every day except 6 days ago (recovered).
        /// - Walk (yes/no, daily, 20 days old): done every day, pending today.
        /// - Stretch (yes/no, daily): 30 days old, done its first 10 days, paused 15 days ago.
        case notebook
        /// The letter UI tests (`ReportUITests`), as of Saturday `today`: Read (10 pages, daily)
        /// since 41 days ago, done every day except 11 days ago (recovered). Letters were
        /// delivered as the days passed; the one 13 days ago has an obstacle answer, and the
        /// newest (6 days ago) is in the envelope with a level-up suggestion.
        case letters
        /// The day-66 UI test: Walk (yes/no, daily) since 65 days ago, done every day before
        /// today (65 done days), so checking it off today brings the day-66 letter.
        case day66
        /// A month that shows every mark and line: seals, slices, a gold seam, a broken streak,
        /// a rest day, notes, a Mon/Wed/Fri habit, a new habit and a paused habit. Read started
        /// 70 days ago and reached day 66 yesterday, so there are letters too.
        case sample

        init?(_ text: String) {
            switch text {
            case "empty": self = .empty
            case "flows": self = .flows
            case "notebook": self = .notebook
            case "letters": self = .letters
            case "day66": self = .day66
            case "sample": self = .sample
            default:
                guard text.hasPrefix("habits:"), let n = Int(text.dropFirst("habits:".count)) else { return nil }
                self = .habits(min(max(n, 0), HabitRules.maxActiveHabits))
            }
        }
    }

    static let names = ["Read", "Walk", "Floss", "Stretch", "Journal"]

    static func seed(_ scenario: Scenario, into repository: Repository, today: DayKey) throws {
        switch scenario {
        case .empty:
            break
        case .habits(let n):
            for name in names.prefix(n) {
                try repository.addHabit(name: name, kind: .yesNo, schedule: .everyDay, today: today)
            }
        case .flows:
            let start = today.adding(days: -10)
            let read = try repository.addHabit(name: "Read", identity: "a reader", kind: .amount(unit: "pages"),
                                               target: 10, schedule: .everyDay, today: start)
            let walk = try repository.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: start)
            for day in start..<today {
                if day != today.adding(days: -5), day != today.adding(days: -1) {
                    try repository.setDone(true, habit: read, on: day, today: day)
                }
                try repository.setDone(true, habit: walk, on: day, today: day)
            }
        case .notebook:
            let start = today.adding(days: -20)
            let stretchStart = today.adding(days: -30)
            let stretch = try repository.addHabit(name: "Stretch", kind: .yesNo, schedule: .everyDay, today: stretchStart)
            for day in stretchStart..<stretchStart.adding(days: 10) {
                try repository.setDone(true, habit: stretch, on: day, today: day)
            }
            try repository.deactivate(stretch, today: today.adding(days: -15))
            let read = try repository.addHabit(name: "Read", identity: "a reader", kind: .amount(unit: "pages"),
                                               target: 10, schedule: .everyDay, today: start)
            let walk = try repository.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: start)
            for day in start..<today {
                if day != today.adding(days: -6) { try repository.setDone(true, habit: read, on: day, today: day) }
                try repository.setDone(true, habit: walk, on: day, today: day)
            }
            try repository.setNote("Read before bed, not after.", on: today.adding(days: -3), today: today.adding(days: -3))
        case .letters:
            let start = today.adding(days: -41)
            let read = try repository.addHabit(name: "Read", identity: "a reader", kind: .amount(unit: "pages"),
                                               target: 10, schedule: .everyDay, today: start)
            for day in start..<today {
                if day != today.adding(days: -11) { try repository.setDone(true, habit: read, on: day, today: day) }
                try deliver(repository, on: day)
                if day == today.adding(days: -13), let letter = try repository.reports().first {
                    try repository.setAnswer("Late meetings. Read at lunch instead.", to: .obstacle, report: letter.id)
                }
            }
        case .day66:
            let start = today.adding(days: -65)
            let walk = try repository.addHabit(name: "Walk", kind: .yesNo, schedule: .everyDay, today: start)
            for day in start..<today {
                try repository.setDone(true, habit: walk, on: day, today: day)
                try deliver(repository, on: day)
            }
        case .sample:
            try seedSample(into: repository, today: today)
        }
    }

    /// Delivers what was due by the end of `day`, as if the app ran that evening.
    private static func deliver(_ repository: Repository, on day: DayKey) throws {
        try repository.deliverDueReports(now: DayClock().date(on: day, hour: 23, minute: 0), today: day)
    }

    /// Replaces every habit with `n` new daily ones (UI tests: the note's height changes).
    static func replaceHabits(with n: Int, in repository: Repository, today: DayKey) throws {
        for habit in try repository.appData().habits { _ = try repository.deleteHabit(habit.id) }
        try seed(.habits(n), into: repository, today: today)
    }

    private static func seedSample(into repository: Repository, today: DayKey) throws {
        let start = today.adding(days: -24)
        // Read started 70 days ago: 46 done days before this month's pattern, 66 by yesterday.
        let readStart = today.adding(days: -70)
        let read = try repository.addHabit(name: "Read", identity: "a reader", kind: .amount(unit: "pages"),
                                           target: 10, schedule: .everyDay, today: readStart)
        for day in readStart..<start {
            try repository.setDone(true, habit: read, on: day, today: day)
            try deliver(repository, on: day)
        }
        let pushups = try repository.addHabit(name: "Pushups", kind: .amount(unit: "pushups"), target: 15,
                                              schedule: Schedule([.monday, .wednesday, .friday])!,
                                              today: start.adding(days: 3))
        let floss = try repository.addHabit(name: "Floss", kind: .yesNo, schedule: .everyDay,
                                            today: start.adding(days: 10))

        // Paused partway through the month (the notebook's inactive list).
        let journal = try repository.addHabit(name: "Journal", kind: .yesNo, schedule: .everyDay, today: start)

        let readMisses: Set<Int> = [6, 12, 13] // a recovered miss, then a broken streak
        let readRest = 18
        for offset in 0..<24 {
            let day = start.adding(days: offset)
            if offset == readRest {
                try repository.setRested(true, habit: read, today: day)
            } else if !readMisses.contains(offset) {
                try repository.setDone(true, habit: read, on: day, today: day)
            }
            if day >= start.adding(days: 3), Schedule([.monday, .wednesday, .friday])!.includes(day), offset != 9 {
                try repository.setDone(true, habit: pushups, on: day, today: day)
            }
            // Floss misses yesterday, so today is a danger day for it.
            if day >= start.adding(days: 10), offset != 23 {
                try repository.setDone(true, habit: floss, on: day, today: day)
            }
            if offset < 15 {
                try repository.setDone(true, habit: journal, on: day, today: day)
            } else if offset == 15 {
                try repository.deactivate(journal, today: day)
            }
            if offset % 5 == 2 {
                try repository.setNote("Read before bed, not after.", on: day, today: day)
            }
            try deliver(repository, on: day)
            // An obstacle answer on a weekly letter, so the next one shows it back.
            if let letter = try repository.reports().first, letter.kind == .weekly, letter.deliveryDay == day,
               letter.answers.isEmpty, offset < 18 {
                try repository.setAnswer("Busy evenings. Read in the morning instead.", to: .obstacle, report: letter.id)
            }
        }
        // Most older letters were read and filed; one stays unread in the archive.
        for (index, letter) in try repository.reports().enumerated() where index > 0 && letter.isNew == false {
            if index != 1 { try repository.markReportOpened(letter.id, at: Date()) }
        }
        try repository.addHabit(name: "Meditate", identity: "calm", kind: .yesNo, schedule: .everyDay, today: today)
    }
}
#endif
