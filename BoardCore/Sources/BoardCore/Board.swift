import Foundation

// MARK: - Configuration

public struct BoardConfig: Codable, Sendable {
    public struct Kid: Codable, Sendable, Hashable {
        public var name: String
        /// Hex color, e.g. "#4C9AFF".
        public var color: String
        /// Muse event tags that belong to this kid, e.g. ["OMS", "Band"].
        public var tags: [String]

        public init(name: String, color: String, tags: [String]) {
            self.name = name; self.color = color; self.tags = tags
        }
    }

    public enum Mode: String, Codable, Sendable {
        /// Only events whose titles carry a kid name or kid tag are shown (your personal calendar).
        case tagged
        /// A school's calendar: every event is shown for `kid`, optionally only all-day ones.
        case school
    }

    public struct Feed: Codable, Sendable, Hashable {
        public var name: String
        public var url: String
        public var mode: Mode
        public var kid: String?
        public var allDayOnly: Bool?

        public init(name: String, url: String, mode: Mode, kid: String? = nil, allDayOnly: Bool? = nil) {
            self.name = name; self.url = url; self.mode = mode; self.kid = kid; self.allDayOnly = allDayOnly
        }

        public var isConfigured: Bool { url.hasPrefix("https://") }
    }

    public var kids: [Kid]
    public var feeds: [Feed]
    public var weekSeconds: Double?
    public var monthSeconds: Double?
    public var refreshMinutes: Double?

    public init(kids: [Kid], feeds: [Feed], weekSeconds: Double? = nil, monthSeconds: Double? = nil, refreshMinutes: Double? = nil) {
        self.kids = kids; self.feeds = feeds
        self.weekSeconds = weekSeconds; self.monthSeconds = monthSeconds; self.refreshMinutes = refreshMinutes
    }
}

// MARK: - Board items

public enum ItemKind: Int, Sendable, Comparable {
    // Raw value = display priority within a day.
    case noSchool, test, homework, deadline, event, school

    public static func < (a: ItemKind, b: ItemKind) -> Bool { a.rawValue < b.rawValue }
}

public struct BoardItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let kid: String?
    public let kind: ItemKind
    public let title: String
    public let course: String?
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isMissing: Bool

    public init(id: String, kid: String?, kind: ItemKind, title: String, course: String? = nil,
                start: Date, end: Date, isAllDay: Bool, isMissing: Bool = false) {
        self.id = id; self.kid = kid; self.kind = kind; self.title = title; self.course = course
        self.start = start; self.end = end; self.isAllDay = isAllDay; self.isMissing = isMissing
    }

    public var isSchoolwork: Bool { kind == .test || kind == .homework }

    /// Display order within a day: no-school banner, missing work, tests, homework, deadlines,
    /// then timed events by start time.
    public static func displayOrder(_ a: BoardItem, _ b: BoardItem) -> Bool {
        if a.isMissing != b.isMissing { return a.isMissing }
        if a.kind != b.kind { return a.kind < b.kind }
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        return a.title < b.title
    }
}

// MARK: - Classification

/// Turns raw calendar occurrences into board items using Muse's title conventions:
///  - Homework:  `[Maya] Math: Unit 2 Test`, `[Maya] Math TEST: Unit 2 Test`, `⚠️ MISSING [Maya] ELA: …`
///  - Events:    `[OMS] Picture Make-Up Day`, `Soccer Tryouts Begin (OMS)`
public struct Classifier: Sendable {
    let kidsByName: [String: String]  // lowercased name → name
    let kidsByTag: [String: String]   // lowercased tag → kid name

    public init(config: BoardConfig) {
        var byName: [String: String] = [:], byTag: [String: String] = [:]
        for kid in config.kids {
            byName[kid.name.lowercased()] = kid.name
            for tag in kid.tags { byTag[tag.lowercased()] = kid.name }
        }
        kidsByName = byName
        kidsByTag = byTag
    }

