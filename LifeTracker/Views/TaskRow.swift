import SwiftUI

/// One task line: tick circle, name, when it is, and what it carries.
struct TaskRow: View {
    var task: TaskItem
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onMove: (String) -> Void
    var onRename: (String) -> Void
    var onRepeat: (Bool) -> Void

    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.done ? Theme.green : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                if editing {
                    TextField("Task", text: $draft, onCommit: commit)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(task.task)
                        .font(.body)
                        .strikethrough(task.done, color: .secondary)
                        .foregroundStyle(task.done ? .secondary : .primary)
                }

                HStack(spacing: 6) {
                    Chip(text: task.when, tint: task.slot.isEmpty ? .secondary : Theme.teal)
                    if task.repeats { Chip(text: "🔁 daily", tint: Theme.teal) }
                    if task.carried { Chip(text: "carried over", tint: Theme.amber) }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startEdit() }
        .contextMenu {
            Button(task.done ? "Mark as not done" : "Mark as done", action: onToggle)
            Button("Rename…") { startEdit() }
            Button(task.repeats ? "Stop repeating daily" : "Repeat every day") { onRepeat(!task.repeats) }
            Divider()
            Button("Move to 7 pm today") { onMove("7 pm") }
            Button("Move to tomorrow") { onMove("tomorrow") }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            Button { onMove("tomorrow") } label: { Label("Tomorrow", systemImage: "arrow.uturn.right") }
                .tint(Theme.amber)
        }
        #endif
    }

    private func startEdit() {
        draft = task.task
        editing = true
    }

    private func commit() {
        editing = false
        onRename(draft)
    }
}
