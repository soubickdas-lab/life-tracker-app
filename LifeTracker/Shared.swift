import Foundation

/// What the app leaves behind for the widget: a small picture of the day, written
/// every time the app hears from the server, plus the token so the widget can go
/// and look for itself when the app has not been opened in a while.
enum Shared {
    static let group = "group.com.soubick.lifetracker"
    /// Same override the app honours, so both halves can be pointed at a local server.
    static var home: String {
        box.string(forKey: "apiHome")
            ?? UserDefaults.standard.string(forKey: "apiHome")
            ?? "https://lifetracker.soubickdas.workers.dev"
    }

    static var box: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    struct Snapshot: Codable, Sendable {
        var at: Date = .now
        var pretty: String = ""
        var done: Int = 0
        var total: Int = 0
        var lines: [Line] = []
        var habitsDone: Int = 0
        var habitsTotal: Int = 0
        var journey: String = ""
        var journeyLeft: Int = 0
        var journeyDone: Int = 0
        var journeyDue: Int = 0

        var left: Int { max(0, total - done) }
        var share: Double { total == 0 ? 1 : Double(done) / Double(total) }
        var hasJourney: Bool { !journey.isEmpty }

        struct Line: Codable, Sendable, Identifiable {
            var text: String
            var slot: String
            var id: String { text + slot }
        }
    }

    static func save(_ snap: Snapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        box.set(data, forKey: "snapshot")
    }

    static func load() -> Snapshot? {
        guard let data = box.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static var token: String {
        get { box.string(forKey: "token") ?? "" }
        set { box.set(newValue, forKey: "token") }
    }
}
