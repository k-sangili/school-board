import SwiftUI
import UIKit

@main
struct SchoolBoardApp: App {
    @State private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            BoardView()
                .environment(store)
                .preferredColorScheme(.dark)
                // A wall display: never let the Apple TV screensaver kick in while the board is open.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
