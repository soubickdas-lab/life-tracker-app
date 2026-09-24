import SwiftUI

/// Anything worth keeping that is not a task.
struct NotesScreen: View {
    @Environment(Store.self) private var store
    @State private var note = ""

    var body: some View {
        Page {
            PageTitle("Notes", subtitle: "Quick things to remember")

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(UI.accent)
                        TextField("buy protein", text: $note)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit(add)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: UI.rowHeight)

                    if store.state.notes.isEmpty {
                        RowLine()
                        EmptyHint(icon: "note.text", text: "Nothing noted yet.")
                    } else {
                        ForEach(Array(store.state.notes.enumerated()), id: \.element.id) { index, item in
                            RowLine(leading: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.text).font(.system(size: 14))
                                Text(item.when).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .id(index)
                        }
                    }
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    private func add() {
        let text = note
        note = ""
        Task { await store.addNote(text) }
    }
}
