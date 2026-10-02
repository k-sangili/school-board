import Foundation

/// Date math for the week and month screens.
public struct Schedule: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) { self.calendar = calendar }

    public struct WeekLayout: Equatable, Sendable {
        public let weekdays: [Date]   // Mon–Fri
        public let weekend: [Date]    // Sat, Sun
        /// On Sat/Sun the board looks ahead: this weekend comes first, then next week's school days.
        public let weekendFirst: Bool
    }

    /// The school week to show for `now`, shifted by `offset` weeks.
    public func week(for now: Date, offset: Int = 0) -> WeekLayout {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)  // 1 = Sun … 7 = Sat
        let isWeekend = weekday == 1 || weekday == 7
        let daysSinceMonday = (weekday + 5) % 7
        let thisMonday = day(-daysSinceMonday, from: today)

        if isWeekend {
            let saturday = weekday == 7 ? today : day(-1, from: today)
            let saturdayShifted = day(7 * offset, from: saturday)
            let nextMonday = day(2, from: saturdayShifted)
            return WeekLayout(weekdays: (0..<5).map { day($0, from: nextMonday) },
                              weekend: [saturdayShifted, day(1, from: saturdayShifted)],
                              weekendFirst: true)
        }
        let monday = day(7 * offset, from: thisMonday)
        return WeekLayout(weekdays: (0..<5).map { day($0, from: monday) },
                          weekend: [day(5, from: monday), day(6, from: monday)],
                          weekendFirst: false)
    }

    /// First day of the month `offset` months from `now`.
    public func month(for now: Date, offset: Int = 0) -> Date {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }

    /// Whole weeks (Sun–Sat) covering the month: 35 or 42 days.
    public func monthGrid(for monthStart: Date) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 1
        let first = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let daysNeeded = (cal.dateComponents([.day], from: first, to: monthEnd).day ?? 35)
        let weeks = Int((Double(daysNeeded) / 7).rounded(.up))
        return (0..<(weeks * 7)).map { day($0, from: first) }
    }

    /// Items that touch `day`, in display order.
    public func items(on day: Date, from items: [BoardItem]) -> [BoardItem] {
        let start = calendar.startOfDay(for: day)
        let end = self.day(1, from: start)
        return items
            .filter { $0.start < end && max($0.end, $0.start.addingTimeInterval(1)) > start }
            .sorted(by: BoardItem.displayOrder)
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    public func day(_ n: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date
    }
}
