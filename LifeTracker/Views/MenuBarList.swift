#if os(macOS)
import SwiftUI
import AppKit

/// Today, in the menu bar. Click the icon and the day is there — tick something
/// off without going to the window, then carry on with whatever you were doing.
struct MenuBarList: View {
    @Environment(Store.self) private var store
    @State private var adding = ""
    @FocusState private var typing: Bool

    private var today: DayBlock? { store.state.todayBlock }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !store.isSignedIn {
                hint("Sign in from the window first.")
            } else if store.waiting {
                hint("Your account is waiting to be let in.")
            } else if let today {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        tasks(today)
                        if !store.state.habits.isEmpty { habits }
                        if let journey = store.state.journeys.first { strip(journey) }
                    }
                }
                .frame(minHeight: 392, maxHeight: 560)
                Divider()
                addRow
            } else {
                hint("Loading your day…")
            }

            Divider()
            footer
        }
        .frame(width: 392)
        .task {
            await store.checkDoor()
            if store.isConfigured { await store.refresh(quietly: true) }
        }
    }

    // MARK: - The pieces

    private var header: some View {
        HStack(spacing: 10) {
            if let today { Ring(progress: today.progress, size: 34, width: 4) }
            VStack(alignment: .leading, spacing: 1) {
                Text("Today").font(.system(size: 14, weight: .semibold))
                Text(today?.pretty ?? "—")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if store.busy { ProgressView().controlSize(.small) }
            Button { Task { await store.refresh(quietly: true) } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 11)
    }

    @ViewBuilder private func tasks(_ day: DayBlock) -> some View {
        let open = day.tasks.filter { !$0.done }
        if open.isEmpty {
            hint(day.tasks.isEmpty ? "Nothing on today yet." : "All clear — the day is done.")
        } else {
            Text("UPCOMING  \(open.count)")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(open) { task in
                HStack(spacing: 8) {
                    TickCircle(on: false) { Task { await store.toggle(task) } }
                    Text(task.task)
                        .font(.system(size: 13.5))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !task.slot.isEmpty {
                        Text(task.slot)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(UI.accent)
                    } else if task.carried {
                        Text("carried").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 6)
            Text("HABITS  \(store.habitsDone)/\(store.state.habits.count)")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 4)], spacing: 4) {
                ForEach(store.state.habits) { habit in
                    HStack(spacing: 6) {
                        TickCircle(on: habit.done, tint: UI.amber) {
                            Task { await store.toggle(habit) }
                        }
                        .scaleEffect(0.88)
                        Text(habit.name)
                            .font(.system(size: 11.5))
                            .strikethrough(habit.done, color: .secondary)
                            .foregroundStyle(habit.done ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func strip(_ journey: Journey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 6)
            HStack(spacing: 6) {
                Text(journey.name).font(.system(size: 12, weight: .semibold))
                Text("· " + journey.pace)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if journey.dueToday > 0 {
                    Text("\(journey.doneToday)/\(journey.dueToday)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(journey.doneToday == journey.dueToday ? UI.mint : UI.amber)
                }
            }
            .padding(.horizontal, 14)
            Meter(pct: journey.timePct, tint: UI.violet)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(UI.accent)
            TextField("Add to today…", text: $adding)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($typing)
                .onSubmit(send)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack {
            Button("Open Life Tracker") { open() }
                .font(.system(size: 11))
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 22)
    }

    // MARK: - Doing things

    private func send() {
        let clean = adding.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let today else { return }
        adding = ""
        Task { await store.add(clean, slot: "", to: today) }
    }

    /// Brings the real window back, whether it is hidden or just behind something.
    private func open() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
        /* nothing left to show — ask for a fresh one */
        NSApplication.shared.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
    }
}
#endif
