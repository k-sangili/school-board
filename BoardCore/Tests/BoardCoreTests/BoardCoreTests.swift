import Foundation
import Testing
@testable import BoardCore

let la = TimeZone(identifier: "America/Los_Angeles")!

var laCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = la
    return c
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    laCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

let config = BoardConfig(
    kids: [
        .init(name: "Maya", color: "#4C9AFF", tags: ["OMS", "Band"]),
        .init(name: "Leo", color: "#FFA94D", tags: ["Pine"]),
    ],
    feeds: []
)
let taggedFeed = BoardConfig.Feed(name: "Muse", url: "https://example", mode: .tagged)

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "ics", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

func sampleItems() throws -> [BoardItem] {
    let window = DateInterval(start: date(2026, 9, 1), end: date(2026, 11, 1))
    return BoardBuilder.items(icsText: try fixture("sample"), feed: taggedFeed, config: config, window: window, timeZone: la)
}

@Suite struct ParserTests {
    @Test func unfoldsAndUnescapes() throws {
        let events = ICSParser.parse(try fixture("sample"), displayTimeZone: la)
        let orange = try #require(events.first { $0.uid == "hw-orange@muse" })
        #expect(orange.summary == "[Maya] ELA: Take the Vocabulary Practice Quiz and Complete the Study Plan (in your ELA Notebook)")
        let unit2 = try #require(events.first { $0.uid == "hw-unit2@muse" })
        #expect(unit2.description == "Topics: congruence, proofs\nView in Classroom")
        #expect(unit2.isAllDay)
        #expect(unit2.start == date(2026, 10, 2))
    }

    @Test func parsesTimeZones() throws {
        let events = ICSParser.parse(try fixture("sample"), displayTimeZone: la)
        let flight = try #require(events.first { $0.uid == "flight@personal" })
        #expect(flight.start == date(2026, 10, 1, 7, 0))  // 14:00Z = 7:00 PDT
        let soccer = try #require(events.first { $0.uid == "soccer@muse" })
        #expect(soccer.start == date(2026, 9, 28, 15, 0))
    }

    @Test func allDayWithoutEndLastsOneDay() throws {
        let events = ICSParser.parse(try fixture("sample"), displayTimeZone: la)
        let missing = try #require(events.first { $0.uid == "hw-missing@muse" })
        #expect(missing.end == date(2026, 9, 11))
    }

    @Test func weeklyRecurrenceHonorsExdateAndOverride() throws {
        let events = ICSParser.parse(try fixture("sample"), displayTimeZone: la)
        let window = DateInterval(start: date(2026, 9, 1), end: date(2026, 10, 23))
        let club = ICSParser.occurrences(of: events, in: window)
            .filter { $0.uid == "mathclub@muse" }
            .sorted { $0.start < $1.start }
        #expect(club.map(\.start) == [
            date(2026, 9, 24, 15), date(2026, 10, 1, 15),
            // Oct 8 excluded by EXDATE; Oct 15 replaced by the moved instance
            date(2026, 10, 15, 15, 30), date(2026, 10, 22, 15),
        ])
        #expect(club[2].summary == "[OMS] Math Club (moved)")
    }

    @Test func monthlyNthWeekdayWithCount() throws {
        let events = ICSParser.parse(try fixture("sample"), displayTimeZone: la)
        let window = DateInterval(start: date(2026, 1, 1), end: date(2027, 6, 1))
        let hsc = ICSParser.occurrences(of: events, in: window).filter { $0.uid == "hsc@muse" }.map(\.start).sorted()
        #expect(hsc == [date(2026, 9, 3, 19), date(2026, 10, 1, 19), date(2026, 11, 5, 19)])
    }

    @Test func weeklyAcrossDSTKeepsWallClock() throws {
        let events = ICSParser.parse(try fixture("sample"), displayTimeZone: la)
        let window = DateInterval(start: date(2026, 10, 30), end: date(2026, 11, 4))
        let drops = ICSParser.occurrences(of: events, in: window).filter { $0.uid == "dropkids@personal" }.map(\.start).sorted()
        // DST ends Nov 1; still 7:00 local on both sides
        #expect(drops == [date(2026, 10, 30, 7), date(2026, 11, 2, 7), date(2026, 11, 3, 7)])
    }

    @Test func monthlyByDayParsesNegativeOrdinal() {
        let rule = RecurrenceRule(parsing: "FREQ=MONTHLY;BYDAY=-1FR", calendarTimeZone: la, displayTimeZone: la)
        #expect(rule?.byDay == [.init(ordinal: -1, weekday: 6)])
    }
}

