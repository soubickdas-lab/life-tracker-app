import Foundation

/// Talks to the Life Tracker web app (the Apps Script behind the Google Sheet).
/// Every call answers with the whole fresh state, so the app never has to guess.
struct TrackerAPI: Sendable {
    var endpoint: String
    var key: String

    var isConfigured: Bool { !endpoint.isEmpty && !key.isEmpty }

    enum Failure: LocalizedError {
        case notConfigured
        case badURL
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add the web app link and key in Settings first."
            case .badURL:        return "That web app link does not look right."
            case .server(let m): return m
            }
        }
    }

    // MARK: - Calls

    func state() async throws -> TrackerState {
        try await send(["api": "state"])
    }

    func add(_ text: String) async throws -> (TrackerState, String) {
        try await sendWithReply(["api": "add", "text": text])
    }

    func setDone(_ id: String, _ done: Bool) async throws -> TrackerState {
        try await send(["api": "toggle", "id": id, "done": done ? "true" : "false"])
    }

    func delete(_ id: String) async throws -> TrackerState {
        try await send(["api": "delete", "id": id])
    }

    func rename(_ id: String, to text: String) async throws -> TrackerState {
        try await send(["api": "rename", "id": id, "text": text])
    }

    func move(_ id: String, to when: String) async throws -> (TrackerState, String) {
        try await sendWithReply(["api": "move", "id": id, "when": when])
    }

    /// Sets the time on one exact task. Blank slot = all day.
    /// Older copies of the sheet script do not know "time" yet, so it falls back to "move".
    func setTime(_ id: String, slot: String) async throws -> (TrackerState, String) {
        do {
            return try await sendWithReply(["api": "time", "id": id, "slot": slot])
        } catch Failure.server(let message) where message.lowercased().contains("unknown api") {
            return try await sendWithReply(["api": "move", "id": id,
                                            "when": slot.isEmpty ? "all day" : slot])
        }
    }

    func setHabit(_ name: String, _ done: Bool, on day: String = "") async throws -> (TrackerState, SheetExtra) {
        var params = ["api": "habit", "name": name, "done": done ? "true" : "false"]
        if !day.isEmpty { params["date"] = day }
        let r = try await raw(params)
        return (r.0, r.2 ?? SheetExtra())
    }

    func logWeight(_ kg: String) async throws -> TrackerState {
        try await send(["api": "weight", "kg": kg])
    }

    func addNote(_ text: String) async throws -> TrackerState {
        try await send(["api": "note", "text": text])
    }

    /// Everything outside the three day tabs.
    func full() async throws -> (TrackerState, SheetExtra) {
        let reply = try await raw(["api": "full"])
        return (reply.0, reply.2 ?? SheetExtra())
    }

    func setRepeat(_ id: String, _ on: Bool) async throws -> (TrackerState, SheetExtra) {
        let r = try await raw(["api": "repeat", "id": id, "on": on ? "true" : "false"])
        return (r.0, r.2 ?? SheetExtra())
    }

    func schedule(_ text: String, date: String, slot: String) async throws -> (TrackerState, SheetExtra) {
        let r = try await raw(["api": "schedule", "text": text, "date": date, "slot": slot])
        return (r.0, r.2 ?? SheetExtra())
    }

    func setSetting(_ name: String, _ value: String) async throws -> (TrackerState, SheetExtra) {
        let r = try await raw(["api": "setting", "name": name, "value": value])
        return (r.0, r.2 ?? SheetExtra())
    }

    func saveHabit(slot: Int, name: String, target: String, active: Bool, remove: Bool = false) async throws -> (TrackerState, SheetExtra) {
        let r = try await raw(["api": "habitcfg", "slot": String(slot), "name": name,
                               "target": target, "active": active ? "true" : "false",
                               "remove": remove ? "true" : "false"])
        return (r.0, r.2 ?? SheetExtra())
    }

    func category(_ text: String, remove: Bool) async throws -> (TrackerState, SheetExtra) {
        let r = try await raw(["api": "category", "text": text, "remove": remove ? "true" : "false"])
        return (r.0, r.2 ?? SheetExtra())
    }

    func saveGoal(row: Int, fields: [String: String], remove: Bool = false) async throws -> (TrackerState, SheetExtra) {
        var params = fields
        params["api"] = "goal"
        params["row"] = String(row)
        if remove { params["remove"] = "true" }
        let r = try await raw(params)
        return (r.0, r.2 ?? SheetExtra())
    }

    func saveBody(date: String, fields: [String: String]) async throws -> (TrackerState, SheetExtra) {
        var params = fields
        params["api"] = "body"
        params["date"] = date
        let r = try await raw(params)
        return (r.0, r.2 ?? SheetExtra())
    }

    // MARK: - Plumbing

    private func send(_ params: [String: String]) async throws -> TrackerState {
        try await sendWithReply(params).0
    }

    private func sendWithReply(_ params: [String: String]) async throws -> (TrackerState, String) {
        let r = try await raw(params)
        return (r.0, r.1)
    }

    private func raw(_ params: [String: String]) async throws -> (TrackerState, String, SheetExtra?) {
        guard isConfigured else { throw Failure.notConfigured }
        guard var parts = URLComponents(string: endpoint) else { throw Failure.badURL }

        var query = [URLQueryItem(name: "key", value: key)]
        for (name, value) in params { query.append(URLQueryItem(name: name, value: value)) }
        parts.queryItems = query
        guard let url = parts.url else { throw Failure.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60          /* the sheet redraws itself on a change */
        request.cachePolicy = .reloadIgnoringLocalCacheData

        /* Apps Script now and then answers a redirect with an HTML page instead of
           the JSON. It is always over by the next try, so ask once more before
           bothering anyone about it. */
        var reply: APIReply
        do {
            reply = try JSONDecoder().decode(APIReply.self, from: try await URLSession.shared.data(for: request).0)
        } catch is DecodingError {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            do {
                reply = try JSONDecoder().decode(APIReply.self, from: try await URLSession.shared.data(for: request).0)
            } catch is DecodingError {
                throw Failure.server("Google answered with a page instead of data. Trying again usually fixes it.")
            }
        }
        guard reply.ok, let state = reply.state else {
            throw Failure.server(reply.error ?? "The sheet said no.")
        }
        return (state, reply.said ?? "", reply.extra)
    }
}
