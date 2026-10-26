import BoardCore
import SwiftUI
import WidgetKit

/// Watch-face complication: what's due on the next school day, plus a count of missing work.
@main
struct SchoolBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SchoolBoardNextUp", provider: Provider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("School Board")
        .description("What's due next and any missing work.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Timeline

struct BoardEntry: TimelineEntry {
    let date: Date
    /// nil until the watch app has saved its first snapshot.
    let items: [BoardItem]?
    let kidColors: [String: Color]
}

/// Reads the snapshot the watch app saves; the app reloads these timelines whenever it saves one.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        entry(at: .now, items: DemoData.items(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        completion(entry(at: .now, items: BoardSnapshot.load()?.items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let items = BoardSnapshot.load()?.items
        let now = Date.now
        // One entry per hour for a day, so "today" flips to "tomorrow" at 3 pm and at midnight
        // even if the app hasn't refreshed in the meantime.
        let entries = (0..<24).map { entry(at: now.addingTimeInterval(Double($0) * 3600), items: items) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, items: [BoardItem]?) -> BoardEntry {
        let config = BoardStore.loadConfig()
        return BoardEntry(date: date, items: items,
                          kidColors: Dictionary(uniqueKeysWithValues: config.kids.map { ($0.name, Color(hex: $0.color)) }))
    }
}

// MARK: - What to show

/// The day the kids care about next: today until 3 pm, then the next day that has anything on it.
struct Glance {
    let day: Date?
    let items: [BoardItem]
    let noSchool: BoardItem?
    let missing: Int
    let schedule: Schedule
    let now: Date

    init(entry: BoardEntry, schedule: Schedule = Schedule()) {
        self.schedule = schedule
        now = entry.date
        let all = entry.items ?? []
        let today = schedule.calendar.startOfDay(for: now)
        let cutoff = schedule.day(-30, from: today)
        missing = all.filter { $0.isMissing && $0.start >= cutoff }.count

        let first = schedule.calendar.component(.hour, from: now) >= 15 ? 1 : 0
        let found = (first..<(first + 7)).lazy
            .map { schedule.day($0, from: today) }
            .map { day in (day, schedule.items(on: day, from: all).filter { !$0.isMissing }) }
            .first { !$0.1.isEmpty }
        day = found?.0
        noSchool = found?.1.first { $0.kind == .noSchool }
        items = found?.1.filter { $0.kind != .noSchool } ?? []
    }

    /// Tests, homework and deadlines: the things that need doing.
    var dueCount: Int { items.filter { $0.isSchoolwork || $0.kind == .deadline }.count }

    var dayName: String {
        guard let day else { return "Week" }
        if schedule.isSameDay(day, now) { return "Today" }
        if schedule.isSameDay(day, schedule.day(1, from: now)) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    var shortDayName: String {
        guard let day else { return "WEEK" }
        return day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }
}

// MARK: - Views

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry

    var body: some View {
        let glance = Glance(entry: entry)
        if entry.items == nil {
            NoDataView(family: family)
        } else {
            switch family {
        case .accessoryCircular: CircularView(glance: glance)
        case .accessoryInline: InlineView(glance: glance)
        case .accessoryCorner: CornerView(glance: glance)
            default: RectangularView(glance: glance, kidColors: entry.kidColors)
            }
        }
    }
}

/// Shown until the watch app has run once and saved what to display.
private struct NoDataView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("SCHOOL BOARD").font(Theme.font(13, .heavy)).foregroundStyle(Theme.today)
                Text("Open the app to load").font(Theme.font(14, .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text("School Board: open app")
        case .accessoryCorner:
            Image(systemName: "checklist").font(.system(size: 20, weight: .semibold))
                .widgetLabel { Text("Open app") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "checklist").font(.system(size: 20, weight: .semibold))
            }
        }
    }
}

private struct RectangularView: View {
    let glance: Glance
    let kidColors: [String: Color]
    private let maxRows = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(glance.dayName.uppercased())
                    .foregroundStyle(Theme.today)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if glance.missing > 0 {
                    Label("\(glance.missing) missing", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.test)
                }
            }
            .font(Theme.font(13, .heavy))

            if let noSchool = glance.noSchool {
                Label(noSchool.title, systemImage: "sun.max.fill")
                    .foregroundStyle(Theme.noSchool)
                    .font(Theme.font(14, .bold))
                    .lineLimit(1)
            }
            if glance.items.isEmpty && glance.noSchool == nil {
                Text("All clear this week")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(glance.items.prefix(maxRows)) { item in
                // "Maya  TEST Unit 2 Test": the kid's name in their color, then what's due.
                (Text(item.kid ?? "School")
                    .fontWeight(.heavy)
                    .foregroundColor(item.kid.flatMap { kidColors[$0] } ?? Theme.secondary)
                 + Text(" " + rowText(item)))
                    .font(Theme.font(14, item.isSchoolwork ? .bold : .medium))
                    .lineLimit(1)
            }
            if glance.items.count > maxRows {
                Text("+\(glance.items.count - maxRows) more")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowText(_ item: BoardItem) -> String {
        let prefix = item.kind == .test ? "TEST " : item.kind == .deadline ? "DUE " : ""
        return prefix + item.title
    }
}

private struct CircularView: View {
    let glance: Glance

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(glance.shortDayName)
                    .font(Theme.font(10, .heavy))
                    .widgetAccentable()
                if glance.noSchool != nil && glance.dueCount == 0 {
                    Image(systemName: "sun.max.fill").font(.system(size: 18, weight: .bold))
                } else {
                    Text("\(glance.dueCount)").font(Theme.font(22, .bold))
                }
                if glance.missing > 0 {
                    Text("\(glance.missing)!")
                        .font(Theme.font(10, .heavy))
                        .foregroundStyle(Theme.test)
                }
            }
        }
    }
}

private struct InlineView: View {
    let glance: Glance

    var body: some View {
        if glance.missing > 0 {
            Text("⚠︎ \(glance.missing) missing · \(glance.shortDayName.capitalized) \(glance.dueCount) due")
        } else if let first = glance.items.first {
            let more = glance.items.count > 1 ? " +\(glance.items.count - 1)" : ""
            Text("\(glance.dayName): \(first.kid.map { "\($0) " } ?? "")\(first.title)\(more)")
        } else if let noSchool = glance.noSchool {
            Text("\(glance.dayName): \(noSchool.title)")
        } else {
            Text("School: all clear")
        }
    }
}

private struct CornerView: View {
    let glance: Glance

    var body: some View {
        Image(systemName: glance.missing > 0 ? "exclamationmark.triangle.fill" : "checklist")
            .font(.system(size: 20, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                Text(glance.missing > 0 ? "\(glance.missing) missing" : "\(glance.shortDayName.capitalized) \(glance.dueCount) due")
            }
    }
}
