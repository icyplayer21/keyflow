import Foundation
import Testing
@testable import KeyflowCore

@Suite struct PracticeDaysTests {
    /// A fixed calendar so the week and days don't depend on the Mac running the tests.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    private func day(_ d: Int, hour: Int = 12) -> Date {
        // November 2026: the 23rd is a Monday.
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    @Test func severalSessionsOnOneDayCountOnce() {
        let days = PracticeDays(dates: [day(24, hour: 8), day(24, hour: 21), day(24, hour: 23)], calendar: calendar)
        #expect(days.days.count == 1)
        #expect(days.practised(on: day(24, hour: 0)))
        #expect(!days.practised(on: day(23)))
    }

    @Test func theWeekRunsFromTheCalendarsFirstWeekday() {
        let days = PracticeDays(dates: [day(23), day(25), day(29)], calendar: calendar)
        let week = days.week(of: day(25))
        #expect(week.count == 7)
        #expect(week.first?.date == calendar.startOfDay(for: day(23)))
        #expect(week.map(\.practised) == [true, false, true, false, false, false, true])
        #expect(week.map(\.isToday) == [false, false, true, false, false, false, false])
        #expect(week.map(\.isAhead) == [false, false, false, true, true, true, true])
    }

    @Test func daysInARowEndToday() {
        let days = PracticeDays(dates: [day(20), day(22), day(23), day(24), day(25)], calendar: calendar)
        #expect(days.streak(asOf: day(25)) == 4)
    }

    @Test func aRunIsNotBrokenBeforeTheDayIsOver() {
        let days = PracticeDays(dates: [day(22), day(23), day(24)], calendar: calendar)
        #expect(days.streak(asOf: day(25)) == 3, "today has no practice yet")
        #expect(days.streak(asOf: day(26)) == 0, "a whole day was missed")
    }

    @Test func noPracticeIsZero() {
        let days = PracticeDays(dates: [Date](), calendar: calendar)
        #expect(days.streak(asOf: day(25)) == 0)
        #expect(days.week(of: day(25)).allSatisfy { !$0.practised })
    }
}
