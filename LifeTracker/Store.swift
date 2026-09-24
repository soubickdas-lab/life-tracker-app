import Foundation
import Observation

/// One place that holds what is on screen and knows how to change it.
/// Ticks and deletes are applied straight away, then confirmed by the sheet.
@MainActor
@Observable
final class Store {
    var state = TrackerState()
    var extra = SheetExtra()
    var selectedDay: String = "Today"
    var pane: Pane = .today
    var loading = false
    var busy = false
    var toast: String?
    var errorText: String?
    var lastSync: Date?

    /// Who this device is signed in as. Kept so the app opens straight into the day.
    var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    var email = ""
    var waiting = false          /* signed in, but the account has not been let in yet */
    var isAdmin = false
    var calendarLink = ""

    var api: TrackerAPI { TrackerAPI(token: token) }
    var isConfigured: Bool { api.isConfigured && !waiting }
    var isSignedIn: Bool { !token.isEmpty }

    /// Runs while the app is in front, so a change made on the phone shows up here
    /// without anyone pressing anything.
    private var poller: Task<Void, Never>?

    init() {
        token = UserDefaults.standard.string(forKey: "token") ?? ""
    }

    // MARK: - The door

    func signIn(email address: String, password: String) async -> String? {
        await door { try await TrackerAPI.signIn(email: address, password: password) }
    }

    func signUp(email address: String, password: String) async -> String? {
        await door { try await TrackerAPI.signUp(email: address, password: password) }
    }

    /// Returns a message when it did not work, nil when it did.
    private func door(_ work: @escaping () async throws -> (token: String, waiting: Bool)) async -> String? {
        busy = true
        defer { busy = false }
        do {
            let answer = try await work()
            token = answer.token
            waiting = answer.waiting
            errorText = nil
            await checkDoor()               /* name, calendar link, whether it is the owner */
            if !waiting { await refresh() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Asks the server whether this device is still welcome.
    func checkDoor() async {
        guard isSignedIn else { return }
        do {
            let who = try await api.check()
            email = who.email
            waiting = who.waiting
            isAdmin = who.admin
            calendarLink = who.calendar
            errorText = nil
        } catch TrackerAPI.Failure.signedOut {
            signOut()
        } catch {
            /* offline — keep what we have and try again later */
        }
    }

    func signOut() {
        wentAway()
        token = ""
        email = ""
        waiting = false
        isAdmin = false
        calendarLink = ""
        state = TrackerState()
        extra = SheetExtra()
        lastSync = nil
        errorText = nil
    }

    /// Called when the window comes forward. Fetches once, then keeps checking.
    func cameToFront() {
        guard isConfigured else { return }
        Task { await refresh(quietly: true) }
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)   /* two minutes */
                guard !Task.isCancelled, let self, self.isConfigured, !self.busy, !self.loading else { continue }
                await self.refresh(quietly: true)
            }
        }
    }

    /// Nothing to poll for while the app is hidden — the sheet is not going anywhere.
    func wentAway() {
        poller?.cancel()
        poller = nil
    }

    var day: DayBlock? {
        state.days.first { $0.label == selectedDay } ?? state.todayBlock
    }

    var habitsDone: Int { state.habits.filter(\.done).count }

    /// The sheet's own "Remind me N min before a task" setting.
    var reminderLead: Int {
        let row = extra.setup.first { $0.name.localizedCaseInsensitiveContains("Remind me") }
        return Int(row?.value ?? "") ?? 10
    }

    // MARK: - Loading

    func refresh(quietly: Bool = false) async {
        guard isConfigured else { return }
        if !quietly { loading = true }
        defer { loading = false }
        let client = api
        await runFull(note: nil, quiet: quietly) { try await client.full() }
    }

    // MARK: - Changes

    func toggle(_ task: TaskItem) async {
        let wanted = !task.done
        for day in state.days.indices {
            if let row = state.days[day].tasks.firstIndex(where: { $0.id == task.id }) {
                state.days[day].tasks[row].done = wanted        /* feels instant */
            }
        }
        let client = api
        await run { try await client.setDone(task.id, wanted) }
    }

    func delete(_ task: TaskItem) async {
        for day in state.days.indices {
            state.days[day].tasks.removeAll { $0.id == task.id }   /* gone at once */
        }
        extra.scheduled.removeAll { $0.id == task.id }
        let client = api
        await run(note: "Deleted \(task.task)") { try await client.delete(task.id) }
    }

    func rename(_ task: TaskItem, to text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != task.task else { return }
        for day in state.days.indices {
            if let row = state.days[day].tasks.firstIndex(where: { $0.id == task.id }) {
                state.days[day].tasks[row].task = clean
            }
        }
        let client = api
        await run(note: "Renamed to \(clean)") { try await client.rename(task.id, to: clean) }
    }

