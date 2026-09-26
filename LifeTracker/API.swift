import Foundation

/// Talks to Life Tracker's own server. The address is built in — there is nothing
/// to paste — and who you are is carried by the token you get when you sign in.
struct TrackerAPI: Sendable {
    /// The backend. Overridable with the \"apiHome\" default, so a build can be
    /// pointed at a local server while a screen is being worked on.
    static let home = UserDefaults.standard.string(forKey: "apiHome")
        ?? "https://lifetracker.soubickdas.workers.dev"

    var token: String

    var isConfigured: Bool { !token.isEmpty }

    enum Failure: LocalizedError {
        case notConfigured
        case badURL
        case signedOut
        case waiting
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Sign in first."
            case .badURL:        return "That address does not look right."
            case .signedOut:     return "Signed out — sign in again."
            case .waiting:       return "Your account is waiting to be let in."
            case .server(let m): return m
            }
        }
    }

    // MARK: - The door

    /// Returns the token, and whether the account is allowed in yet.
    static func signIn(email: String, password: String) async throws -> (token: String, waiting: Bool) {
        try await door(at: "/api/login", email: email, password: password)
    }

    static func signUp(email: String, password: String) async throws -> (token: String, waiting: Bool) {
        try await door(at: "/api/signup", email: email, password: password)
    }

    private static func door(at path: String, email: String, password: String) async throws -> (token: String, waiting: Bool) {
        guard let url = URL(string: home + path) else { throw Failure.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, _) = try await URLSession.shared.data(for: request)
        let reply = try JSONDecoder().decode(DoorReply.self, from: data)
        guard reply.ok, let token = reply.token else {
            throw Failure.server(reply.error ?? "That did not work.")
        }
        return (token, reply.status == "pending")
    }

    /// Whether this device's token still opens the door, and what the account may do.
    func check() async throws -> (email: String, waiting: Bool, admin: Bool, calendar: String) {
        guard isConfigured else { throw Failure.notConfigured }
        guard let url = URL(string: Self.home + "/api/me") else { throw Failure.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer " + token, forHTTPHeaderField: "authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw Failure.signedOut }
        let reply = try JSONDecoder().decode(MeReply.self, from: data)
        guard reply.ok else { throw Failure.signedOut }
        return (reply.email ?? "", reply.status != "active", reply.admin ?? false, reply.calendar ?? "")
    }

    // MARK: - Calls

    func state() async throws -> TrackerState {
        try await send(["api": "state"])
    }

    func add(_ text: String) async throws -> (TrackerState, String) {
        try await sendWithReply(["api": "add", "text": text])
    }

    func setDone(_ id: String, _ done: Bool) async throws -> TrackerState {
        try await send(["api": "toggle", "id": id, "done": done ? "true" : "false", "light": "1"])
    }

    func delete(_ id: String) async throws -> TrackerState {
        try await send(["api": "delete", "id": id, "light": "1"])
    }

    func rename(_ id: String, to text: String) async throws -> TrackerState {
        try await send(["api": "rename", "id": id, "text": text, "light": "1"])
    }

    func move(_ id: String, to when: String) async throws -> (TrackerState, String) {
        try await sendWithReply(["api": "move", "id": id, "when": when, "light": "1"])
    }

    /// Sets the time on one exact task. Blank slot = all day.
    /// Older copies of the sheet script do not know "time" yet, so it falls back to "move".
    func setTime(_ id: String, slot: String) async throws -> (TrackerState, String) {
        do {
            return try await sendWithReply(["api": "time", "id": id, "slot": slot, "light": "1"])
        } catch Failure.server(let message) where message.lowercased().contains("unknown api") {
            return try await sendWithReply(["api": "move", "id": id,
                                            "when": slot.isEmpty ? "all day" : slot])
        }
    }

    /// Every day, every other day, every third day…
    func setHabitEvery(_ name: String, _ every: Int) async throws -> (TrackerState, SheetExtra?) {
        let r = try await raw(["api": "habitfreq", "name": name, "every": String(every)])
        return (r.0, r.2)
    }

    /// Starts or edits a journey. Give it months, or an exact end date.
    func saveJourney(_ fields: [String: String]) async throws -> (TrackerState, SheetExtra?) {
        var params = fields
        params["api"] = "journey"
        let r = try await raw(params)
        return (r.0, r.2)
    }

    func dropJourney(_ id: Int) async throws -> (TrackerState, SheetExtra?) {
        let r = try await raw(["api": "journeydel", "id": String(id)])
        return (r.0, r.2)
    }

    func journeyHabit(_ id: Int, habit: String, remove: Bool, photo: Bool? = nil) async throws -> (TrackerState, SheetExtra?) {
        var params = ["api": "journeyhabit", "id": String(id),
                      "habit": habit, "remove": remove ? "true" : "false", "light": "1"]
        if let photo { params["photo"] = photo ? "true" : "false" }
        let r = try await raw(params)
        return (r.0, r.2)
    }

    // MARK: - Proof photos

    /// Sends the picture. The habit ticks because the picture landed, not the other way round.
    func sendPhoto(_ bytes: Data, journey: Int, habit: String, day: String? = nil) async throws -> (TrackerState, SheetExtra?) {
        guard isConfigured else { throw Failure.notConfigured }
        guard var parts = URLComponents(string: Self.home + "/") else { throw Failure.badURL }
        parts.queryItems = [
            URLQueryItem(name: "api", value: "photo"),
            URLQueryItem(name: "journey", value: String(journey)),
            URLQueryItem(name: "habit", value: habit),
        ] + (day.map { [URLQueryItem(name: "day", value: $0)] } ?? [])
        guard let url = parts.url else { throw Failure.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer " + token, forHTTPHeaderField: "authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "content-type")
        request.httpBody = bytes

        let data = try await URLSession.shared.data(for: request).0
        let reply = try JSONDecoder().decode(APIReply.self, from: data)
        if reply.pending == true { throw Failure.waiting }
        guard reply.ok, let state = reply.state else {
            throw Failure.server(reply.error ?? "That photo did not go through.")
        }
        return (state, reply.extra)
    }

    /// The picture itself, for looking at.
    func photo(journey: Int, habit: String, day: String? = nil) async throws -> Data {
        guard isConfigured else { throw Failure.notConfigured }
        guard var parts = URLComponents(string: Self.home + "/") else { throw Failure.badURL }
        parts.queryItems = [
            URLQueryItem(name: "api", value: "photo"),
            URLQueryItem(name: "journey", value: String(journey)),
            URLQueryItem(name: "habit", value: habit),
        ] + (day.map { [URLQueryItem(name: "day", value: $0)] } ?? [])
        guard let url = parts.url else { throw Failure.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Bearer " + token, forHTTPHeaderField: "authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.server("That photo is not there.")
        }
        return data
    }

    func dropPhoto(journey: Int, habit: String, day: String? = nil) async throws -> (TrackerState, SheetExtra?) {
        var params = ["api": "photodel", "journey": String(journey), "habit": habit, "light": "1"]
        if let day { params["day"] = day }
        let r = try await raw(params)
        return (r.0, r.2)
    }

    func clearPhotos(journey: Int) async throws -> (TrackerState, SheetExtra?) {
        let r = try await raw(["api": "photoclear", "journey": String(journey)])
        return (r.0, r.2)
    }

    /// Every photo of one journey, zipped, ready to be put somewhere safe.
    func photoZip(journey: Int) async throws -> Data {
        guard isConfigured else { throw Failure.notConfigured }
        guard var parts = URLComponents(string: Self.home + "/") else { throw Failure.badURL }
        parts.queryItems = [
            URLQueryItem(name: "api", value: "photozip"),
            URLQueryItem(name: "journey", value: String(journey)),
        ]
        guard let url = parts.url else { throw Failure.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue("Bearer " + token, forHTTPHeaderField: "authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.server("There are no photos to take away yet.")
        }
        return data
    }

    /// The day, in the order the screen now shows it.
    func setOrder(_ ids: [String]) async throws -> (TrackerState, String) {
        try await sendWithReply(["api": "order", "ids": ids.joined(separator: ","), "light": "1"])
    }

    func setHabit(_ name: String, _ done: Bool, on day: String = "") async throws -> (TrackerState, SheetExtra?) {
        var params = ["api": "habit", "name": name, "done": done ? "true" : "false", "light": "1"]
        if !day.isEmpty { params["date"] = day }
        let r = try await raw(params)
        return (r.0, r.2)
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

    func setRepeat(_ id: String, _ on: Bool) async throws -> (TrackerState, SheetExtra?) {
        let r = try await raw(["api": "repeat", "id": id, "on": on ? "true" : "false", "light": "1"])
        return (r.0, r.2)
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
        guard var parts = URLComponents(string: Self.home + "/") else { throw Failure.badURL }

        parts.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = parts.url else { throw Failure.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + token, forHTTPHeaderField: "authorization")

        /* One quiet retry: a dropped connection should not become a red banner. */
        var reply: APIReply
        do {
            reply = try JSONDecoder().decode(APIReply.self, from: try await URLSession.shared.data(for: request).0)
        } catch is DecodingError {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            reply = try JSONDecoder().decode(APIReply.self, from: try await URLSession.shared.data(for: request).0)
        }
        if reply.pending == true { throw Failure.waiting }
        guard reply.ok, let state = reply.state else {
            throw Failure.server(reply.error ?? "The sheet said no.")
        }
        return (state, reply.said ?? "", reply.extra)
    }
}
