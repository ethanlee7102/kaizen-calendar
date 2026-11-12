import Foundation
import Testing
@testable import Core

@Suite struct DayKeyTests {
    @Test func parsesAndPrints() throws {
        let day = try #require(DayKey("2026-11-08"))
        #expect(day.year == 2026 && day.month == 11 && day.day == 8)
        #expect(day.description == "2026-11-08")
        #expect(DayKey(year: 7, month: 1, day: 2)?.description == "0007-01-02")
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-11-31", "2026-1-01", "20261108", "", "2026-11-08x"])
    func rejectsInvalid(_ string: String) {
        #expect(DayKey(string) == nil)
    }

    @Test func leapYears() {
        #expect(DayKey("2028-02-29") != nil)
        #expect(DayKey("2000-02-29") != nil)
        #expect(DayKey("1900-02-29") == nil)
        #expect(d("2028-02-28").adding(days: 1) == d("2028-02-29"))
        #expect(d("2028-02-29").adding(days: 1) == d("2028-03-01"))
        #expect(d("2028-02-01").daysInMonth == 29)
    }

    @Test func arithmeticAcrossMonthsAndYears() {
        #expect(d("2026-12-31").adding(days: 1) == d("2027-01-01"))
        #expect(d("2027-01-01").adding(days: -1) == d("2026-12-31"))
        #expect(d("2026-01-01").days(to: d("2027-01-01")) == 365)
        #expect(d("2028-01-01").days(to: d("2029-01-01")) == 366)
        // Round-trips through Julian Day Numbers for a long span.
        var day = d("1999-12-25")
        for _ in 0..<5000 {
            let next = day.adding(days: 1)
            #expect(DayKey(year: next.year, month: next.month, day: next.day) == next)
            day = next
        }
    }

    @Test func weekdays() {
        #expect(d("2026-11-01").weekday == .sunday)
        #expect(d("2026-11-09").weekday == .monday)
        #expect(d("2000-01-01").weekday == .saturday)
        #expect(d("2026-11-11").startOfWeek == d("2026-11-08"))
        #expect(d("2026-11-11").endOfWeek == d("2026-11-14"))
        #expect(d("2026-11-08").startOfWeek == d("2026-11-08"))
    }

    @Test func rangesAndStriding() {
        let range = DayRange(d("2026-11-01"), d("2026-11-07"))
        #expect(range.count == 7)
        #expect(Array(range).last == d("2026-11-07"))
        #expect(range.contains(d("2026-11-04")))
        #expect(!range.contains(d("2026-11-08")))
        #expect((d("2026-10-30")...d("2026-11-02")).count == 4)
    }

    @Test func codableAsString() throws {
        let data = try JSONEncoder().encode([d("2026-11-08")])
        #expect(String(data: data, encoding: .utf8) == #"["2026-11-08"]"#)
        #expect(try JSONDecoder().decode([DayKey].self, from: data) == [d("2026-11-08")])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([DayKey].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
    }
}

@Suite struct ScheduleTests {
    @Test func weekdaySets() {
        let set = WeekdaySet([.monday, .wednesday, .friday])
        #expect(set.count == 3)
        #expect(set.weekdays == [.monday, .wednesday, .friday])
        #expect(WeekdaySet.all.count == 7)
        #expect(Schedule(days: []) == nil)
        #expect(Schedule.everyDay.isEveryDay)
        #expect(days(.monday).includes(d("2026-11-09")))
        #expect(!days(.monday).includes(d("2026-11-10")))
    }
}

@Suite struct DayClockTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    func date(_ string: String, _ tz: TimeZone) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        formatter.timeZone = tz
        return formatter.date(from: string)!
    }

    @Test func midnightDayEnd() {
        let clock = DayClock(timeZone: newYork, dayEndHour: 0)
        #expect(clock.day(for: date("2026-11-10T23:59:00", newYork)) == d("2026-11-10"))
        #expect(clock.day(for: date("2026-11-11T00:00:00", newYork)) == d("2026-11-11"))
    }

    @Test func lateDayEndCountsForThePreviousDay() {
        let clock = DayClock(timeZone: newYork, dayEndHour: 4)
        #expect(clock.day(for: date("2026-11-11T03:59:00", newYork)) == d("2026-11-10"))
        #expect(clock.day(for: date("2026-11-11T04:00:00", newYork)) == d("2026-11-11"))
        // New Year's night belongs to Dec 31.
        #expect(clock.day(for: date("2027-01-01T02:00:00", newYork)) == d("2026-12-31"))
    }

    @Test func springForwardGap() {
        // 2026-03-08: 2:00 → 3:00 in New York. With a 2am day end, the day starts at 3:00.
        let clock = DayClock(timeZone: newYork, dayEndHour: 2)
        #expect(clock.day(for: date("2026-03-08T01:59:00", newYork)) == d("2026-03-07"))
        #expect(clock.day(for: date("2026-03-08T03:00:00", newYork)) == d("2026-03-08"))
        let start = clock.start(of: d("2026-03-08"))
        #expect(start == date("2026-03-08T03:00:00", newYork))
        #expect(clock.day(for: start) == d("2026-03-08"))
        // The day is 23 hours long.
        #expect(clock.end(of: d("2026-03-08")).timeIntervalSince(start) == 23 * 3600)
    }

    @Test func fallBackRepeatedHour() {
        // 2026-11-01: 2:00 → 1:00 in New York. Both 1:30s belong to Oct 31 with a 2am day end.
        let clock = DayClock(timeZone: newYork, dayEndHour: 2)
        let first = date("2026-11-01T00:30:00", newYork).addingTimeInterval(3600) // 1:30 EDT
        let second = first.addingTimeInterval(3600)
        #expect(clock.day(for: first) == d("2026-10-31"))
        #expect(clock.day(for: second) == d("2026-10-31"))
        #expect(clock.day(for: second.addingTimeInterval(1800)) == d("2026-11-01"))
        #expect(clock.end(of: d("2026-10-31")).timeIntervalSince(clock.start(of: d("2026-10-31"))) == 25 * 3600)
    }

    @Test func followsTheCurrentTimeZone() {
        // The same moment is a different day in Tokyo and New York.
        let moment = date("2026-11-10T20:00:00", newYork)
        #expect(DayClock(timeZone: newYork).day(for: moment) == d("2026-11-10"))
        #expect(DayClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!).day(for: moment) == d("2026-11-11"))
    }

    @Test func wallClockTimes() {
        let clock = DayClock(timeZone: newYork)
        #expect(clock.date(on: d("2026-11-08"), hour: 18, minute: 0) == date("2026-11-08T18:00:00", newYork))
        #expect(clock.calendarDay(for: date("2026-11-09T01:00:00", newYork)) == d("2026-11-09"))
    }
}

@Suite struct MonthGridTests {
    @Test func sundayFirstGrid() {
        // November 2026 starts on a Sunday: 5 rows, no leading padding.
        let november = MonthGrid(year: 2026, month: 11)
        #expect(november.weeks.count == 5)
        #expect(november.weeks[0][0] == d("2026-11-01"))
        #expect(november.weeks[4][1] == d("2026-11-30"))
        #expect(november.weeks[4][2] == nil)
        #expect(november.days.count == 30)

        // August 2026 starts on a Saturday: 6 rows.
        let august = MonthGrid(year: 2026, month: 8)
        #expect(august.weeks.count == 6)
        #expect(august.weeks[0][5] == nil && august.weeks[0][6] == d("2026-08-01"))
        #expect(august.weeks.allSatisfy { $0.count == 7 })

        // February 2026 starts on a Sunday and has 28 days: exactly 4 rows.
        #expect(MonthGrid(year: 2026, month: 2).weeks.count == 4)
    }
}
