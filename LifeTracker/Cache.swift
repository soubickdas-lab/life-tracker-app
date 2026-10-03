import Foundation

/// The last day the app saw, kept on disk. On the next launch it is on screen
/// before the network has said a word — the server's answer then quietly replaces
/// it. Nobody should watch a spinner to find out what they already knew.
enum Cache {
    private static let folder = "LifeTracker"
    private static let file = "day.json"

    private struct Box: Codable {
        var state: TrackerState
        var extra: SheetExtra
        var at: Date
        var email: String
        var calendar: String
    }

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(file)
    }

    static func save(state: TrackerState, extra: SheetExtra, email: String, calendar: String) {
        guard let url else { return }
        let box = Box(state: state, extra: extra, at: .now, email: email, calendar: calendar)
        guard let data = try? JSONEncoder().encode(box) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> (state: TrackerState, extra: SheetExtra, email: String, calendar: String)? {
        guard let url, let data = try? Data(contentsOf: url),
              let box = try? JSONDecoder().decode(Box.self, from: data) else { return nil }
        return (box.state, box.extra, box.email, box.calendar)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