    /// New time on an existing task — shown at once, then saved.
    func setTime(_ task: TaskItem, _ slot: String) async {
        let clean = slot.trimmingCharacters(in: .whitespacesAndNewlines)
        for day in state.days.indices {
            if let row = state.days[day].tasks.firstIndex(where: { $0.id == task.id }) {
                state.days[day].tasks[row].slot = clean
                state.days[day].tasks[row].pending = true
            }
        }
        let client = api
        await runWithReply { try await client.setTime(task.id, slot: clean) }
    }

    /// Dragged into a new place: the list moves first, then the sheet is told.
    func reorder(_ movedId: String, before targetId: String, on label: String) async {
        guard movedId != targetId,
              let day = state.days.firstIndex(where: { $0.label == label }) else { return }
        var list = state.days[day].tasks
        guard let from = list.firstIndex(where: { $0.id == movedId }),
              let to = list.firstIndex(where: { $0.id == targetId }) else { return }
        let moving = list.remove(at: from)
        list.insert(moving, at: to)
        state.days[day].tasks = list

        let ids = list.map(\.id).filter { !$0.hasPrefix("pending-") }
        let client = api
        await runWithReply { try await client.setOrder(ids) }
    }

    func move(_ task: TaskItem, to when: String) async {
        let client = api
        await runWithReply { try await client.move(task.id, to: when) }
    }

    func send(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let client = api
        await runWithReply { try await client.add(clean) }
    }

    /// Shows the new task straight away on that day, then sends it to the sheet.
    func add(_ name: String, slot: String, to day: DayBlock) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if let index = state.days.firstIndex(where: { $0.date == day.date }) {
            state.days[index].tasks.append(
                TaskItem(id: "pending-" + UUID().uuidString, task: clean,
                         slot: slot.trimmingCharacters(in: .whitespaces), pending: true))
        }