@Suite struct ClassifierTests {
    @Test func homeworkTestsAndMissing() throws {
        let items = try sampleItems()
        let unit2 = try #require(items.first { $0.id.hasPrefix("hw-unit2") })
        #expect(unit2.kind == .test)
        #expect(unit2.kid == "Maya")
        #expect(unit2.course == "Math")
        #expect(unit2.title == "Unit 2 Test")

        let orange = try #require(items.first { $0.id.hasPrefix("hw-orange") })
        #expect(orange.kind == .test)  // "Quiz" in the title
        #expect(orange.course == "ELA")

        let missing = try #require(items.first { $0.id.hasPrefix("hw-missing") })
        #expect(missing.isMissing)
        #expect(missing.kind == .homework)
        #expect(missing.title == "Constructions Retake")
    }

    @Test func tagsRouteEventsToKids() throws {
        let items = try sampleItems()
        let slip = try #require(items.first { $0.id.hasPrefix("oms-slip") })
        #expect(slip.kid == "Maya")
        #expect(slip.kind == .deadline)
        #expect(slip.title == "Science field trip — permission slip due")

        let optout = try #require(items.first { $0.id.hasPrefix("pine-optout") })
        #expect(optout.kid == "Leo")
        #expect(optout.kind == .deadline)

        let soccer = try #require(items.first { $0.id.hasPrefix("soccer") })
        #expect(soccer.kid == "Maya")
        #expect(soccer.title == "Soccer Tryouts Begin - Tentative")
        #expect(soccer.kind == .event)
    }

    @Test func personalAndCancelledEventsAreHidden() throws {
        let items = try sampleItems()
        #expect(!items.contains { $0.id.hasPrefix("flight") })
        #expect(!items.contains { $0.id.hasPrefix("dropkids") })
        #expect(!items.contains { $0.id.hasPrefix("cancelled") })
    }

    @Test func schoolFeedKeepsAllDayOnly() {
        let feed = BoardConfig.Feed(name: "OMS", url: "https://x", mode: .school, kid: "Maya", allDayOnly: true)
        let classifier = Classifier(config: config)
        let noSchool = Occurrence(uid: "a", summary: "Fall Holiday - No School", description: "",
                                  start: date(2026, 10, 12), end: date(2026, 10, 13), isAllDay: true)
        let game = Occurrence(uid: "b", summary: "8th Grade Boys Basketball Game vs. Price @ Price", description: "",
                              start: date(2026, 10, 1, 15, 45), end: date(2026, 10, 1, 17), isAllDay: false)
        #expect(classifier.classify(noSchool, feed: feed)?.kind == .noSchool)
        #expect(classifier.classify(game, feed: feed) == nil)
    }
}

@Suite struct ScheduleTests {
    let schedule = Schedule(calendar: laCalendar)

    @Test func weekdayShowsCurrentSchoolWeek() {
        let week = schedule.week(for: date(2026, 10, 2, 9))  // Friday
        #expect(week.weekdays.first == date(2026, 9, 28))
        #expect(week.weekend == [date(2026, 10, 3), date(2026, 10, 4)])
        #expect(!week.weekendFirst)
    }

    @Test func weekendLooksAhead() {
        let week = schedule.week(for: date(2026, 10, 4, 9))  // Sunday
        #expect(week.weekendFirst)
        #expect(week.weekend == [date(2026, 10, 3), date(2026, 10, 4)])
        #expect(week.weekdays.first == date(2026, 10, 5))
    }

    @Test func monthGridCoversWholeWeeks() {
        let grid = schedule.monthGrid(for: schedule.month(for: date(2026, 10, 2)))
        #expect(grid.first == date(2026, 9, 27))  // Sunday before Oct 1
        #expect(grid.count == 35)
        #expect(grid.last == date(2026, 10, 31))
    }

    @Test func itemsOnDayAreOrdered() throws {
        let day = schedule.items(on: date(2026, 10, 2), from: try sampleItems())
        #expect(day.map(\.kind) == [.test, .test, .deadline])
    }
}

/// Runs against a real school calendar when SCHOOL_ICS points at a downloaded .ics file.
@Suite struct RealFeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOOL_ICS"] != nil))
    func schoolCalendar() throws {
        let path = ProcessInfo.processInfo.environment["SCHOOL_ICS"]!
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let feed = BoardConfig.Feed(name: "School", url: "https://x", mode: .school, kid: "Maya", allDayOnly: true)
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now.addingTimeInterval(90 * 86_400))

        let clock = ContinuousClock()
        var items: [BoardItem] = []
        let elapsed = clock.measure {
            items = BoardBuilder.items(icsText: text, feed: feed, config: config, window: window, timeZone: la)
        }
        print("School feed: \(items.count) items in \(elapsed)")
        for item in items.sorted(by: { $0.start < $1.start }) {
            print("  \(item.start.formatted(.iso8601.year().month().day()))  \(item.kind)  \(item.title)")
        }
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.isAllDay })
        // Duplicate entries (same title, same day) are collapsed.
        let keys = items.map { "\($0.title)|\($0.start)" }
        #expect(Set(keys).count == keys.count)
    }
}
