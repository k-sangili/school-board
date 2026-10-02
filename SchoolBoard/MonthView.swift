import BoardCore
import SwiftUI

struct MonthView: View {
    let month: Date
    let items: [BoardItem]
    let now: Date
    let schedule: Schedule

    var body: some View {
        let days = schedule.monthGrid(for: month)
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }

        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { name in
                    Text(name)
                        .font(Theme.font(18, .heavy))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
            }
            ForEach(weeks, id: \.first) { week in
                HStack(spacing: 10) {
                    ForEach(week, id: \.self) { day in
                        MonthCell(day: day, items: schedule.items(on: day, from: items), now: now,
                                  inMonth: schedule.calendar.isDate(day, equalTo: month, toGranularity: .month),
                                  schedule: schedule)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct MonthCell: View {
    @Environment(BoardStore.self) private var store
    let day: Date
    let items: [BoardItem]
    let now: Date
    let inMonth: Bool
    let schedule: Schedule

    private var isToday: Bool { schedule.isSameDay(day, now) }
    private var isPast: Bool { day < schedule.calendar.startOfDay(for: now) }
    private var noSchool: Bool { items.contains { $0.kind == .noSchool } }
    private var visible: [BoardItem] { items.filter { $0.kind != .noSchool } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(day.formatted(.dateTime.day()))
                    .font(Theme.font(20, .bold))
                    .foregroundStyle(isToday ? Theme.background : Theme.text)
                    .frame(minWidth: 34, minHeight: 34)
                    .background(Circle().fill(isToday ? Theme.today : .clear))
                if noSchool {
                    Text("No School")
                        .font(Theme.font(14, .heavy))
                        .foregroundStyle(Theme.noSchool)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ForEach(visible.prefix(3)) { item in
                HStack(spacing: 6) {
                    Circle().fill(store.color(for: item.kid)).frame(width: 9, height: 9)
                    Text(label(item))
                        .font(Theme.font(15, item.isSchoolwork ? .bold : .medium))
                        .foregroundStyle(item.kind == .test || item.isMissing ? Theme.test : Theme.text)
                        .lineLimit(1)
                }
            }
            if visible.count > 3 {
                Text("+\(visible.count - 3) more")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(noSchool ? Theme.noSchool.opacity(0.12) : Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isToday ? Theme.today : .clear, lineWidth: 3))
        .opacity(inMonth ? (isPast ? 0.5 : 1) : 0.22)
    }

    private func label(_ item: BoardItem) -> String {
        let prefix = item.isMissing ? "MISSING · " : (item.kind == .test ? "TEST · " : "")
        return prefix + item.title
    }
}
