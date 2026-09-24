import SwiftUI

/// Today's habits as tappable chips, with the streak on each one.
struct HabitStrip: View {
    @Environment(Store.self) private var store

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 10)]
    }

    var body: some View {
        if !store.state.habits.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Habits")
                            .font(.headline)
                        Spacer()
                        Text("\(store.habitsDone)/\(store.state.habits.count)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(store.state.habits) { habit in
                            Button {
                                Task { await store.toggle(habit) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: habit.done ? "flame.fill" : "circle")
                                        .foregroundStyle(habit.done ? Theme.amber : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(habit.name)
                                            .font(.callout)
                                            .lineLimit(1)
                                        if habit.streak > 0 {
                                            Text("\(habit.streak) day streak")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        } else if !habit.target.isEmpty {
                                            Text(habit.target)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(habit.done ? Theme.amber.opacity(0.14) : Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
