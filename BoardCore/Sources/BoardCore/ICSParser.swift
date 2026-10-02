import Foundation

/// One VEVENT from an iCalendar feed (RFC 5545), as published by Google Calendar.
public struct ICSEvent: Sendable {
    public var uid: String
    public var summary: String
    public var description: String
    public var location: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Zone the event's wall-clock times are defined in (used for recurrence math).
    public var timeZone: TimeZone
    public var rule: RecurrenceRule?
    public var exceptionDates: Set<Date>
    /// Set on an edited instance of a recurring event; identifies the instance it replaces.
    public var recurrenceID: Date?
    public var isCancelled: Bool
}

/// Minimal iCalendar reader: handles line folding, text escapes, TZID / UTC / floating /
/// all-day dates, RRULE, EXDATE and RECURRENCE-ID. Nested components (VALARM) are ignored.
public enum ICSParser {
    struct Property {
        let name: String
        let params: [String: String]
        let value: String
    }

    /// - Parameter displayTimeZone: zone all-day dates are pinned to (the device's zone).
    public static func parse(_ text: String, displayTimeZone: TimeZone = .current) -> [ICSEvent] {
        var calendarTimeZone = displayTimeZone
        var events: [ICSEvent] = []
        var stack: [String] = []
        var props: [Property] = []

        for line in unfold(text) {
            guard let prop = parseLine(line) else { continue }
            switch prop.name {
            case "BEGIN":
                stack.append(prop.value.uppercased())
                if prop.value.uppercased() == "VEVENT" { props = [] }
            case "END":
                if prop.value.uppercased() == "VEVENT", stack.last == "VEVENT",
                   let event = makeEvent(props, calendarTimeZone: calendarTimeZone, displayTimeZone: displayTimeZone) {
                    events.append(event)
                }
                if !stack.isEmpty { stack.removeLast() }
            default:
                if stack.last == "VEVENT" {
                    props.append(prop)
                } else if stack.last == "VCALENDAR", prop.name == "X-WR-TIMEZONE",
                          let tz = TimeZone(identifier: prop.value) {
                    calendarTimeZone = tz
                }
            }
        }
        return events
    }

    // MARK: - Lines

    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(text.count / 40)
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            var line = Substring(raw)
            if line.last == "\r" { line = line.dropLast() }
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(String(line))
            }
        }
        return lines
    }

    static func parseLine(_ line: String) -> Property? {
        var inQuotes = false
        var colon: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            else if c == ":" && !inQuotes { colon = i; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])

        var parts: [Substring] = []
        var current = head.startIndex
        inQuotes = false
        for i in head.indices {
            if head[i] == "\"" { inQuotes.toggle() }
            else if head[i] == ";" && !inQuotes {
                parts.append(head[current..<i])
                current = head.index(after: i)
            }
        }
        parts.append(head[current...])

        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq].uppercased()
            let val = part[part.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            params[key] = val
        }
        return Property(name: parts[0].uppercased(), params: params, value: value)
    }

    static func unescape(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var escaping = false
        for c in text {
            if escaping {
                switch c {
                case "n", "N": out.append("\n")
                default: out.append(c)  // \, \; \\
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    // MARK: - Events

    static func makeEvent(_ props: [Property], calendarTimeZone: TimeZone, displayTimeZone: TimeZone) -> ICSEvent? {
        var uid = UUID().uuidString
        var summary = "", description = "", location = ""
        var start: ParsedDate?, end: ParsedDate?
        var ruleText: String?
        var exdates = Set<Date>()
        var recurrenceID: Date?
        var cancelled = false

        for p in props {
            switch p.name {
            case "UID": uid = p.value
            case "SUMMARY": summary = unescape(p.value).trimmingCharacters(in: .whitespaces)
            case "DESCRIPTION": description = unescape(p.value)
            case "LOCATION": location = unescape(p.value)
            case "DTSTART": start = parseDate(p.value, params: p.params, calendarTimeZone: calendarTimeZone, displayTimeZone: displayTimeZone)
            case "DTEND": end = parseDate(p.value, params: p.params, calendarTimeZone: calendarTimeZone, displayTimeZone: displayTimeZone)
            case "RRULE": ruleText = p.value
            case "EXDATE":
                for v in p.value.split(separator: ",") {
                    if let d = parseDate(String(v), params: p.params, calendarTimeZone: calendarTimeZone, displayTimeZone: displayTimeZone) {
                        exdates.insert(d.date)
                    }
                }
            case "RECURRENCE-ID":
                recurrenceID = parseDate(p.value, params: p.params, calendarTimeZone: calendarTimeZone, displayTimeZone: displayTimeZone)?.date
            case "STATUS": cancelled = p.value.uppercased() == "CANCELLED"
            default: break
            }
        }

        guard let start else { return nil }
        let endDate: Date
        if let end, end.date > start.date {
            endDate = end.date
        } else if start.isAllDay {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = displayTimeZone
            endDate = cal.date(byAdding: .day, value: 1, to: start.date) ?? start.date
        } else {
            endDate = start.date
        }

        let zone = start.isAllDay ? displayTimeZone : start.timeZone
        let rule = ruleText.flatMap { RecurrenceRule(parsing: $0, calendarTimeZone: zone, displayTimeZone: displayTimeZone) }

        return ICSEvent(
            uid: uid, summary: summary, description: description, location: location,
            start: start.date, end: endDate, isAllDay: start.isAllDay, timeZone: zone,
            rule: rule, exceptionDates: exdates, recurrenceID: recurrenceID, isCancelled: cancelled
        )
    }

    // MARK: - Dates

    struct ParsedDate {
        let date: Date
        let isAllDay: Bool
        let timeZone: TimeZone
    }

    /// Parses `20261002`, `20261002T150000`, `20261002T150000Z`.
    static func parseDate(_ raw: String, params: [String: String], calendarTimeZone: TimeZone, displayTimeZone: TimeZone) -> ParsedDate? {
        let value = Array(raw.trimmingCharacters(in: .whitespaces).utf8)
        func num(_ from: Int, _ len: Int) -> Int? {
            guard from + len <= value.count else { return nil }
            var n = 0
            for b in value[from..<(from + len)] {
                guard b >= 48 && b <= 57 else { return nil }
                n = n * 10 + Int(b - 48)
            }
            return n
        }
        guard let y = num(0, 4), let mo = num(4, 2), let d = num(6, 2) else { return nil }

        var comps = DateComponents(year: y, month: mo, day: d)
        let isDateOnly = params["VALUE"] == "DATE" || value.count == 8
        var cal = Calendar(identifier: .gregorian)

        if isDateOnly {
            cal.timeZone = displayTimeZone
            guard let date = cal.date(from: comps) else { return nil }
            return ParsedDate(date: date, isAllDay: true, timeZone: displayTimeZone)
        }

        guard value.count >= 15, let h = num(9, 2), let mi = num(11, 2), let s = num(13, 2) else { return nil }
        comps.hour = h; comps.minute = mi; comps.second = s
        let zone: TimeZone
        if value.last == UInt8(ascii: "Z") {
            zone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) {
            zone = tz
        } else {
            zone = calendarTimeZone
        }
        cal.timeZone = zone
        guard let date = cal.date(from: comps) else { return nil }
        // Recurrence math should use the event's real zone, not UTC.
        return ParsedDate(date: date, isAllDay: false, timeZone: zone.identifier == "UTC" ? calendarTimeZone : zone)
    }
}
