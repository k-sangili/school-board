import BoardCore
import Foundation
import Observation
import SwiftUI

/// Loads the configured iCal feeds, keeps them fresh, and falls back to the last saved copy
/// when the network is down.
@MainActor
@Observable
final class BoardStore {
    private(set) var items: [BoardItem] = []
    private(set) var lastUpdated: Date?
    private(set) var problems: [String] = []
    private(set) var isDemo = false

    let config: BoardConfig
    private let kidColors: [String: Color]

    init(config: BoardConfig = BoardStore.loadConfig()) {
        self.config = config
        kidColors = Dictionary(uniqueKeysWithValues: config.kids.map { ($0.name, Color(hex: $0.color)) })
    }

    var kids: [String] { config.kids.map(\.name) }
    var weekSeconds: Double { config.weekSeconds ?? 75 }
    var monthSeconds: Double { config.monthSeconds ?? 25 }

    /// True until your personal calendar (where Muse writes) has been added to BoardConfig.json.
    var needsPersonalFeed: Bool {
        !isDemo && !config.feeds.contains { $0.mode == .tagged && $0.isConfigured }
    }

    func color(for kid: String?) -> Color {
        kid.flatMap { kidColors[$0] } ?? Theme.secondary
    }

    func start() async {
        let feeds = config.feeds.filter(\.isConfigured)
        if feeds.isEmpty || ProcessInfo.processInfo.arguments.contains("-demo") {
            isDemo = true
            items = DemoData.items(now: .now)
            lastUpdated = .now
            return
        }
        while !Task.isCancelled {
            await refresh(feeds)
            try? await Task.sleep(for: .seconds((config.refreshMinutes ?? 10) * 60))
        }
    }

    private func refresh(_ feeds: [BoardConfig.Feed]) async {
        let config = self.config
        let window = BoardBuilder.window(around: .now)
        let results = await withTaskGroup(of: FeedResult.self) { group in
            for feed in feeds {
                group.addTask { await Self.load(feed, config: config, window: window) }
            }
            var all: [FeedResult] = []
            for await result in group { all.append(result) }
            return all
        }
        items = BoardBuilder.deduplicated(results.flatMap(\.items))
        problems = results.compactMap(\.problem)
        lastUpdated = .now
    }

    // MARK: - Loading

    private struct FeedResult: Sendable {
        let items: [BoardItem]
        let problem: String?
    }

    nonisolated private static func load(_ feed: BoardConfig.Feed, config: BoardConfig, window: DateInterval) async -> FeedResult {
        var text: String?
        var problem: String?
        let cacheURL = cacheFile(for: feed)
        do {
            guard let url = URL(string: feed.url) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }
            text = String(decoding: data, as: UTF8.self)
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            problem = "\(feed.name): \(error.localizedDescription)"
            if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
                text = cached
                problem! += " (showing saved copy)"
            }
        }
        let items = text.map { BoardBuilder.items(icsText: $0, feed: feed, config: config, window: window) } ?? []
        return FeedResult(items: items, problem: problem)
    }

    nonisolated private static func cacheFile(for feed: BoardConfig.Feed) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let name = String(feed.url.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }, radix: 36)
        return dir.appendingPathComponent("feed-\(name).ics")
    }

    nonisolated static func loadConfig() -> BoardConfig {
        for name in ["BoardConfig", "BoardConfig.example"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let config = try? JSONDecoder().decode(BoardConfig.self, from: data) {
                return config
            }
        }
        return BoardConfig(kids: [.init(name: "Maya", color: "#4C9AFF", tags: ["OMS"])], feeds: [])
    }
}
