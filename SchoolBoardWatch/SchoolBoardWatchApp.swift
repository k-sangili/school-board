import BoardCore
import SwiftUI
import WatchKit
import WidgetKit

@main
struct SchoolBoardWatchApp: App {
    @State private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            AgendaView()
                .environment(store)
                .onAppear { Self.scheduleRefresh() }
        }
        // Keeps the complication current without opening the app. watchOS decides the actual
        // timing; with the complication on the face it allows a few refreshes an hour.
        .backgroundTask(.appRefresh) { _ in
            await store.refresh()
            await Self.publish(store.items)
            await Self.scheduleRefresh()
        }
    }

    /// Saves what the complication shows and asks it to redraw.
    @MainActor static func publish(_ items: [BoardItem]) {
        BoardSnapshot(items: items).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor static func scheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: .now.addingTimeInterval(30 * 60),
                                                         userInfo: nil) { _ in }
    }
}
