import SwiftUI

/// Things booked for a later date — they drop onto the day tab by themselves.
struct ScheduledScreen: View {
    @Environment(Store.self) private var store
    @State private var task = ""
    @State private var slot = ""
    @State private var date = Date().addingTimeInterval(2 * 86_400)

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        Page {
            PageTitle("Scheduled", subtitle: "Booked past tomorrow")

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    if store.extra.scheduled.isEmpty {
                        EmptyHint(icon: "calendar", text: "Nothing booked yet.")
                    } else {
                        ForEach(Array(store.extra.scheduled.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(UI.violet.opacity(0.15))
                                    .frame(width: 42, height: 38)
                                    .overlay {
                                        Text(item.pretty.suffix(6))
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(UI.violet)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task).font(.system(size: 14))
                                    Text(item.pretty).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Tag(text: item.slot.isEmpty ? "All day" : item.slot,
                                    tint: item.slot.isEmpty ? .secondary : UI.sky, strong: !item.slot.isEmpty)
                                Button {
                                    Task { await store.delete(TaskItem(id: item.id, task: item.task, slot: item.slot)) }
                                } label: {
                                    Image(systemName: "trash").font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            if index < store.extra.scheduled.count - 1 { RowLine(leading: 70) }
                        }
                    }
                }
            }

            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Book something").font(.system(size: 15, weight: .semibold))
                    #if os(macOS)
                    HStack(spacing: 10) { bookingFields; addButton }
                    #else
                    VStack(spacing: 10) {
                        bookingFields
                        addButton.frame(maxWidth: .infinity)
                    }
                    #endif
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    @ViewBuilder private var bookingFields: some View {
        TextField("Dentist", text: $task)
            .textFieldStyle(.roundedBorder)
            .onSubmit(add)
        HStack(spacing: 10) {
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
            TextField("7-8 pm", text: $slot)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onSubmit(add)
        }
    }

    private var addButton: some View {
        Button("Add", action: add)
            .buttonStyle(.borderedProminent)
            .disabled(task.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func add() {
        let name = task.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let when = Self.stamp.string(from: date), s = slot
        task = ""; slot = ""
        Task { await store.schedule(name, date: when, slot: s) }
    }
}