        var line = clean
        if !slot.trimmingCharacters(in: .whitespaces).isEmpty { line += " " + slot }
        switch day.label {
        case "Tomorrow":  line += " tomorrow"
        case "Yesterday": line += " yesterday"
        default: break
        }
        let client = api
        await runWithReply { try await client.add(line) }
    }

    func toggle(_ habit: Habit) async {
        guard let i = state.habits.firstIndex(where: { $0.name == habit.name }) else { return }
        let wanted = !habit.done
        state.habits[i].done = wanted
        let client = api
        await runFull(note: nil) { try await client.setHabit(habit.name, wanted) }
    }

    /// Tick a habit on any day of the month grid.
    func setHabit(_ name: String, _ done: Bool, on day: String) async {
        if let row = extra.habitGrid.rows.firstIndex(where: { $0.name == name }) {
            let index = (Int(day.suffix(2)) ?? 1) - 1
            if extra.habitGrid.rows[row].marks.indices.contains(index) {
                extra.habitGrid.rows[row].marks[index] = done
            }
        }
        if let today = state.habits.firstIndex(where: { $0.name == name }) {
            state.habits[today].done = done
        }
        let client = api
        await runFull(note: nil) { try await client.setHabit(name, done, on: day) }
    }

    func logWeight(_ kg: String) async {
        state.weight = kg                                   /* shows before the sheet answers */
        let today = Self.stamp.string(from: Date())
        if let row = extra.body.firstIndex(where: { $0.date == today }) {
            extra.body[row].wt = kg
        }
        let client = api
        await run(note: "⚖️ \(kg) kg") { try await client.logWeight(kg) }
    }

    func addNote(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        state.notes.insert(Note(when: "just now", text: clean), at: 0)
        let client = api
        await run(note: "🗒 Noted") { try await client.addNote(clean) }
    }

    func setRepeat(_ task: TaskItem, _ on: Bool) async {
        for day in state.days.indices {
            if let row = state.days[day].tasks.firstIndex(where: { $0.id == task.id }) {
                state.days[day].tasks[row].repeats = on
            }
        }
        let client = api
        await runFull(note: nil) { try await client.setRepeat(task.id, on) }
    }

    func schedule(_ text: String, date: String, slot: String) async {
        extra.scheduled.append(ScheduledItem(id: "pending-" + UUID().uuidString, task: text,
                                             date: date, pretty: date, slot: slot, done: false))
        extra.scheduled.sort { $0.date < $1.date }
        let client = api
        await runFull(note: "🗓️ \(text)") { try await client.schedule(text, date: date, slot: slot) }
    }

    func setSetting(_ name: String, _ value: String) async {
        if let row = extra.setup.firstIndex(where: { $0.name == name }) {
            extra.setup[row].value = value
        }
        let client = api
        await runFull(note: "⚙️ \(name)") { try await client.setSetting(name, value) }
    }

    func saveHabit(slot: Int, name: String, target: String, active: Bool, remove: Bool = false) async {
        if remove {
            extra.habitCfg.removeAll { $0.slot == slot }
            state.habits.removeAll { $0.name == name }
        } else if let row = extra.habitCfg.firstIndex(where: { $0.slot == slot }) {
            extra.habitCfg[row].name = name
            extra.habitCfg[row].target = target
            extra.habitCfg[row].active = active
        } else {
            extra.habitCfg.append(HabitConfig(slot: slot, name: name, target: target, active: active))
        }
        let client = api
        await runFull(note: remove ? "🗑 \(name)" : "🔥 \(name)") {
            try await client.saveHabit(slot: slot, name: name, target: target, active: active, remove: remove)
        }
    }

    /// How often a habit should come round. Shown at once, then saved.
    func setHabitEvery(_ name: String, _ every: Int) async {
        let n = max(1, min(30, every))
        if let row = extra.habitCfg.firstIndex(where: { $0.name == name }) {
            extra.habitCfg[row].every = n
        }
        if let row = extra.habitGrid.rows.firstIndex(where: { $0.name == name }) {
            extra.habitGrid.rows[row].every = n
        }
        if let row = state.habits.firstIndex(where: { $0.name == name }) {
            state.habits[row].every = n
        }
        let client = api
        await runFull(note: n == 1 ? "📅 \(name) — every day" : "📅 \(name) — every \(n) days") {
            try await client.setHabitEvery(name, n)
        }
    }

    func category(_ text: String, remove: Bool) async {
        if remove { extra.categories.removeAll { $0 == text } }
        else if !extra.categories.contains(text) { extra.categories.append(text) }
        let client = api
        await runFull(note: remove ? "🗑 \(text)" : "🏷 \(text)") { try await client.category(text, remove: remove) }
    }

    func saveGoal(row: Int, fields: [String: String], remove: Bool = false) async {
        if remove {
            extra.goals.removeAll { $0.row == row }
        } else if let index = extra.goals.firstIndex(where: { $0.row == row }) {
            apply(fields, to: &extra.goals[index])
        } else {
            var fresh = Goal(row: row, goal: "", why: "", target: "", status: "Idea", pct: 0, notes: "")
            apply(fields, to: &fresh)
            extra.goals.append(fresh)
        }
        let client = api
        await runFull(note: remove ? "🗑 Goal removed" : "🎯 Saved") {
            try await client.saveGoal(row: row, fields: fields, remove: remove)
        }
    }

    func saveBody(date: String, fields: [String: String]) async {
        var row = extra.body.first { $0.date == date }
            ?? BodyRow(date: date, pretty: date, wt: "", waist: "", chest: "", arm: "", fat: "", notes: "")
        row.wt = fields["wt"] ?? row.wt
        row.waist = fields["waist"] ?? row.waist
        row.chest = fields["chest"] ?? row.chest
        row.arm = fields["arm"] ?? row.arm
        row.fat = fields["fat"] ?? row.fat
        row.notes = fields["notes"] ?? row.notes
        if let at = extra.body.firstIndex(where: { $0.date == date }) { extra.body[at] = row }
        else { extra.body.insert(row, at: 0) }
        if date == Self.stamp.string(from: Date()), let wt = fields["wt"], !wt.isEmpty { state.weight = wt }
        let client = api
        await runFull(note: "⚖️ Saved") { try await client.saveBody(date: date, fields: fields) }
    }

    /// Copies whatever the screen sent into the goal it belongs to.
    private func apply(_ fields: [String: String], to goal: inout Goal) {
        goal.goal = fields["goal"] ?? goal.goal
        goal.why = fields["why"] ?? goal.why
        goal.target = fields["target"] ?? goal.target
        goal.status = fields["status"] ?? goal.status
        goal.notes = fields["notes"] ?? goal.notes
        if let pct = fields["pct"], let value = Int(pct) { goal.pct = value }
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Shared handling

    private func runFull(note: String?, quiet: Bool = false,
                         _ work: @escaping () async throws -> (TrackerState, SheetExtra?)) async {
        if !quiet { busy = true }
        defer { if !quiet { busy = false } }
        do {
            let (fresh, more) = try await work()
            state = fresh
            if let more { extra = more }        /* a light reply leaves the other tabs alone */
            lastSync = Date()
            errorText = nil
            replanAlerts()
            if let note { flash(note) }
        } catch TrackerAPI.Failure.waiting {
            waiting = true
        } catch TrackerAPI.Failure.signedOut {
            signOut()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func run(note: String? = nil, _ work: @escaping () async throws -> TrackerState) async {
        busy = true
        defer { busy = false }
        do {
            state = try await work()
            lastSync = Date()
            errorText = nil
            replanAlerts()
            if let note { flash(note) }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runWithReply(_ work: @escaping () async throws -> (TrackerState, String)) async {
        busy = true
        defer { busy = false }
        do {
            let (fresh, said) = try await work()
            state = fresh
            lastSync = Date()
            errorText = nil
            replanAlerts()
            flash(said.split(separator: "\n").first.map(String.init) ?? "Done")
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// The task nudges and the two daily bookends, always planned together.
    private func replanAlerts() {
        Notifier.reschedule(state, leadMinutes: reminderLead)
        Notifier.bookends(state, habitsDone: habitsDone, habitsTotal: state.habits.count)
    }

    private func flash(_ text: String) {
        guard !text.isEmpty else { return }
        toast = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if self?.toast == text { self?.toast = nil }
        }
    }
}
