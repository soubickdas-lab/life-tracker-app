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
    /// The Mac reopens on the page you left, the way the phone already does.
    var pane: Pane = Pane(rawValue: UserDefaults.standard.string(forKey: "macPane") ?? "") ?? .today {
        didSet { UserDefaults.standard.set(pane.rawValue, forKey: "macPane") }
    }
    /// A page Today asked to open. The Mac shows it in place; the phone picks it up
    /// and switches tab (or opens it under More).
    var jump: Pane?

    func open(_ page: Pane) {
        #if os(macOS)
        pane = page
        #else
        jump = page
        #endif
    }
    var loading = false
    var busy = false
    var toast: String?
    var errorText: String?
    @ObservationIgnored private var misses = 0      /* background checks that failed in a row */
    var lastSync: Date?

    /// Who this device is signed in as. Kept so the app opens straight into the day.
    var token: String {
        didSet {
            UserDefaults.standard.set(token, forKey: "token")
            Shared.token = token              /* the widget signs in with the same one */
            if let home = UserDefaults.standard.string(forKey: "apiHome") {
                Shared.box.set(home, forKey: "apiHome")
            }
        }
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

    /// A tick is on screen before the server hears about it, so there is nothing to
    /// wait for. "Updating…" only appears if a call is slow enough to be worth saying.
    private var working = 0
    private var reveal: Task<Void, Never>?

    /// Every change gets a number. A reply only replaces what is on screen when it
    /// is the newest one — otherwise a slow answer would undo a faster tap.
    private var issued = 0

    private func beginWork(quiet: Bool) {
        working += 1
        guard !quiet, reveal == nil else { return }
        reveal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.working > 0 else { return }
            self.busy = true
        }
    }

    private func endWork() {
        working = max(0, working - 1)
        guard working == 0 else { return }
        reveal?.cancel()
        reveal = nil
        busy = false
    }

    init() {
        token = UserDefaults.standard.string(forKey: "token") ?? ""
        if let kept = Cache.load() {
            state = kept.state
            extra = kept.extra
            email = kept.email
            calendarLink = kept.calendar
        }
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
        Cache.clear()
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
                /* often enough that a tick on the phone shows up here while you look */
                try? await Task.sleep(for: .seconds(25))
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

    /// What the menu bar icon says: how much of today is still waiting.
    var menuBarCount: String {
        guard let today = state.todayBlock else { return "" }
        let left = today.openCount
        return left == 0 ? "" : String(left)
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
        if quietly, working > 0 { return }        /* something is mid-flight — its reply is newer */
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

    /// Not a job for today after all: off the day, onto the Long Term list.
    func toLongTerm(_ task: TaskItem) async {
        for day in state.days.indices {
            state.days[day].tasks.removeAll { $0.id == task.id }   /* gone from the day at once */
        }
        extra.scheduled.removeAll { $0.id == task.id }
        let client = api
        await runFull(note: "🎯 Moved to Long Term") { try await client.toLongTerm(task.id) }
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

    // MARK: - Pictures kept with a plan

    func addPlanPicture(_ raw: Data, to goal: Goal) async {
        guard let full = Photo.shrink(raw, longSide: 1800) else {
            errorText = "That file is not a picture."
            return
        }
        beginWork(quiet: false)
        defer { endWork() }
        do {
            let (fresh, more, id) = try await api.addPlanPicture(full, row: goal.row)
            state = fresh
            if let more { extra = more }
            errorText = nil
            flash("🖼 Saved to " + goal.goal)
            if let id, let small = Photo.shrink(full, longSide: 320) { await api.addPlanThumb(small, id: id) }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func planPicture(id: Int, thumb: Bool) async -> Data? {
        try? await api.planPicture(id: id, thumb: thumb)
    }

    func dropPlanPicture(id: Int) async {
        for at in extra.goals.indices { extra.goals[at].images.removeAll { $0 == id } }
        let client = api
        await runFull(note: "🗑 Picture removed") { try await client.dropPlanPicture(id: id) }
    }

    // MARK: - Assistant

    struct ChatLine: Identifiable, Equatable {
        var id = UUID()
        var mine: Bool
        var text: String
        var failed = false
        var picture: Data?            /* a picture sent along with the words */
    }

    var chat: [ChatLine] = []
    var thinking = false

    /// One thing said to the assistant. Whatever it changed comes back with the
    /// answer, so every screen is already right by the time you read the reply.
    func ask(_ text: String, picture: Data? = nil) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || picture != nil, !thinking else { return }

        let before = chat.filter { !$0.failed }.suffix(12).map {
            ["role": $0.mine ? "user" : "model", "text": $0.text]
        }
        chat.append(ChatLine(mine: true, text: clean, picture: picture))
        thinking = true
        defer { thinking = false }

        do {
            let answer = try await api.ask(clean, history: Array(before), picture: picture)
            if let more = answer.extra { extra = more }
            if let fresh = answer.state {
                issued += 1                         /* anything still in flight is older than this */
                state = fresh
                replanAlerts()
            }
            if let month = answer.money { extra.money = month }
            chat.append(ChatLine(mine: false, text: answer.reply ?? "Done."))
        } catch {
            chat.append(ChatLine(mine: false, text: error.localizedDescription, failed: true))
        }
    }

    /// The same, spoken. The bubble shows a mic until the words come back.
    func ask(voice: Data) async {
        guard !thinking else { return }
        let before = chat.filter { !$0.failed }.suffix(12).map {
            ["role": $0.mine ? "user" : "model", "text": $0.text]
        }
        let mine = ChatLine(mine: true, text: "🎤 …")
        chat.append(mine)
        thinking = true
        defer { thinking = false }

        do {
            let answer = try await api.ask("", history: Array(before), voice: voice)
            if let at = chat.firstIndex(where: { $0.id == mine.id }) {
                let words = (answer.heard ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                chat[at].text = words.isEmpty ? "🎤 (nothing heard)" : words
            }
            if let fresh = answer.state {
                issued += 1
                state = fresh
                replanAlerts()
            }
            if let month = answer.money { extra.money = month }
            chat.append(ChatLine(mine: false, text: answer.reply ?? "Done."))
        } catch {
            if let at = chat.firstIndex(where: { $0.id == mine.id }) { chat[at].text = "🎤 voice message" }
            chat.append(ChatLine(mine: false, text: error.localizedDescription, failed: true))
        }
    }

    func clearChat() { chat = [] }

    // MARK: - Money

    /// The month the money screen is showing — this one unless you paged back.
    var moneyShowing: String { extra.money.month.isEmpty ? state.money.month : extra.money.month }
    var moneyIsThisMonth: Bool { moneyShowing == state.money.month }

    /// A rupee in or out. It is on the list and in the balance before the server
    /// has heard of it; the reply then swaps the stand-in for the real row.
    func addMoney(amount: Double, isIn: Bool, category: String, note: String, day: String? = nil) async {
        guard amount > 0 else { return }
        let when = day ?? state.today
        let kind = isIn ? "in" : "out"

        if when.hasPrefix(moneyShowing) {
            extra.money.entries.insert(
                MoneyEntry(id: -Int.random(in: 1...9_999_999), day: when, amount: amount,
                           kind: kind, category: category, note: note), at: 0)
        }
        if when.hasPrefix(state.money.month) {
            if isIn { state.money.came += amount } else { state.money.went += amount }
            state.money.balance += isIn ? amount : -amount
            state.money.entries += 1
            if when == state.today {
                if isIn { state.money.todayIn += amount } else { state.money.todayOut += amount }
            }
        }

        var params = ["api": "money", "amount": String(amount), "kind": kind,
                      "category": category, "note": note, "show": moneyShowing]
        if let day { params["day"] = day }
        await runMoney(params)
    }

    func deleteMoney(_ entry: MoneyEntry) async {
        extra.money.entries.removeAll { $0.id == entry.id }
        if entry.day.hasPrefix(state.money.month) {
            if entry.isIn { state.money.came -= entry.amount } else { state.money.went -= entry.amount }
            state.money.balance += entry.isIn ? -entry.amount : entry.amount
        }
        guard entry.id > 0 else { return }          /* never reached the server */
        await runMoney(["api": "moneydel", "id": String(entry.id), "show": moneyShowing])
    }

    func editMoney(_ entry: MoneyEntry, amount: Double, isIn: Bool, category: String, note: String) async {
        guard entry.id > 0, amount > 0 else { return }
        if let at = extra.money.entries.firstIndex(where: { $0.id == entry.id }) {
            extra.money.entries[at].amount = amount
            extra.money.entries[at].kind = isIn ? "in" : "out"
            extra.money.entries[at].category = category
            extra.money.entries[at].note = note
        }
        await runMoney(["api": "moneyedit", "id": String(entry.id), "amount": String(amount),
                        "kind": isIn ? "in" : "out", "category": category, "note": note,
                        "show": moneyShowing])
    }

    /// What the month began with. An empty answer lets it carry on from last month.
    func setOpening(_ amount: String, month: String) async {
        await runMoney(["api": "moneyopen", "amount": amount, "month": month, "show": moneyShowing])
    }

    func showMoney(month: String) async {
        await runMoney(["api": "moneymonth", "show": month])
    }

    private func runMoney(_ params: [String: String]) async {
        issued += 1
        let mine = issued
        beginWork(quiet: false)
        defer { endWork() }
        do {
            let (fresh, month) = try await api.money(params)
            if mine == issued {
                state = fresh
                if let month { extra.money = month }
            }
            lastSync = Date()
            errorText = nil
            replanAlerts()
        } catch TrackerAPI.Failure.waiting {
            waiting = true
        } catch TrackerAPI.Failure.signedOut {
            signOut()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Journeys

    func startJourney(_ fields: [String: String]) async {
        let client = api
        await runFull(note: "🎯 Started") { try await client.saveJourney(fields) }
    }

    func stopJourney(_ id: Int) async {
        state.journeys.removeAll { $0.id == id }
        let client = api
        await runFull(note: "🗑 Journey removed") { try await client.dropJourney(id) }
    }

    func journeyHabit(_ id: Int, habit: String, remove: Bool, photo: Bool? = nil) async {
        let client = api
        await runFull(note: nil) { try await client.journeyHabit(id, habit: habit, remove: remove, photo: photo) }
    }

    // MARK: - Proof photos

    func sendPhoto(_ bytes: Data, journey: Int, habit: String) async {
        PhotoStore.shared.forget(journey: journey, habit: habit)
        let client = api
        await runFull(note: nil) { try await client.sendPhoto(bytes, journey: journey, habit: habit) }
        if let small = Photo.shrink(bytes, longSide: 320) {
            _ = try? await client.sendPhoto(small, journey: journey, habit: habit, thumb: true)
        }
    }

    func dropPhoto(journey: Int, habit: String, day: String? = nil) async {
        PhotoStore.shared.forget(journey: journey, habit: habit)
        let client = api
        await runFull(note: "🗑 Photo removed") {
            try await client.dropPhoto(journey: journey, habit: habit, day: day)
        }
    }

    func photo(journey: Int, habit: String, day: String? = nil, thumb: Bool = false) async -> Data? {
        try? await api.photo(journey: journey, habit: habit, day: day, thumb: thumb)
    }

    func clearPhotos(journey: Int) async {
        let client = api
        await runFull(note: nil) { try await client.clearPhotos(journey: journey) }
    }

    func photoZip(journey: Int) async -> Data? {
        busy = true
        defer { busy = false }
        do { return try await api.photoZip(journey: journey) }
        catch { errorText = error.localizedDescription; return nil }
    }

    /// Ticking from the journey screen is the same tick as anywhere else.
    func toggle(journeyHabit name: String, on: Bool) async {
        tickLocally(name, on)
        let client = api
        await runFull(note: nil) { try await client.setHabit(name, on) }
    }

    /// The habit grid, the Today chips and the journey all show the same tick, so
    /// they all move at once — the server only confirms it afterwards.
    private func tickLocally(_ name: String, _ on: Bool) {
        if let at = state.habits.firstIndex(where: { $0.name == name }) { state.habits[at].done = on }
        for j in state.journeys.indices {
            guard let at = state.journeys[j].habits.firstIndex(where: { $0.name == name }) else { continue }
            state.journeys[j].habits[at].done = on
            state.journeys[j].doneToday = state.journeys[j].habits
                .filter { $0.due && $0.ticked }.count
        }
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
            state.days[index].tasks.insert(
                TaskItem(id: "pending-" + UUID().uuidString, task: clean,
                         slot: slot.trimmingCharacters(in: .whitespaces), pending: true), at: 0)
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
        guard state.habits.contains(where: { $0.name == habit.name }) else { return }
        let wanted = !habit.done
        tickLocally(habit.name, wanted)
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
        issued += 1
        let mine = issued
        beginWork(quiet: quiet)
        defer { endWork() }
        do {
            let (fresh, more) = try await work()
            /* a tap that came after this one is already on screen — leave it there */
            if mine == issued { state = fresh }
            if let more { extra = more }        /* a light reply leaves the other tabs alone */
            lastSync = Date()
            errorText = nil
            misses = 0
            replanAlerts()
            if let note { flash(note) }
        } catch TrackerAPI.Failure.waiting {
            waiting = true
        } catch TrackerAPI.Failure.signedOut {
            signOut()
        } catch {
            /* a background check that fails once is not news while the day is on screen —
               the next check is seconds away; say so only when it keeps failing */
            misses += 1
            if !quiet || state.days.isEmpty || misses >= 3 { errorText = error.localizedDescription }
        }
    }

    private func run(note: String? = nil, _ work: @escaping () async throws -> TrackerState) async {
        issued += 1
        let mine = issued
        beginWork(quiet: false)
        defer { endWork() }
        do {
            let fresh = try await work()
            if mine == issued { state = fresh }
            lastSync = Date()
            errorText = nil
            replanAlerts()
            if let note { flash(note) }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runWithReply(_ work: @escaping () async throws -> (TrackerState, String)) async {
        issued += 1
        let mine = issued
        beginWork(quiet: false)
        defer { endWork() }
        do {
            let (fresh, said) = try await work()
            if mine == issued { state = fresh }
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
        leaveSnapshot()
    }

    /// A small picture of today, left where the widget can find it.
    private func leaveSnapshot() {
        guard let today = state.todayBlock else { return }
        var snap = Shared.Snapshot()
        snap.pretty = today.pretty
        snap.done = today.doneCount
        snap.total = today.tasks.count
        snap.lines = today.tasks.filter { !$0.done }.prefix(6).map {
            Shared.Snapshot.Line(text: $0.task, slot: $0.slot)
        }
        snap.habitsDone = habitsDone
        snap.habitsTotal = state.habits.count
        if let journey = state.journeys.first {
            snap.journey = journey.name
            snap.journeyLeft = journey.daysLeft
            snap.journeyDone = journey.doneToday
            snap.journeyDue = journey.dueToday
        }
        Shared.save(snap)
        Cache.save(state: state, extra: extra, email: email, calendar: calendarLink)
        #if os(iOS)
        Widgets.nudge()
        #endif
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
