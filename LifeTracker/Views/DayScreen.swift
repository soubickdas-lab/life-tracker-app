import SwiftUI

/// The day, in the order you read it: what is booked at a time, what else is on,
/// and — folded away — whatever rolled over from earlier days.
struct DayScreen: View {
    @Environment(Store.self) private var store

    @State private var label = "Today"
    @State private var newTask = ""
    @State private var newSlot = ""
    @State private var newPriority = false
    @AppStorage("taskSort") private var sortKey = TaskSort.mine.rawValue
    @AppStorage("carriedOpen") private var carriedOpen = false
    @State private var doneOpen = false
    @State private var editing: String?
    @State private var draft = ""
    @State private var timing: TaskItem?
    @State private var confirmLater = false
    @FocusState private var focus: String?
    @State private var dropTarget: String?
    @State private var lingering: Set<String> = []     /* just ticked — still shown in place */

    private var day: DayBlock? { store.state.days.first { $0.label == label } }

    var body: some View {
        Page {
            dayPicker
            if let day {
                header(day)
                composer(day)
                taskPanel(day)
                if label == "Today", let journey = store.state.journeys.first {
                    JourneyCard(journey: journey)
                }
                if label == "Today" { habitsPanel }
            } else {
                Panel { EmptyHint(icon: "arrow.clockwise", text: "Loading your day…") }
            }
        }
        .onChange(of: focus) { was, now in
            if was != nil, now == nil { putEditorsAway() }
        }
        #if os(macOS)
        .onExitCommand { editing = nil; focus = nil }
        #endif
        .refreshable { await store.refresh(quietly: true) }
        .timeSheet(isPresented: Binding(get: { timing != nil }, set: { if !$0 { timing = nil } }),
                   slot: timing?.slot ?? "", dayIsToday: label == "Today") { picked in
            if let task = timing, picked != task.slot { Task { await store.setTime(task, picked) } }
            timing = nil
        }
        .confirmationDialog("Move everything carried over to Later?", isPresented: $confirmLater,
                            titleVisibility: .visible) {
            Button("Move \(carried.count) to Later") { Task { await store.toLater(carried) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They leave today and wait in Later. You can bring any of them back with one tap.")
        }
    }

    // MARK: - The parts of the day

    private var open: [TaskItem] {
        (day?.tasks ?? []).filter { !$0.done || lingering.contains($0.id) }
    }
    /* the flagged ones come first, whatever day they came from; timed ones by time */
    private var priority: [TaskItem] {
        let flagged = open.filter(\.isPriority)
        return flagged.filter { !$0.start.isEmpty }.sorted { $0.start < $1.start } + flagged.filter { $0.start.isEmpty }
    }
    private var scheduled: [TaskItem] {
        open.filter { !$0.start.isEmpty && !$0.carried && !$0.isPriority }.sorted { $0.start < $1.start }
    }
    private var loose: [TaskItem] {
        (TaskSort(rawValue: sortKey) ?? .mine).apply(open.filter { $0.start.isEmpty && !$0.carried && !$0.isPriority })
    }
    private var carried: [TaskItem] { open.filter { $0.carried && !$0.isPriority } }
    private var done: [TaskItem] {
        (day?.tasks ?? []).filter { $0.done && !lingering.contains($0.id) }
    }

    // MARK: - Top

    private var dayPicker: some View {
        Picker("", selection: $label) {
            Text("Yesterday").tag("Yesterday")
            Text("Today").tag("Today")
            Text("Tomorrow").tag("Tomorrow")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private func header(_ day: DayBlock) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(weekday(day.date))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                Text(summary(day))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Ring(progress: day.progress, size: 50, width: 5)
        }
        .padding(.horizontal, 4)
    }

    private func summary(_ day: DayBlock) -> String {
        let total = day.tasks.count - carried.count
        let finished = day.tasks.filter(\.done).count
        var line = prettyDate(day.date)
        if total > 0 { line += " · \(finished) of \(total) done" }
        return line
    }

    /// The add box: its own tinted strip, so it reads as "type here".
    private func composer(_ day: DayBlock) -> some View {
        let ready = !newTask.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(UI.accent, in: Circle())
            TextField(label == "Today" ? "Add a task…" : "Add to \(label.lowercased())…", text: $newTask)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focus, equals: "new")
                .onSubmit { add(day) }
            Button { newPriority.toggle() } label: {
                Image(systemName: newPriority ? "flag.fill" : "flag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(newPriority ? .white : Color.secondary)
                    .frame(width: 28, height: 26)
                    .background(newPriority ? UI.rose : Color.primary.opacity(0.05), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(newPriority ? "Adding as a priority" : "Add as a priority")
            SlotPicker(slot: $newSlot, dayIsToday: label == "Today")
            if ready {
                Button { add(day) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(UI.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.15), value: ready)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(UI.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.accent.opacity(0.22), lineWidth: 1))
    }

    // MARK: - The list

    @ViewBuilder private func taskPanel(_ day: DayBlock) -> some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                if priority.isEmpty && scheduled.isEmpty && loose.isEmpty && carried.isEmpty {
                    EmptyHint(icon: day.tasks.isEmpty ? "sun.max" : "checkmark.seal",
                              text: day.tasks.isEmpty ? "Nothing planned yet." : "All clear — everything is done.")
                }

                if !priority.isEmpty {
                    section("Priority", count: priority.count, tint: UI.rose)
                    rows(priority, timed: false)
                }

                if !scheduled.isEmpty {
                    if !priority.isEmpty { gap }
                    section("Schedule", count: scheduled.count)
                    rows(scheduled, timed: true)
                }

                if !loose.isEmpty {
                    if !scheduled.isEmpty || !priority.isEmpty { gap }
                    section("To do", count: loose.count) { sortMenu }
                    rows(loose, timed: false, draggable: true)
                }

                if !carried.isEmpty {
                    if !priority.isEmpty || !scheduled.isEmpty || !loose.isEmpty { gap }
                    fold(title: "Carried over", count: carried.count, open: $carriedOpen, tint: UI.amber) {
                        Button { confirmLater = true } label: {
                            Text("Move all to Later")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(UI.amber.opacity(0.16), in: Capsule())
                                .foregroundStyle(UI.amber)
                        }
                        .buttonStyle(.plain)
                    }
                    if carriedOpen { rows(carried, timed: false) }
                }

                if !done.isEmpty {
                    gap
                    fold(title: "Done", count: done.count, open: $doneOpen, tint: UI.mint) { EmptyView() }
                    if doneOpen { rows(done, timed: false) }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var gap: some View { RowLine().padding(.top, 4) }

    private func section(_ title: String, count: Int, tint: Color? = nil,
                         @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 8) {
            if let tint {
                Image(systemName: "flag.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(tint ?? .secondary)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 4)
    }

    /// A heading that opens and shuts what is under it.
    private func fold(title: String, count: Int, open: Binding<Bool>, tint: Color,
                      @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { open.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.16), in: Capsule())
                        .foregroundStyle(tint)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var sortMenu: some View {
        let current = TaskSort(rawValue: sortKey) ?? .mine
        return Menu {
            ForEach(TaskSort.allCases) { choice in
                Button { sortKey = choice.rawValue } label: {
                    if choice == current { Label(choice.title, systemImage: "checkmark") } else { Text(choice.title) }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(current == .mine ? Color.secondary : UI.accent)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .barelyAMenu()
        .help("Order: \(current.title)")
    }

    private func rows(_ tasks: [TaskItem], timed: Bool, draggable: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                Group {
                    if draggable { movable(task, timed: timed) } else { row(task, timed: timed) }
                }
                if index < tasks.count - 1 { RowLine(leading: timed ? 118 : 52) }
            }
        }
    }

    /// A To do row can be dragged into a new place.
    private func movable(_ task: TaskItem, timed: Bool) -> some View {
        row(task, timed: timed)
            .draggable(task.id) {
                Text(task.task)
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
                if dropTarget == task.id { Rectangle().fill(UI.accent).frame(height: 2) }
            }
    }

    private func row(_ task: TaskItem, timed: Bool) -> some View {
        HStack(spacing: 10) {
            TickCircle(on: task.done) { tick(task) }

            if timed {
                Button { timing = task } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(TimeSheet.short(task.slot))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(task.rings ? UI.amber : UI.sky)
                        if let end = task.slot.components(separatedBy: " - ").dropFirst().first {
                            Text(end)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 66, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change the time")
            }

            if editing == task.id {
                TextField("Task", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focus, equals: "name-" + task.id)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { focus = "name-" + task.id } }
                    .onSubmit { commit(task) }
            } else {
                HStack(spacing: 6) {
                    Text(task.task)
                        .font(.system(size: 15))
                        .strikethrough(task.done, color: .secondary)
                        .foregroundStyle(task.done ? .secondary : .primary)
                        .lineLimit(2)
                    if task.pending { ProgressView().controlSize(.mini) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !timed && !task.slot.isEmpty {
                Text(TimeSheet.short(task.slot))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            if task.rings && !timed {
                Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(UI.amber)
            }
            if task.repeats {
                Image(systemName: "repeat").font(.system(size: 10, weight: .bold)).foregroundStyle(UI.violet.opacity(0.8))
            }
            if task.isPriority {
                Image(systemName: "flag.fill").font(.system(size: 11)).foregroundStyle(UI.rose)
            }

            menu(task)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: UI.rowHeight)
        .opacity(task.pending ? 0.6 : 1)
    }

    private func menu(_ task: TaskItem) -> some View {
        Menu {
            Button(task.done ? "Mark as not done" : "Mark as done") { tick(task) }
            Button(task.isPriority ? "Remove priority" : "Mark as priority") {
                Task { await store.setPriority(task, !task.isPriority) }
            }
            Button("Rename") { draft = task.task; editing = task.id }
            Button(task.slot.isEmpty ? "Set a time" : "Change the time") { timing = task }
            if !task.slot.isEmpty {
                Button(task.alarm == true ? "Turn the alarm off" : "Alarm at \(TimeSheet.short(task.slot))") {
                    Task { await store.setAlarm(task, task.alarm != true) }
                }
            }
            Button(task.repeats ? "Stop repeating" : "Repeat every day") {
                Task { await store.setRepeat(task, !task.repeats) }
            }
            Divider()
            if label != "Today" {
                Button("Move to today") { Task { await store.move(task, to: "today") } }
            }
            if label != "Tomorrow" {
                Button("Move to tomorrow") { Task { await store.move(task, to: "tomorrow") } }
            }
            Button("Move to Later") { Task { await store.toLongTerm(task) } }
            Divider()
            Button("Delete", role: .destructive) { Task { await store.delete(task) } }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .barelyAMenu()
        .disabled(task.pending)
    }

    // MARK: - Habits that are not part of the journey

    @ViewBuilder private var habitsPanel: some View {
        let journeyHabits = Set(store.state.journeys.flatMap { $0.habits.map(\.name) })
        let habits = store.state.habits.filter { !journeyHabits.contains($0.name) }
        if !habits.isEmpty {
            Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("HABITS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text("\(habits.filter(\.done).count)/\(habits.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button { store.open(.habits) } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Manage habits")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(habits) { habit in
                            Button { Task { await store.toggle(habit) } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(habit.done ? UI.mint : Color.secondary.opacity(0.5))
                                    Text(habit.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(habit.done ? .secondary : .primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    if habit.streak > 1 {
                                        Text("\(habit.streak)🔥").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(habit.done ? UI.mint.opacity(0.10) : Color.primary.opacity(0.035),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func add(_ day: DayBlock) {
        let name = newTask, slot = newSlot, flagged = newPriority
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        newTask = ""; newSlot = ""; newPriority = false
        Task { await store.add(name, slot: slot, to: day, priority: flagged) }
    }

    private func commit(_ task: TaskItem) {
        let clean = draft.trimmingCharacters(in: .whitespaces)
        editing = nil
        focus = nil
        if !clean.isEmpty && clean != task.task { Task { await store.rename(task, to: clean) } }
    }

    /// A tick holds the row in place for a few seconds, so the tap can be seen —
    /// and undone — before it folds into Done.
    private func tick(_ task: TaskItem) {
        guard !task.pending else { return }
        if task.done {
            lingering.remove(task.id)
        } else {
            lingering.insert(task.id)
            let id = task.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.snappy) { _ = lingering.remove(id) }
            }
        }
        Task { await store.toggle(task) }
    }

    private func putEditorsAway() {
        if let id = editing, let task = day?.tasks.first(where: { $0.id == id }) { commit(task) }
        editing = nil
    }

    // MARK: - Dates

    private func date(_ day: String) -> Date? {
        let take = DateFormatter()
        take.locale = Locale(identifier: "en_US_POSIX")
        take.dateFormat = "yyyy-MM-dd"
        return take.date(from: day)
    }

    private func weekday(_ day: String) -> String {
        guard let when = date(day) else { return label }
        let show = DateFormatter()
        show.dateFormat = "EEEE"
        return show.string(from: when)
    }

    private func prettyDate(_ day: String) -> String {
        guard let when = date(day) else { return day }
        let show = DateFormatter()
        show.dateFormat = "d MMMM"
        return (label == "Today" ? "" : label + " · ") + show.string(from: when)
    }
}

/// Fat loss on Today: where you are in it, and today's boxes — one tap each.
struct JourneyCard: View {
    @Environment(Store.self) private var store
    var journey: Journey

    var body: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 11) {
                Button { store.open(.journey) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(UI.violet, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(journey.name).font(.system(size: 15, weight: .semibold))
                            Text(journey.startsIn > 0 ? journey.pace
                                 : "Day \(journey.dayNumber) of \(journey.daysTotal) · \(journey.daysLeft) left")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(journey.doneToday)/\(journey.dueToday)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(journey.dueToday > 0 && journey.doneToday == journey.dueToday ? UI.mint : UI.violet)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 7)], spacing: 7) {
                    ForEach(journey.habits.filter(\.due)) { habit in
                        Button { tap(habit) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: icon(habit))
                                    .font(.system(size: 13))
                                    .foregroundStyle(habit.done ? UI.mint : UI.violet)
                                Text(habit.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(habit.done ? .secondary : .primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(habit.done ? UI.mint.opacity(0.10) : UI.violet.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func icon(_ habit: JourneyHabit) -> String {
        habit.done ? "checkmark.circle.fill" : "circle"
    }

    private func tap(_ habit: JourneyHabit) {
        Task { await store.toggle(journeyHabit: habit.name, on: !habit.done) }
    }
}

/// The orders the To do list can be shown in. "My order" is the one dragging changes.
enum TaskSort: String, CaseIterable, Identifiable {
    case mine, newest, oldest, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mine:   return "My order"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .name:   return "A to Z"
        }
    }

    func apply(_ tasks: [TaskItem]) -> [TaskItem] {
        switch self {
        case .mine:   return tasks
        case .newest: return tasks.sorted { ($0.made ?? "") > ($1.made ?? "") }
        case .oldest: return tasks.sorted { ($0.made ?? "") < ($1.made ?? "") }
        case .name:   return tasks.sorted { $0.task.localizedCaseInsensitiveCompare($1.task) == .orderedAscending }
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
