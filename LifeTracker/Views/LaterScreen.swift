import SwiftUI

/// Everything that is not for today: ideas, plans and notes, in one list.
/// A task you will not get to goes here; anything here can come back to Today.
struct LaterScreen: View {
    @Environment(Store.self) private var store
    @State private var draft = ""
    @State private var showDone = false
    @State private var opened: Goal?
    @FocusState private var typing: Bool

    static let states = ["Idea", "In progress", "On hold", "Done"]

    private var items: [Goal] {
        let rank = ["In progress": 0, "Idea": 1, "": 1, "On hold": 2, "Done": 3]
        return store.extra.goals
            .filter { showDone ? $0.status == "Done" : $0.status != "Done" }
            .sorted { (rank[$0.status] ?? 1, -$0.row) < (rank[$1.status] ?? 1, -$1.row) }
    }

    private var doneCount: Int { store.extra.goals.filter { $0.status == "Done" }.count }
    private var openCount: Int { store.extra.goals.count - doneCount }

    var body: some View {
        Page {
            PageTitle("Later", subtitle: "Ideas, plans and notes — anything that isn't for today")

            composer

            Picker("", selection: $showDone) {
                Text("Open · \(openCount)").tag(false)
                Text("Done · \(doneCount)").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    if items.isEmpty {
                        EmptyHint(icon: showDone ? "checkmark.seal" : "tray",
                                  text: showDone ? "Nothing finished here yet."
                                                 : "Empty. Save an idea above, or move a task here from Today.")
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, goal in
                        row(goal)
                        if index < items.count - 1 { RowLine(leading: 50) }
                    }
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
        .sheet(item: $opened) { goal in
            LaterDetail(goal: goal).environment(store)
        }
    }

    private var composer: some View {
        let ready = !draft.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(UI.violet, in: Circle())
            TextField("Save an idea, a plan or a note…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($typing)
                .onSubmit(add)
            if ready {
                Button(action: add) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(UI.violet, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(UI.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.violet.opacity(0.22), lineWidth: 1))
    }

    private func row(_ goal: Goal) -> some View {
        let pending = goal.row < 0
        return HStack(spacing: 10) {
            Image(systemName: Self.icon(goal.status))
                .font(.system(size: 14))
                .foregroundStyle(Self.tint(goal.status))
                .frame(width: 28, height: 28)
                .background(Self.tint(goal.status).opacity(0.12), in: Circle())

            Button { if !pending { opened = goal } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.goal)
                        .font(.system(size: 15))
                        .foregroundStyle(goal.status == "Done" ? .secondary : .primary)
                        .strikethrough(goal.status == "Done", color: .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let meta = meta(goal) {
                        Text(meta).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !pending && goal.status != "Done" {
                Button { Task { await store.planToToday(goal) } } label: {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(UI.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(UI.accent)
                }
                .buttonStyle(.plain)
                .help("Put this on today's list")
            }

            Menu {
                Button("Open") { opened = goal }
                Button("Do it today") { Task { await store.planToToday(goal) } }
                Divider()
                ForEach(Self.states, id: \.self) { state in
                    Button { save(goal, ["status": state]) } label: {
                        if goal.status == state || (goal.status.isEmpty && state == "Idea") {
                            Label(state, systemImage: "checkmark")
                        } else { Text(state) }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    Task { await store.saveGoal(row: goal.row, fields: ["goal": goal.goal], remove: true) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .barelyAMenu()
            .disabled(pending)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(minHeight: UI.rowHeight)
        .opacity(pending ? 0.6 : 1)
    }

    private func meta(_ goal: Goal) -> String? {
        var bits: [String] = []
        if goal.status == "In progress" || goal.status == "On hold" { bits.append(goal.status) }
        if goal.pct > 0 && goal.status != "Done" { bits.append("\(goal.pct)%") }
        if !goal.images.isEmpty { bits.append("\(goal.images.count) picture" + (goal.images.count == 1 ? "" : "s")) }
        if !goal.notes.isEmpty { bits.append(goal.notes) }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private func save(_ goal: Goal, _ fields: [String: String]) {
        Task { await store.saveGoal(row: goal.row, fields: fields) }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await store.saveGoal(row: 0, fields: ["goal": text, "status": "Idea", "pct": "0"]) }
    }

    static func icon(_ status: String) -> String {
        switch status {
        case "In progress": return "bolt.fill"
        case "On hold":     return "pause.fill"
        case "Done":        return "checkmark"
        default:            return "lightbulb"
        }
    }

    static func tint(_ status: String) -> Color {
        switch status {
        case "In progress": return UI.accent
        case "On hold":     return .secondary
        case "Done":        return UI.mint
        default:            return UI.amber
        }
    }
}

/// One Later item opened up: its words, where it stands, its pictures.
struct LaterDetail: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var goal: Goal

    @State private var title = ""
    @State private var notes = ""
    @State private var status = "Idea"
    @State private var pct = 0

    private var live: Goal { store.extra.goals.first { $0.row == goal.row } ?? goal }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Later").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }

            TextField("What is it?", text: $title, axis: .vertical)
                .font(.system(size: 20, weight: .semibold))
                .textFieldStyle(.plain)
                .lineLimit(1...4)

            Picker("", selection: $status) {
                ForEach(LaterScreen.states, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if status == "In progress" || pct > 0 {
                HStack(spacing: 12) {
                    ProgressView(value: Double(pct) / 100).tint(pct >= 100 ? UI.mint : UI.accent)
                    Text("\(pct)%").font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    Stepper("", value: $pct, in: 0...100, step: 10).labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                TextField("Links, details, anything…", text: $notes, axis: .vertical)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .lineLimit(3...10)
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PICTURES").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                PlanPictures(goal: live)
            }

            Spacer(minLength: 0)

            HStack {
                Button(role: .destructive) {
                    dismiss()
                    Task { await store.saveGoal(row: goal.row, fields: ["goal": goal.goal], remove: true) }
                } label: { Text("Delete").font(.system(size: 13)) }
                Spacer()
                Button {
                    save()
                    dismiss()
                    Task { await store.planToToday(live) }
                } label: {
                    Label("Do it today", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 460)
        #else
        .presentationDetents([.large])
        #endif
        .onAppear {
            title = goal.goal
            notes = goal.notes
            status = goal.status.isEmpty ? "Idea" : goal.status
            pct = goal.pct
        }
    }

    private func save() {
        var fields: [String: String] = [:]
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty && clean != goal.goal { fields["goal"] = clean }
        if notes != goal.notes { fields["notes"] = notes }
        if status != goal.status { fields["status"] = status }
        if pct != goal.pct { fields["pct"] = String(pct) }
        guard !fields.isEmpty else { return }
        if fields["goal"] == nil { fields["goal"] = goal.goal }
        Task { await store.saveGoal(row: goal.row, fields: fields) }
    }
}
