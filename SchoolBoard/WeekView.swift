import BoardCore
import SwiftUI

struct WeekView: View {
    let layout: Schedule.WeekLayout
    let items: [BoardItem]
    let now: Date
    let schedule: Schedule

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if layout.weekendFirst { weekend }
            ForEach(layout.weekdays, id: \.self) { day in
                DayColumn(day: day, items: schedule.items(on: day, from: items), now: now,
                          schedule: schedule, maxItems: 6)
            }
            if !layout.weekendFirst { weekend }
        }
    }

    private var weekend: some View {
        VStack(spacing: 16) {
            ForEach(layout.weekend, id: \.self) { day in
                DayColumn(day: day, items: schedule.items(on: day, from: items), now: now,
                          schedule: schedule, maxItems: 2)
            }
        }
    }
}

struct DayColumn: View {
    let day: Date
    let items: [BoardItem]
    let now: Date
    let schedule: Schedule
    let maxItems: Int

    private var isToday: Bool { schedule.isSameDay(day, now) }
    private var isPast: Bool { day < schedule.calendar.startOfDay(for: now) }
    private var noSchool: BoardItem? { items.first { $0.kind == .noSchool } }
    private var visible: [BoardItem] { items.filter { $0.kind != .noSchool } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if visible.isEmpty {
                Text(noSchool == nil ? "Nothing scheduled" : "")
                    .font(Theme.font(20, .medium))
                    .foregroundStyle(Theme.secondary.opacity(0.6))
            }
            ForEach(visible.prefix(maxItems)) { item in
                ItemCard(item: item)
            }
            if visible.count > maxItems {
                Text("+\(visible.count - maxItems) more")
                    .font(Theme.font(18, .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(noSchool != nil ? Theme.noSchool.opacity(0.10) : (isToday ? Theme.panelRaised : Theme.panel))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isToday ? Theme.today : .clear, lineWidth: 4)
        )
        .opacity(isPast ? 0.45 : 1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(Theme.font(22, .heavy))
                    .foregroundStyle(isToday ? Theme.today : Theme.secondary)
                Text(day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(Theme.font(22, .semibold))
                    .foregroundStyle(isToday ? Theme.text : Theme.secondary)
                Spacer(minLength: 0)
                if isToday {
                    Text("TODAY")
                        .font(Theme.font(15, .heavy))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.today))
                }
            }
            if let noSchool {
                Label(noSchool.title, systemImage: "sun.max.fill")
                    .font(Theme.font(18, .bold))
                    .foregroundStyle(Theme.noSchool)
                    .lineLimit(2)
            }
        }
    }
}

struct ItemCard: View {
    @Environment(BoardStore.self) private var store
    let item: BoardItem

    private var color: Color { store.color(for: item.kid) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(color).frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.kid?.uppercased() ?? "SCHOOL")
                        .font(Theme.font(15, .heavy))
                        .foregroundStyle(color)
                    if let course = item.course {
                        Text(course)
                            .font(Theme.font(15, .bold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    badge
                }
                Text(item.title)
                    .font(Theme.font(item.isSchoolwork ? 24 : 21, item.isSchoolwork ? .bold : .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.isAllDay {
                    Text(item.start.formatted(date: .omitted, time: .shortened))
                        .font(Theme.font(17, .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)  // hug content; don't stretch to the column
        .background(RoundedRectangle(cornerRadius: 14).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(item.isMissing ? Theme.test : .clear, lineWidth: 2))
    }

    private var background: Color {
        switch item.kind {
        case .test: Theme.test.opacity(0.16)
        case .homework: color.opacity(0.14)
        case .deadline: Theme.deadline.opacity(0.12)
        default: Color.white.opacity(0.04)
        }
    }

    @ViewBuilder private var badge: some View {
        if item.isMissing {
            Badge(text: "MISSING", color: Theme.test)
        } else if item.kind == .test {
            Badge(text: "TEST", color: Theme.test)
        } else if item.kind == .deadline {
            Badge(text: "DUE", color: Theme.deadline)
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.font(13, .heavy))
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}