    private static let bracketed = try! NSRegularExpression(pattern: #"^(?:\x{26A0}\x{FE0F}?\s*)?(MISSING\s*[:\-–—]?\s*)?\[([^\]]+)\]\s*(.+)$"#, options: [.caseInsensitive])
    private static let courseTitle = try! NSRegularExpression(pattern: #"^(.{1,30}?)(?:\s+(TEST|QUIZ|EXAM))?:\s+(.+)$"#)
    private static let suffixTag = try! NSRegularExpression(pattern: #"^(.+?)\s*\(([^)]+)\)\s*$"#)
    private static let testWords = try! NSRegularExpression(pattern: #"\b(test|quiz|exam|assessment|final)\b"#, options: [.caseInsensitive])
    private static let deadlineWords = try! NSRegularExpression(pattern: #"\b(due|deadline|last day|opt[- ]?out|permission slip)\b"#, options: [.caseInsensitive])
    private static let noSchoolWords = try! NSRegularExpression(pattern: #"no school|holiday|break\b|recess day|non-student day"#, options: [.caseInsensitive])

    public func classify(_ o: Occurrence, feed: BoardConfig.Feed) -> BoardItem? {
        let title = o.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let id = "\(o.uid)@\(Int(o.start.timeIntervalSince1970))"

        if feed.mode == .school {
            if feed.allDayOnly == true && !o.isAllDay { return nil }
            let kind: ItemKind = Self.matches(Self.noSchoolWords, title) ? .noSchool : .school
            return BoardItem(id: id, kid: feed.kid, kind: kind, title: title,
                             start: o.start, end: o.end, isAllDay: o.isAllDay)
        }

        if let m = Self.groups(Self.bracketed, title) {
            let missing = m[1] != nil || title.hasPrefix("\u{26A0}")
            let tag = m[2] ?? ""
            let rest = (m[3] ?? "").trimmingCharacters(in: .whitespaces)

            // [Kid] Course: Title → homework / test
            if let kid = kidsByName[tag.lowercased()] {
                var course: String?
                var name = rest
                var isTest = false
                if let c = Self.groups(Self.courseTitle, rest) {
                    course = c[1]
                    isTest = c[2] != nil
                    name = c[3] ?? rest
                }
                if !isTest { isTest = Self.matches(Self.testWords, name) }
                return BoardItem(id: id, kid: kid, kind: isTest ? .test : .homework, title: name, course: course,
                                 start: o.start, end: o.end, isAllDay: o.isAllDay, isMissing: missing)
            }
            // [Tag] Event → that kid's event
            if let kid = kidsByTag[tag.lowercased()] {
                return eventItem(id: id, kid: kid, title: rest, o)
            }
            return nil
        }

        if let m = Self.groups(Self.suffixTag, title), let tag = m[2], let kid = kidsByTag[tag.lowercased()] {
            return eventItem(id: id, kid: kid, title: m[1] ?? title, o)
        }
        return nil
    }

    private func eventItem(id: String, kid: String, title: String, _ o: Occurrence) -> BoardItem {
        let kind: ItemKind
        if Self.matches(Self.noSchoolWords, title) { kind = .noSchool }
        else if Self.matches(Self.deadlineWords, title) { kind = .deadline }
        else { kind = .event }
        return BoardItem(id: id, kid: kid, kind: kind, title: title,
                         start: o.start, end: o.end, isAllDay: o.isAllDay)
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func groups(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) }
        }
    }
}

// MARK: - Building

public enum BoardBuilder {
    /// Parses one feed's iCal text into board items overlapping `window`.
    public static func items(icsText: String, feed: BoardConfig.Feed, config: BoardConfig,
                             window: DateInterval, timeZone: TimeZone = .current) -> [BoardItem] {
        let events = ICSParser.parse(icsText, displayTimeZone: timeZone)
        let classifier = Classifier(config: config)
        let items = ICSParser.occurrences(of: events, in: window).compactMap { classifier.classify($0, feed: feed) }
        return deduplicated(items)
    }

    /// School calendars often carry the same event twice (separate UIDs); keep one per kid/title/start.
    public static func deduplicated(_ items: [BoardItem]) -> [BoardItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.kid ?? "")|\(item.title.lowercased())|\(Int(item.start.timeIntervalSince1970))"
            return seen.insert(key).inserted
        }
    }

    /// The span of data the board needs: last month through three months out.
    public static func window(around now: Date, calendar: Calendar = .current) -> DateInterval {
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let start = calendar.date(byAdding: .day, value: -45, to: monthStart) ?? now
        let end = calendar.date(byAdding: .month, value: 3, to: monthStart) ?? now
        return DateInterval(start: start, end: end)
    }
}
