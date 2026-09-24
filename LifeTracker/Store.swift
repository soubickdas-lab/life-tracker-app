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

    var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: "endpoint") }
    }
    var key: String {
        didSet { UserDefaults.standard.set(key, forKey: "key") }
    }

    var api: TrackerAPI { TrackerAPI(endpoint: endpoint, key: key) }
    var isConfigured: Bool { api.isConfigured }

    init() {
        endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? ""
        key = UserDefaults.standard.string(forKey: "key") ?? ""
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
        await runFull(note: nil) { try await client.full() }
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
        let client = api
        await run(note: "⚖️ \(kg) kg") { try await client.logWeight(kg) }
    }

    func addNote(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let client = api
        await run(note: "🗒 Noted") { try await client.addNote(clean) }
    }

    func setRepeat(_ task: TaskItem, _ on: Bool) async {
        let client = api
        await runFull(note: nil) { try await client.setRepeat(task.id, on) }
    }

    func schedule(_ text: String, date: String, slot: String) async {
        let client = api
        await runFull(note: "🗓️ \(text)") { try await client.schedule(text, date: date, slot: slot) }
    }

    func setSetting(_ name: String, _ value: String) async {
        let client = api
        await runFull(note: "⚙️ \(name)") { try await client.setSetting(name, value) }
    }

    func saveHabit(slot: Int, name: String, target: String, active: Bool, remove: Bool = false) async {
        let client = api
        await runFull(note: remove ? "🗑 \(name)" : "🔥 \(name)") {
            try await client.saveHabit(slot: slot, name: name, target: target, active: active, remove: remove)
        }
    }

    func category(_ text: String, remove: Bool) async {
        let client = api
        await runFull(note: remove ? "🗑 \(text)" : "🏷 \(text)") { try await client.category(text, remove: remove) }
    }

    func saveGoal(row: Int, fields: [String: String], remove: Bool = false) async {
        let client = api
        await runFull(note: remove ? "🗑 Goal removed" : "🎯 Saved") {
            try await client.saveGoal(row: row, fields: fields, remove: remove)
        }
    }

    func saveBody(date: String, fields: [String: String]) async {
        let client = api
        await runFull(note: "⚖️ Saved") { try await client.saveBody(date: date, fields: fields) }
    }

    // MARK: - Shared handling

    private func runFull(note: String?, _ work: @escaping () async throws -> (TrackerState, SheetExtra)) async {
        busy = true
        defer { busy = false }
        do {
            let (fresh, more) = try await work()
            state = fresh
            extra = more
            lastSync = Date()
            errorText = nil
            Notifier.reschedule(state, leadMinutes: reminderLead)
            if let note { flash(note) }
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
            Notifier.reschedule(state, leadMinutes: reminderLead)
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
            Notifier.reschedule(state, leadMinutes: reminderLead)
            flash(said.split(separator: "\n").first.map(String.init) ?? "Done")
        } catch {
            errorText = error.localizedDescription
        }
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
