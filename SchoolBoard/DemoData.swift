import BoardCore
import Foundation

/// Sample board shown when no feeds are configured (or when launched with `-demo`).
/// Titles mirror real Classroom / Muse items, laid out around the current week.
enum DemoData {
    static func items(now: Date, calendar: Calendar = .current) -> [BoardItem] {
        let schedule = Schedule(calendar: calendar)
        let monday = schedule.week(for: now).weekdays[0]

        func at(_ dayOffset: Int, _ hour: Int? = nil, _ minute: Int = 0) -> (Date, Date, Bool) {
            let day = schedule.day(dayOffset, from: monday)
            guard let hour else { return (day, schedule.day(1, from: day), true) }
            let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            return (start, start.addingTimeInterval(3600), false)
        }

        let rows: [(Int, Int?, Int, String, ItemKind, String?, String, Bool)] = [
            // day, hour, minute, kid, kind, course, title, missing
            (-5, nil, 0, "Maya", .homework, "Math", "Constructions Retake", true),
            (0, nil, 0, "Maya", .homework, "ELA", "Study 15 minutes for the vocab quiz", false),
            (0, nil, 0, "Maya", .deadline, nil, "Science field trip — permission slip due", false),
            (0, 15, 0, "Leo", .event, nil, "Running Club", false),
            (1, nil, 0, "Maya", .homework, "Math", "Online practice: Congruence 3", false),
            (1, nil, 0, "Leo", .homework, "Reading", "Reading log — 20 minutes", false),
            (1, 12, 30, "Maya", .event, nil, "Car Club meeting", false),
            (2, 7, 15, "Maya", .event, nil, "Band sectional — Brass", false),
            (2, nil, 0, "Leo", .deadline, nil, "Safety program opt-out due", false),
            (2, 14, 45, "Leo", .event, nil, "Fall Chorus rehearsal", false),
            (3, nil, 0, "Maya", .test, "Math", "Unit 2 Test", false),
            (3, nil, 0, "Maya", .test, "ELA", "Vocabulary Practice Quiz", false),
            (3, nil, 0, "Leo", .homework, "Math", "Multiplication facts practice", false),
            (3, 15, 0, "Maya", .event, nil, "Math Club", false),
            (4, nil, 0, "Maya", .homework, "ELA", "30 minutes of vocabulary practice", false),
            (4, nil, 0, "Leo", .event, nil, "Crazy Hair Day", false),
            (5, 13, 0, "Maya", .event, nil, "Community Parade (volunteer band)", false),
            (6, 6, 30, "Leo", .event, nil, "Fun run volunteer shift", false),
            (7, nil, 0, "Maya", .noSchool, nil, "Fall Holiday - No School", false),
            (7, nil, 0, "Leo", .noSchool, nil, "Fall Holiday - No School", false),
            (8, nil, 0, "Maya", .homework, "Social Studies", "Chapter 3 vocabulary", false),
            (9, nil, 0, "Leo", .test, "Spelling", "Spelling test — Unit 4", false),
            (10, nil, 0, "Maya", .homework, "Math", "Workbook lessons 19–20", false),
            (11, nil, 0, "Maya", .event, nil, "End of 1st Quarter!", false),
            (14, nil, 0, "Maya", .test, "Math", "Unit 3 Quiz", false),
            (16, 19, 0, "Maya", .event, nil, "Band trip parent meeting", false),
            (18, nil, 0, "Leo", .homework, "Science", "Leaf collection project", false),
            (22, nil, 0, "Maya", .test, "ELA", "Vocabulary Unit Test", false),
        ]

        return rows.enumerated().map { index, row in
            let (day, hour, minute, kid, kind, course, title, missing) = row
            let (start, end, allDay) = at(day, hour, minute)
            return BoardItem(id: "demo-\(index)", kid: kid, kind: kind, title: title, course: course,
                             start: start, end: end, isAllDay: allDay, isMissing: missing)
        }
    }
}
