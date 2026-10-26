import BoardCore
import Foundation

/// The few weeks of items the complication needs, saved by the watch app into the shared App Group.
/// The complication only reads this file: downloading and parsing whole iCal feeds goes past the
/// widget extension's ~15 MB memory limit on the watch.
struct BoardSnapshot: Codable {
    var items: [BoardItem]
    var updated: Date

    /// `group.<BUNDLE_ID>`, set as APP_GROUP in project.yml and passed through each target's Info.plist.
    private static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SchoolBoardAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("board-snapshot.json")
    }

    /// Keeps the last month (for missing work) through the next two weeks.
    init(items: [BoardItem], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -31, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 16, to: today) ?? today
        self.items = items.filter { $0.end > start && $0.start < end }
        updated = now
    }

    static func load() -> BoardSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BoardSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
