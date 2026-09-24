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

    private var day: DayBlock? { store.state.days.first { $0.label == label } }

    var body: some View {
        Page {
            if let day {
                header(day)
                tasks(day)
                if label == "Today" { habits; streak }
            } else {
                Panel { EmptyHint(icon: "arrow.clockwise", text: "Loading your sheet…") }
            }
        }
        .overlay(alignment: .top) { Banner() }
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

    private func tasks(_ day: DayBlock) -> some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                if day.tasks.isEmpty {
                    EmptyHint(icon: "checklist", text: "Nothing on this day yet.\nAdd the first thing below.")
                } else {
                    ForEach(Array(day.tasks.enumerated()), id: \.element.id) { index, task in
                        row(task)
                        if index < day.tasks.count - 1 { RowLine(leading: 52) }
                    }
                }
                RowLine()
                addRow(day)
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        let naming = editing == task.id
        let timing = clockEdit == task.id

        return HStack(spacing: 11) {
            TickCircle(on: task.done) {
                guard !task.pending else { return }
                Task { await store.toggle(task) }
            }

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
                    Spacer(minLength: 8)
                    marks(task)
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)          /* the whole row ticks — let clicks fall through */
                #else
                VStack(alignment: .leading, spacing: 2) {
                    name(task)
                    if !timing {
                        HStack(spacing: 6) {
                            marks(task)
                            timeControl(task, timing: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }

            #if os(macOS)
            if !naming { timeControl(task, timing: timing) }
            #else
            if timing { timeControl(task, timing: true) }
            #endif

            Menu {
                Button(task.done ? "Mark as not done" : "Mark as done") { Task { await store.toggle(task) } }
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

    /// The little marks a task carries: brought over from yesterday, repeats daily.
    @ViewBuilder private func marks(_ task: TaskItem) -> some View {
        if task.carried { Tag(text: "carried", tint: UI.amber) }
        if task.repeats {
            Image(systemName: "repeat")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UI.violet)
        }
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
                    tint: task.slot.isEmpty ? .secondary : UI.sky,
                    strong: !task.slot.isEmpty)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Tap to change the time")
        }
    }

    /// An invisible button under the row, so a click anywhere on it ticks the task.
    private func tickLayer(_ task: TaskItem, busy: Bool) -> some View {
        Button {
            guard !task.pending, !busy else { return }
            Task { await store.toggle(task) }
        } label: {
            Rectangle()
                .fill(Color.primary.opacity(0.0001))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

            TextField("7-8 pm", text: $newSlot)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .multilineTextAlignment(.trailing)
                .frame(width: 84)
                .onSubmit { add(day) }

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
                        Button {
                            Task { await store.toggle(habit) }
                        } label: {
                            HStack(spacing: 9) {
                                TickCircle(on: habit.done, tint: UI.amber) { Task { await store.toggle(habit) } }
                                    .allowsHitTesting(false)
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
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var streak: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last 14 days").font(.system(size: 15, weight: .semibold))
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(store.extra.history) { day in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day.share >= 1 ? UI.mint : UI.accent.opacity(0.65))
                                .frame(height: max(4, 52 * day.share))
                            Text(day.date.prefix(2))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 70, alignment: .bottom)
            }
        }
    }

    // MARK: - Actions

    private func commit(_ task: TaskItem) {
        let clean = draft.trimmingCharacters(in: .whitespaces)
        editing = nil
        focus = nil
        if clean.isEmpty { Task { await store.delete(task) } }
        else if clean != task.task { Task { await store.rename(task, to: clean) } }
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

/// The little message that slides down after something changes.
struct Banner: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let text = store.toast ?? store.errorText {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(store.errorText == nil ? UI.accent : UI.rose, in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.toast = nil; store.errorText = nil }
        }
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
