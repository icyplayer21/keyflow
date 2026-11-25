import Foundation

/// The days you practised, for Learn ▸ Today.
///
/// A day counts when anything was saved on it: a lesson round, a Finger
/// Focus round or check, a Typing Mechanics round, a Key Repetition session,
/// a Daily Flow passage, or a Practice or Test session. Skipping a lesson
/// stage is not practice and does not count. Nothing is scored: these are
/// dates and a count of days in a row, nothing more.
public struct PracticeDays: Sendable, Equatable {
    /// The start of each day with practice.
    public let days: Set<Date>
    public let calendar: Calendar

    public init(dates: some Sequence<Date>, calendar: Calendar = .current) {
        self.calendar = calendar
        days = Set(dates.map { calendar.startOfDay(for: $0) })
    }

    public func practised(on date: Date) -> Bool {
        days.contains(calendar.startOfDay(for: date))
    }

    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        public let practised: Bool
        public let isToday: Bool
        /// Later in the week than today.
        public let isAhead: Bool
        public var id: Date { date }
    }

    /// The seven days of the calendar week containing `today`, in order. The
    /// week starts on the first weekday of the calendar (the Mac's region).
    public func week(of today: Date) -> [Day] {
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        let todayStart = calendar.startOfDay(for: today)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = calendar.startOfDay(for: date)
            return Day(date: day, practised: days.contains(day), isToday: day == todayStart, isAhead: day > todayStart)
        }
    }

    /// Days in a row with practice, ending today. Until you have practised
    /// today, the run ending yesterday still counts, so it never reads as
    /// broken before the day is over.
    public func streak(asOf today: Date) -> Int {
        var day = calendar.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
