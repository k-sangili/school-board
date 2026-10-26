import BoardCore
import SwiftUI

/// The wrist version of the board: missing work first, then the next two weeks day by day.
struct AgendaView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now

    private let schedule = Schedule()
    private let daysAhead = 14

    var body: some View {
        NavigationStack {
            List {
                if !missing.isEmpty {
                    Section {
                        ForEach(missing) { row($0) }
                    } header: {
                        Label("Missing", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.test)
                    }
                }
                ForEach(days, id: \.self) { day in
                    DaySection(day: day, items: items(on: day), now: now, schedule: schedule) { row($0) }
                }
                Section { StatusFooter() }
            }
            .navigationTitle("School")
            .navigationDestination(for: BoardItem.self) { ItemDetail(item: $0) }
        }
        .task { await store.start() }
        .onChange(of: store.lastUpdated) { SchoolBoardWatchApp.publish(store.items) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = .now
            Task { await store.refresh() }
        }
    }

    private func row(_ item: BoardItem) -> some View {
        NavigationLink(value: item) { ItemRow(item: item) }
            .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(ItemStyle.background(item, color: store.color(for: item.kid))))
    }

    // MARK: - Derived

    /// Missing work from the last 30 days, oldest first (same rule as the TV board).
    private var missing: [BoardItem] {
        let cutoff = schedule.day(-30, from: now)
        return store.items.filter { $0.isMissing && $0.start >= cutoff }.sorted { $0.start < $1.start }
    }

    /// Today, plus any later day in the next two weeks that has something on it.
    private var days: [Date] {
        let today = schedule.calendar.startOfDay(for: now)
        return (0..<daysAhead).map { schedule.day($0, from: today) }
            .filter { $0 == today || !items(on: $0).isEmpty }
    }

    private func items(on day: Date) -> [BoardItem] {
        schedule.items(on: day, from: store.items).filter { !$0.isMissing }
    }
}

private struct DaySection<Row: View>: View {
    let day: Date
    let items: [BoardItem]
    let now: Date
    let schedule: Schedule
    @ViewBuilder let row: (BoardItem) -> Row

    private var noSchool: BoardItem? { items.first { $0.kind == .noSchool } }
    private var visible: [BoardItem] { items.filter { $0.kind != .noSchool } }

    var body: some View {
        Section {
            if let noSchool {
                Label(noSchool.title, systemImage: "sun.max.fill")
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.noSchool)
                    .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(Theme.noSchool.opacity(0.12)))
            }
            if items.isEmpty {
                Text("Nothing scheduled")
                    .font(Theme.font(15, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(visible) { row($0) }
        } header: {
            Text(title)
                .foregroundStyle(schedule.isSameDay(day, now) ? Theme.today : Theme.secondary)
        }
    }

    private var title: String {
        if schedule.isSameDay(day, now) { return "Today" }
        if schedule.isSameDay(day, schedule.day(1, from: now)) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

struct ItemRow: View {
    @Environment(BoardStore.self) private var store
    let item: BoardItem

    private var color: Color { store.color(for: item.kid) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule().fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.kid?.uppercased() ?? "SCHOOL")
                        .font(Theme.font(12, .heavy))
                        .foregroundStyle(color)
                    if let course = item.course {
                        Text(course)
                            .font(Theme.font(12, .bold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    ItemStyle.badge(item)
                }
                Text(item.title)
                    .font(Theme.font(15, item.isSchoolwork ? .bold : .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                if !item.isAllDay {
                    Text(item.start.formatted(date: .omitted, time: .shortened))
                        .font(Theme.font(12, .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ItemDetail: View {
    @Environment(BoardStore.self) private var store
    let item: BoardItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.kid ?? "School")
                        .font(Theme.font(15, .heavy))
                        .foregroundStyle(store.color(for: item.kid))
                    Spacer()
                    ItemStyle.badge(item)
                }
                if let course = item.course {
                    Text(course)
                        .font(Theme.font(14, .bold))
                        .foregroundStyle(Theme.secondary)
                }
                Text(item.title)
                    .font(Theme.font(18, .bold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(when)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var when: String {
        let day = item.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return item.isAllDay ? day : "\(day), \(item.start.formatted(date: .omitted, time: .shortened))"
    }
}

/// Colors and badges matching the TV board's `ItemCard`.
enum ItemStyle {
    static func background(_ item: BoardItem, color: Color) -> Color {
        switch item.kind {
        case .test: Theme.test.opacity(0.20)
        case .homework: color.opacity(0.18)
        case .deadline: Theme.deadline.opacity(0.16)
        default: Theme.panel
        }
    }

    @ViewBuilder static func badge(_ item: BoardItem) -> some View {
        if item.isMissing {
            WatchBadge(text: "MISSING", color: Theme.test)
        } else if item.kind == .test {
            WatchBadge(text: "TEST", color: Theme.test)
        } else if item.kind == .deadline {
            WatchBadge(text: "DUE", color: Theme.deadline)
        }
    }
}

private struct WatchBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.font(10, .heavy))
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color))
    }
}

private struct StatusFooter: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.isDemo {
                Text("DEMO DATA").font(Theme.font(12, .heavy)).foregroundStyle(Theme.deadline)
            } else if store.needsPersonalFeed {
                Text("Add your calendar’s iCal URL to BoardConfig.json to show homework")
                    .foregroundStyle(Theme.deadline)
            }
            if let problem = store.problems.first {
                Label(problem, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(Theme.deadline)
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(Theme.font(12, .medium))
        .foregroundStyle(Theme.secondary)
        .listRowBackground(Color.clear)
    }
}
