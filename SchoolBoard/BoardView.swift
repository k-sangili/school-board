import BoardCore
import SwiftUI

/// Root screen. Rotates between the week and month views on its own; the Siri Remote can
/// browse (◀ ▶), switch views (▲ ▼) and jump back to today (⏯). After 3 idle minutes it
/// returns to the current week.
struct BoardView: View {
    enum Mode { case week, month }

    @Environment(BoardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: Mode = .week
    @State private var weekOffset = 0
    @State private var monthOffset = 0
    @State private var now = Date()
    @State private var lastInteraction: Date?
    @State private var phaseStart = Date()

    private let schedule = Schedule()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                HeaderView(now: now, title: title, summaries: summaries)

                if mode == .week, !missing.isEmpty {
                    MissingStrip(items: missing)
                }

                Group {
                    switch mode {
                    case .week:
                        WeekView(layout: schedule.week(for: now, offset: weekOffset), items: store.items,
                                 now: now, schedule: schedule)
                    case .month:
                        MonthView(month: schedule.month(for: now, offset: monthOffset), items: store.items,
                                  now: now, schedule: schedule)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

                FooterView(mode: mode)
            }

            // Dim overnight so the TV isn't a night-light.
            Color.black.opacity(isNight ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: handleMove)
        #if os(tvOS)
        .onPlayPauseCommand { returnToToday() }
        #endif
        .task { await store.start() }
        .task { await tick() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }

    // MARK: - Derived

    private var title: String {
        switch mode {
        case .week:
            let layout = schedule.week(for: now, offset: weekOffset)
            if weekOffset == 0 { return layout.weekendFirst ? "This Weekend & Next Week" : "This Week" }
            if weekOffset == 1 && !layout.weekendFirst { return "Next Week" }
            let first = layout.weekendFirst ? layout.weekend[0] : layout.weekdays[0]
            let last = layout.weekendFirst ? layout.weekdays[4] : layout.weekend[1]
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return schedule.month(for: now, offset: monthOffset).formatted(.dateTime.month(.wide).year())
        }
    }

    /// Missing work from the last 30 days, oldest first.
    private var missing: [BoardItem] {
        let cutoff = schedule.day(-30, from: now)
        return store.items.filter { $0.isMissing && $0.start >= cutoff }.sorted { $0.start < $1.start }
    }

    private var summaries: [HeaderView.KidSummary] {
        let today = schedule.calendar.startOfDay(for: now)
        let horizon = schedule.day(7, from: today)
        return store.kids.map { kid in
            let upcoming = store.items.filter { $0.kid == kid && $0.isSchoolwork && !$0.isMissing && $0.start >= today && $0.start < horizon }
            return .init(name: kid, color: store.color(for: kid),
                         due: upcoming.count,
                         tests: upcoming.filter { $0.kind == .test }.count,
                         missing: missing.filter { $0.kid == kid }.count)
        }
    }

    private var isNight: Bool {
        let hour = schedule.calendar.component(.hour, from: now)
        return hour >= 21 || hour < 6
    }

    // MARK: - Remote + rotation

    private func handleMove(_ direction: MoveCommandDirection) {
        lastInteraction = .now
        withAnimation(.easeInOut(duration: 0.3)) {
            switch direction {
            case .left: if mode == .week { weekOffset -= 1 } else { monthOffset -= 1 }
            case .right: if mode == .week { weekOffset += 1 } else { monthOffset += 1 }
            case .up, .down: mode = mode == .week ? .month : .week
            @unknown default: break
            }
        }
    }

    private func returnToToday() {
        lastInteraction = nil
        phaseStart = .now
        withAnimation(.easeInOut(duration: 0.4)) {
            mode = .week
            weekOffset = 0
            monthOffset = 0
        }
    }

    private func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            now = .now
            if let last = lastInteraction {
                if now.timeIntervalSince(last) > 180 { returnToToday() }
                continue
            }
            let duration = mode == .week ? store.weekSeconds : store.monthSeconds
            if now.timeIntervalSince(phaseStart) >= duration {
                withAnimation(.easeInOut(duration: 0.6)) { mode = mode == .week ? .month : .week }
                phaseStart = now
            }
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    struct KidSummary: Identifiable {
        var id: String { name }
        let name: String
        let color: Color
        let due: Int
        let tests: Int
        let missing: Int
    }

    let now: Date
    let title: String
    let summaries: [KidSummary]

    var body: some View {
        HStack(alignment: .bottom, spacing: 32) {
            VStack(alignment: .leading, spacing: 2) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(Theme.font(28, .semibold))
                    .foregroundStyle(Theme.today)
                Text(now.formatted(.dateTime.month(.wide).day()))
                    .font(Theme.font(56, .bold))
                    .foregroundStyle(Theme.text)
            }

            Text(title)
                .font(Theme.font(30, .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.bottom, 8)

            Spacer()

            ForEach(summaries) { kid in
                KidChip(kid: kid)
            }

            Text(now.formatted(date: .omitted, time: .shortened))
                .font(Theme.font(48, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
    }
}

private struct KidChip: View {
    let kid: HeaderView.KidSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Circle().fill(kid.color).frame(width: 16, height: 16)
                Text(kid.name).font(Theme.font(26, .bold)).foregroundStyle(Theme.text)
            }
            Text(detail)
                .font(Theme.font(18, .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(kid.color.opacity(0.5), lineWidth: 2))
    }

    private var detail: String {
        var parts = [kid.due == 0 ? "Nothing due" : "\(kid.due) due this week"]
        if kid.tests > 0 { parts.append("\(kid.tests) test\(kid.tests == 1 ? "" : "s")") }
        if kid.missing > 0 { parts.append("\(kid.missing) missing") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Missing strip

struct MissingStrip: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let items: [BoardItem]

    var body: some View {
        HStack(spacing: 14) {
            Label("Missing", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.font(22, .bold))
                .foregroundStyle(Theme.test)
            ForEach(items.prefix(4)) { item in
                HStack(spacing: 8) {
                    Circle().fill(store.color(for: item.kid)).frame(width: 12, height: 12)
                    Text([item.course, item.title].compactMap { $0 }.joined(separator: ": "))
                        .lineLimit(1)
                    Text(item.start.formatted(.dateTime.month(.abbreviated).day()))
                        .foregroundStyle(Theme.secondary)
                }
                .font(Theme.font(20, .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.test.opacity(0.15)))
            }
            if items.count > 4 {
                Text("+\(items.count - 4) more").font(Theme.font(20, .semibold)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let mode: BoardView.Mode

    var body: some View {
        HStack(spacing: 20) {
            if store.isDemo {
                Text("DEMO DATA").font(Theme.font(16, .heavy)).foregroundStyle(Theme.deadline)
            } else if store.needsPersonalFeed {
                Text("Add your calendar’s secret iCal URL to BoardConfig.json to show homework")
                    .font(Theme.font(16, .semibold)).foregroundStyle(Theme.deadline)
            }
            if let problem = store.problems.first {
                Label(problem, systemImage: "wifi.exclamationmark")
                    .lineLimit(1)
                    .foregroundStyle(Theme.deadline)
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(mode == .week ? Theme.text : Theme.secondary.opacity(0.4)).frame(width: 10, height: 10)
                Circle().fill(mode == .month ? Theme.text : Theme.secondary.opacity(0.4)).frame(width: 10, height: 10)
            }
            Text("◀ ▶ browse   ▲ ▼ week / month   ⏯ today")
        }
        .font(Theme.font(16, .medium))
        .foregroundStyle(Theme.secondary)
    }
}
