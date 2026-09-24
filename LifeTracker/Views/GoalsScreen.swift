import SwiftUI

/// The long-term plans, with how far along each one is.
struct GoalsScreen: View {
    @Environment(Store.self) private var store
    @State private var newGoal = ""

    private let states = ["Idea", "In progress", "On hold", "Done"]

    var body: some View {
        Page {
            PageTitle("Long term", subtitle: "The big things that take more than a day")

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    if store.extra.goals.isEmpty {
                        EmptyHint(icon: "target", text: "No plans here yet.")
                    } else {
                        ForEach(Array(store.extra.goals.enumerated()), id: \.element.id) { index, goal in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(goal.goal).font(.system(size: 14, weight: .medium))
                                    Spacer()
                                    Menu {
                                        ForEach(states, id: \.self) { state in
                                            Button(state) { save(goal, ["status": state]) }
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            Task { await store.saveGoal(row: goal.row, fields: ["goal": goal.goal], remove: true) }
                                        }
                                    } label: {
                                        Tag(text: goal.status.isEmpty ? "Idea" : goal.status,
                                            tint: goal.status == "Done" ? UI.mint : UI.sky, strong: true)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                }
                                HStack(spacing: 12) {
                                    ProgressView(value: Double(goal.pct) / 100)
                                        .tint(goal.pct >= 100 ? UI.mint : UI.accent)
                                    Text("\(goal.pct)%")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                    Stepper("", value: Binding(get: { goal.pct },
                                                               set: { save(goal, ["pct": String($0)]) }),
                                            in: 0...100, step: 10)
                                        .labelsHidden()
                                    if !goal.target.isEmpty { Tag(text: goal.target, tint: UI.amber) }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            if index < store.extra.goals.count - 1 { RowLine(leading: 18) }
                        }
                    }
                    RowLine()
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(UI.accent)
                        TextField("New plan…", text: $newGoal)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit(add)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: UI.rowHeight)
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    private func save(_ goal: Goal, _ fields: [String: String]) {
        Task { await store.saveGoal(row: goal.row, fields: fields) }
    }

    private func add() {
        let text = newGoal.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        newGoal = ""
        Task { await store.saveGoal(row: 0, fields: ["goal": text, "status": "Idea", "pct": "0"]) }
    }
}
