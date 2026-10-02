import Foundation

/// The subset of RRULE that Google Calendar emits: DAILY / WEEKLY / MONTHLY / YEARLY with
/// INTERVAL, COUNT, UNTIL, BYDAY (incl. ordinals like 2TH, -1FR), BYMONTHDAY and WKST.
public struct RecurrenceRule: Sendable {
    public enum Frequency: String, Sendable { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

    public struct WeekdayRule: Sendable, Hashable {
        public let ordinal: Int?  // nil = every such weekday
        public let weekday: Int   // Calendar weekday: 1 = Sunday … 7 = Saturday
    }

    public var frequency: Frequency
    public var interval = 1
    public var count: Int?
    public var until: Date?
    public var byDay: [WeekdayRule] = []
    public var byMonthDay: [Int] = []
    public var weekStart = 2  // RFC 5545 default WKST=MO

    static let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    public init?(parsing text: String, calendarTimeZone: TimeZone, displayTimeZone: TimeZone) {
        var fields: [String: String] = [:]
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { fields[kv[0].uppercased()] = String(kv[1]) }
        }
        guard let freq = fields["FREQ"].flatMap({ Frequency(rawValue: $0.uppercased()) }) else { return nil }
        frequency = freq
        if let i = fields["INTERVAL"].flatMap(Int.init), i > 0 { interval = i }
        count = fields["COUNT"].flatMap(Int.init)
        if let u = fields["UNTIL"],
           let parsed = ICSParser.parseDate(u, params: [:], calendarTimeZone: calendarTimeZone, displayTimeZone: displayTimeZone) {
            // A date-only UNTIL includes that whole day.
            until = parsed.isAllDay ? parsed.date.addingTimeInterval(86_399) : parsed.date
        }
        if let wk = fields["WKST"], let d = Self.weekdays[wk.uppercased()] { weekStart = d }
        if let days = fields["BYDAY"] {
            byDay = days.split(separator: ",").compactMap { token in
                let t = token.uppercased()
                guard t.count >= 2, let wd = Self.weekdays[String(t.suffix(2))] else { return nil }
                let prefix = t.dropLast(2)
                return WeekdayRule(ordinal: prefix.isEmpty ? nil : Int(prefix), weekday: wd)
            }
        }
        if let md = fields["BYMONTHDAY"] {
            byMonthDay = md.split(separator: ",").compactMap { Int($0) }
        }
    }

    /// Start dates of every instance of `event` that overlaps `window`, excluding EXDATEs.
    public func occurrences(of event: ICSEvent, in window: DateInterval) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = event.timeZone
        cal.firstWeekday = weekStart

        let duration = event.end.timeIntervalSince(event.start)
        let time = cal.dateComponents([.hour, .minute, .second], from: event.start)
        var results: [Date] = []
        var emitted = 0
        var iterations = 0

        /// Returns false once the series is exhausted or past the window.
        func consider(_ day: Date) -> Bool {
            guard let start = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) else { return true }
            if start < event.start { return true }
            if let until, start > until { return false }
            if let count, emitted >= count { return false }
            emitted += 1
            if start >= window.end { return false }
            if start.addingTimeInterval(max(duration, 1)) > window.start, !event.exceptionDates.contains(start) {
                results.append(start)
            }
            return true
        }

        let anchor = cal.startOfDay(for: event.start)
        let maxIterations = 20_000

        switch frequency {
        case .daily:
            var i = 0
            while iterations < maxIterations, let day = cal.date(byAdding: .day, value: i * interval, to: anchor) {
                iterations += 1
                if !consider(day) { break }
                i += 1
            }

        case .weekly:
            let days = Set(byDay.isEmpty ? [cal.component(.weekday, from: event.start)] : byDay.map(\.weekday))
            guard let weekStartDate = cal.dateInterval(of: .weekOfYear, for: anchor)?.start else { break }
            var w = 0
            outer: while iterations < maxIterations, let base = cal.date(byAdding: .weekOfYear, value: w * interval, to: weekStartDate) {
                for offset in 0..<7 {
                    iterations += 1
                    guard let day = cal.date(byAdding: .day, value: offset, to: base) else { continue }
                    if days.contains(cal.component(.weekday, from: day)), !consider(day) { break outer }
                }
                w += 1
            }

        case .monthly:
            guard let monthStart = cal.dateInterval(of: .month, for: anchor)?.start else { break }
            let startDay = cal.component(.day, from: anchor)
            var m = 0
            outer: while iterations < maxIterations, let base = cal.date(byAdding: .month, value: m * interval, to: monthStart) {
                iterations += 1
                for day in monthlyCandidates(in: base, startDay: startDay, cal: cal) where !consider(day) {
                    break outer
                }
                m += 1
            }

        case .yearly:
            var y = 0
            while iterations < maxIterations, let day = cal.date(byAdding: .year, value: y * interval, to: anchor) {
                iterations += 1
                if !consider(day) { break }
                y += 1
            }
        }
        return results
    }

    private func monthlyCandidates(in monthStart: Date, startDay: Int, cal: Calendar) -> [Date] {
        guard let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let length = range.count
        var dayNumbers: [Int] = []

        if !byMonthDay.isEmpty {
            dayNumbers = byMonthDay.map { $0 > 0 ? $0 : length + $0 + 1 }
        } else if !byDay.isEmpty {
            let firstWeekday = cal.component(.weekday, from: monthStart)
            for rule in byDay {
                let first = (rule.weekday - firstWeekday + 7) % 7 + 1
                let all = Array(stride(from: first, through: length, by: 7))
                if let n = rule.ordinal {
                    let idx = n > 0 ? n - 1 : all.count + n
                    if all.indices.contains(idx) { dayNumbers.append(all[idx]) }
                } else {
                    dayNumbers += all
                }
            }
        } else {
            dayNumbers = [startDay]
        }

        return dayNumbers
            .filter { (1...length).contains($0) }
            .sorted()
            .compactMap { cal.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }
}

/// A concrete instance of an event, after recurrence expansion.
public struct Occurrence: Sendable, Hashable {
    public let uid: String
    public let summary: String
    public let description: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
}

extension ICSParser {
    /// Expands recurring events and applies EXDATE / RECURRENCE-ID / CANCELLED.
    public static func occurrences(of events: [ICSEvent], in window: DateInterval) -> [Occurrence] {
        var overridden: [String: Set<Date>] = [:]
        for e in events {
            if let rid = e.recurrenceID { overridden[e.uid, default: []].insert(rid) }
        }

        var out: [Occurrence] = []
        for e in events {
            let duration = e.end.timeIntervalSince(e.start)
            func emit(_ start: Date) {
                out.append(Occurrence(uid: e.uid, summary: e.summary, description: e.description,
                                      start: start, end: start.addingTimeInterval(duration), isAllDay: e.isAllDay))
            }

            if e.recurrenceID != nil || e.rule == nil {
                guard !e.isCancelled, e.start < window.end, max(e.end, e.start.addingTimeInterval(1)) > window.start else { continue }
                emit(e.start)
            } else if let rule = e.rule, !e.isCancelled {
                let skip = overridden[e.uid] ?? []
                for start in rule.occurrences(of: e, in: window) where !skip.contains(start) {
                    emit(start)
                }
            }
        }
        return out
    }
}
