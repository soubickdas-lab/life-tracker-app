import SwiftUI

/// A day: how it is going, its tasks, and a line to add the next one.
struct DayScreen: View {
    @Environment(Store.self) private var store
    var label: String

    @State private var newTask = ""
    @State private var newSlot = ""
    @State private var editing: String?
    @State private var draft = ""
    @State private var clockEdit: String?
    @State private var clockDraft = ""
    @FocusState private var focus: String?
    @State private var kg = ""
    @State private var dropTarget: String?
    @State private var lingering: Set<String> = []     /* just ticked — still shown up top */

    private var day: DayBlock? { store.state.days.first { $0.label == label } }

    var body: some View {
        Page {
            if let day {
                header(day)
                if label == "Today" {
                    ForEach(store.state.journeys) { JourneyStrip(journey: $0) }
                }
                tasks(day)
                if label == "Today" { habits; weight }
            } else {
                Panel { EmptyHint(icon: "arrow.clockwise", text: "Loading your sheet…") }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { putEditorsAway() }           /* a click on empty space only closes the box */
        .onChange(of: focus) { was, now in
            guard was != nil, now == nil else { return }
            putEditorsAway()                          /* tabbed or clicked away */
        }
        #if os(macOS)
        .onExitCommand { cancelEditors() }            /* Escape drops what was typed */
        #endif
        .refreshable { await store.refresh(quietly: true) }
    }

    // MARK: - Header

    private func header(_ day: DayBlock) -> some View {
        Panel {
            HStack(spacing: 16) {
                Ring(progress: day.progress, size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(day.label)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(day.pretty)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    Tag(text: "\(day.doneCount) done", tint: UI.mint, strong: day.doneCount > 0)
                    Tag(text: "\(day.openCount) left", tint: UI.amber, strong: day.openCount > 0)
                    if store.busy {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Task list

    @ViewBuilder private func tasks(_ day: DayBlock) -> some View {
        let open = day.tasks.filter { !$0.done || lingering.contains($0.id) }
        let done = day.tasks.filter { $0.done && !lingering.contains($0.id) }

        Panel(padding: 0) {
            VStack(spacing: 0) {
                heading("Upcoming", count: open.count, tint: UI.accent)
                if open.isEmpty {
                    EmptyHint(icon: day.tasks.isEmpty ? "checklist" : "checkmark.seal",
                              text: day.tasks.isEmpty ? "Nothing on this day yet.\nAdd the first thing below."
                                                      : "All clear — everything here is done.")
                } else {
                    list(open)
                }
                RowLine()
                addRow(day)
            }
        }

        if !done.isEmpty {
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    heading("Done", count: done.count, tint: UI.mint)
                    list(done)
                }
            }
        }
    }

    /// The header on each of the two lists.
    private func heading(_ title: String, count: Int, tint: Color) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer()
            if count > 0 { Tag(text: "\(count)", tint: tint, strong: true) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    private func list(_ tasks: [TaskItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                oldRowBody(task)
                if index < tasks.count - 1 { RowLine(leading: 52) }
            }
        }
    }

    /// One row, ready to be picked up and dropped somewhere else.
    private func oldRowBody(_ task: TaskItem) -> some View {
        row(task)
            .draggable(task.id) {
                Text(task.task)                     /* what you see under the cursor */
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(UI.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .dropDestination(for: String.self) { dropped, _ in
                guard let moved = dropped.first else { return false }
                Task { await store.reorder(moved, before: task.id, on: label) }
                return true
            } isTargeted: { over in
                dropTarget = over ? task.id : (dropTarget == task.id ? nil : dropTarget)
            }
            .overlay(alignment: .top) {
                if dropTarget == task.id {
                    Rectangle().fill(UI.accent).frame(height: 2)
                }
            }
    }

    private func row(_ task: TaskItem) -> some View {
        let naming = editing == task.id
        let timing = clockEdit == task.id

        return HStack(spacing: 11) {
            TickCircle(on: task.done) { tick(task) }

            if naming {
                TextField("Task", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focus, equals: "name-" + task.id)
                    .onAppear { grabFocus("name-" + task.id) }
                    .onSubmit { commit(task) }
            } else {
                #if os(macOS)
                HStack(spacing: 8) {
                    name(task)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if task.carried { Tag(text: "carried", tint: UI.amber) }
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)          /* the whole row ticks — let clicks fall through */
                #else
                VStack(alignment: .leading, spacing: 3) {
                    name(task)
                        .allowsHitTesting(false)
                    if !timing {
                        HStack(spacing: 6) {
                            if task.carried { Tag(text: "carried", tint: UI.amber) }
                            timeControl(task, timing: false)
                            repeatButton(task)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }

            /* on the Mac the time and the repeat switch live on the right of the row */
            #if os(macOS)
            if !naming {
                timeControl(task, timing: timing)
                repeatButton(task)
            }
            #else
            if timing { timeControl(task, timing: true) }
            #endif

            Menu {
                Button(task.done ? "Mark as not done" : "Mark as done") { tick(task) }
                Button("Rename…") { draft = task.task; editing = task.id }
                Button("Change time…") { clockDraft = task.slot; clockEdit = task.id }
                Button(task.slot.isEmpty ? "Keep all day" : "Clear the time") {
                    Task { await store.setTime(task, "") }
                }
                Button(task.repeats ? "Stop repeating" : "Repeat every day") {
                    Task { await store.setRepeat(task, !task.repeats) }
                }
                Divider()
                Button("Move to tomorrow") { Task { await store.move(task, to: "tomorrow") } }
                Divider()
                Button("Delete", role: .destructive) { Task { await store.delete(task) } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .barelyAMenu()
        }
        .padding(.horizontal, 14)
        .frame(height: UI.rowHeight)
        .opacity(task.pending ? 0.6 : 1)
        .background(alignment: .leading) {
            /* a repeating task wears a violet edge, so the daily ones read at a glance */
            if task.repeats {
                Rectangle()
                    .fill(UI.violet)
                    .frame(width: 3)
                    .clipShape(Capsule())
                    .padding(.vertical, 7)
            }
        }
        .background(tickLayer(task, busy: naming || timing))
    }

    private func name(_ task: TaskItem) -> some View {
        HStack(spacing: 7) {
            Text(task.task)
                .font(.system(size: 14))
                .strikethrough(task.done, color: .secondary)
                .foregroundStyle(task.done ? .secondary : .primary)
                .lineLimit(1)
            if task.pending { ProgressView().controlSize(.mini) }
        }
    }

    /// Tap it and the task comes back tomorrow, and every day after.
    private func repeatButton(_ task: TaskItem) -> some View {
        Button {
            guard !task.pending else { return }
            Task { await store.setRepeat(task, !task.repeats) }
        } label: {
            Image(systemName: "repeat")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(task.repeats ? .white : Color.secondary.opacity(0.5))
                .frame(width: 25, height: 25)
                .background(task.repeats ? UI.violet : Color.primary.opacity(0.05), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: task.repeats)
        .help(task.repeats ? "Repeats every day — tap to stop" : "Repeat this every day")
    }

    /// The time: a tap target that turns into a box you can type in.
    @ViewBuilder private func timeControl(_ task: TaskItem, timing: Bool) -> some View {
        if timing {
            TextField("7-8 pm", text: $clockDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .multilineTextAlignment(.trailing)
                .frame(width: 118)
                .focused($focus, equals: "time-" + task.id)
                .onAppear { grabFocus("time-" + task.id) }
                .onSubmit { commitTime(task) }
        } else {
            Button {
                clockDraft = task.slot
                clockEdit = task.id
            } label: {
                Tag(text: task.when,
                    tint: task.slot.isEmpty ? .secondary : (task.repeats ? UI.violet : UI.sky),
                    strong: !task.slot.isEmpty)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Tap to change the time")
        }
    }

    /// Strictly not a tick target: the circle is the only thing that ticks.
    /// This layer exists only to put away a box that was left open.
    private func tickLayer(_ task: TaskItem, busy: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.0001))
            .contentShape(Rectangle())
            .onTapGesture {
                if editing != nil || clockEdit != nil { putEditorsAway() }
            }
    }

    private func addRow(_ day: DayBlock) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(UI.accent)
                .frame(width: 21, height: 21)

            TextField("Add to \(day.label.lowercased())…", text: $newTask)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit { add(day) }

            SlotPicker(slot: $newSlot, dayIsToday: day.label == "Today")

            Button { add(day) } label: {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(newTask.isEmpty ? .secondary : UI.accent)
            .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: UI.rowHeight)
    }

    // MARK: - Today extras

    private var habits: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Habits").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(store.habitsDone)/\(store.state.habits.count)")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                    ForEach(store.state.habits) { habit in
                        Group {
                            HStack(spacing: 9) {
                                TickCircle(on: habit.done, tint: UI.amber) { Task { await store.toggle(habit) } }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(habit.name)
                                        .font(.system(size: 13))
                                        .strikethrough(habit.done, color: .secondary)
                                        .foregroundStyle(habit.done ? .secondary : .primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if habit.streak > 0 {
                                        Text("\(habit.streak) day streak")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(habit.done ? UI.amber.opacity(0.12) : Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    /// Today's weight, in the same place you tick everything else off.
    private var weight: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Weight").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if !store.state.weight.isEmpty {
                        Tag(text: "last \(store.state.weight) kg", tint: UI.violet, strong: true)
                    }
                }
                HStack(spacing: 10) {
                    TextField("72.5", text: $kg)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .frame(width: 110)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onSubmit { saveWeight() }
                    Text("kg").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Save today") { saveWeight() }
                        .buttonStyle(.borderedProminent)
                        .disabled(Double(kg.trimmingCharacters(in: .whitespaces)) == nil)
                    Spacer()
                }
            }
        }
    }

    private func saveWeight() {
        let clean = kg.trimmingCharacters(in: .whitespaces)
        guard Double(clean) != nil else { return }
        kg = ""
        Task { await store.logWeight(clean) }
    }

    // MARK: - Actions

    private func commit(_ task: TaskItem) {
        let clean = draft.trimmingCharacters(in: .whitespaces)
        editing = nil
        focus = nil
        if clean.isEmpty { Task { await store.delete(task) } }
        else if clean != task.task { Task { await store.rename(task, to: clean) } }
    }

    /// Ticking holds the task where it is for a few seconds, so you can see what you
    /// just did — and undo it — before it drops into Done. Bringing one back is instant.
    private func tick(_ task: TaskItem) {
        guard !task.pending else { return }
        if task.done {
            lingering.remove(task.id)
        } else {
            lingering.insert(task.id)
            let id = task.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                lingering.remove(id)
            }
        }
        Task { await store.toggle(task) }
    }

    /// Saves and shuts whichever box is open. Called when the click, or the focus, goes elsewhere.
    private func putEditorsAway() {
        let tasks = day?.tasks ?? []
        if let id = clockEdit {
            if let task = tasks.first(where: { $0.id == id }) { commitTime(task) } else { clockEdit = nil }
        }
        if let id = editing {
            if let task = tasks.first(where: { $0.id == id }) { commit(task) } else { editing = nil }
        }
        focus = nil
    }

    /// Escape: shut the box and keep what the sheet already had.
    private func cancelEditors() {
        clockEdit = nil
        editing = nil
        focus = nil
    }

    /// A newly shown field is not in the responder chain yet — focus it a tick later.
    private func grabFocus(_ id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { focus = id }
    }

    /// Saves whatever was typed into the row's time box — blank means all day.
    private func commitTime(_ task: TaskItem) {
        let clean = clockDraft.trimmingCharacters(in: .whitespaces)
        clockEdit = nil
        focus = nil
        guard clean != task.slot else { return }
        Task { await store.setTime(task, clean) }
    }

    private func add(_ day: DayBlock) {
        let name = newTask, slot = newSlot
        newTask = ""; newSlot = ""
        Task { await store.add(name, slot: slot, to: day) }
    }
}

extension View {
    /// The ellipsis menu: bare on the Mac, plain on the phone.
    @ViewBuilder func barelyAMenu() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        #else
        self.menuStyle(.button).buttonStyle(.plain).fixedSize()
        #endif
    }
}
