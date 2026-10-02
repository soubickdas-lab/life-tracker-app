import Foundation

/// The widget can ask the server itself, so it stays right on a day the app was
/// never opened. If anything at all goes wrong it simply keeps the last picture.
enum Live {
    static func fetch() async -> Shared.Snapshot? {
        let token = Shared.token
        guard !token.isEmpty,
              var parts = URLComponents(string: Shared.home + "/") else { return nil }
        parts.queryItems = [
            URLQueryItem(name: "api", value: "state"),
            URLQueryItem(name: "light", value: "1"),
        ]
        guard let url = parts.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + token, forHTTPHeaderField: "authorization")

        guard let data = try? await URLSession.shared.data(for: request).0,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.ok, let state = reply.state,
              let today = state.days.first(where: { $0.label == "Today" }) else { return nil }

        var snap = Shared.Snapshot()
        snap.pretty = today.pretty
        snap.total = today.tasks.count
        snap.done = today.tasks.filter(\.done).count
        snap.lines = today.tasks.filter { !$0.done }.prefix(6)
            .map { Shared.Snapshot.Line(text: $0.task, slot: $0.slot) }
        snap.habitsTotal = state.habits.count
        snap.habitsDone = state.habits.filter(\.done).count
        if let journey = state.journeys.first {
            snap.journey = journey.name
            snap.journeyLeft = journey.daysLeft
            snap.journeyDone = journey.doneToday
            snap.journeyDue = journey.dueToday
        }
        Shared.save(snap)
        return snap
    }

    /* only the handful of fields a widget shows */
    private struct Reply: Decodable { var ok = false; var state: State? }

    private struct State: Decodable {
        var days: [Day] = []
        var habits: [Habit] = []
        var journeys: [Journey] = []
    }

    private struct Day: Decodable {
        var label = ""
        var pretty = ""
        var tasks: [Task] = []
    }

    private struct Task: Decodable {
        var task = ""
        var slot = ""
        var done = false
    }

    private struct Habit: Decodable {
        var name = ""
        var done = false
    }

    private struct Journey: Decodable {
        var name = ""
        var daysLeft = 0
        var doneToday = 0
        var dueToday = 0
    }
}
