import SwiftUI

/// The month at a glance: one row per habit, one dot per day.
struct HabitsScreen: View {
    @Environment(Store.self) private var store
    private let dot: CGFloat = 20

    var body: some View {
        let grid = store.extra.habitGrid

        Page {
            PageTitle("Habits", subtitle: grid.label) {
                Tag(text: "\(store.habitsDone)/\(store.state.habits.count) today", tint: UI.amber, strong: true)
            }

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(grid.rows.enumerated()), id: \.element.id) { index, row in
                        habitRow(row, grid: grid)
                        if index < grid.rows.count - 1 { RowLine(leading: 18) }
                    }
                    if grid.rows.isEmpty {
                        EmptyHint(icon: "flame", text: "No habits yet — add them in Setup.")
                    }
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    private func habitRow(_ row: HabitGridRow, grid: HabitGridData) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(row.name)
                    .font(.system(size: 14, weight: .medium))
                if !row.target.isEmpty {
                    Text(row.target).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if row.streak > 0 { Tag(text: "\(row.streak) day streak", tint: UI.amber, strong: true) }
                Tag(text: "\(row.done) of \(grid.days)", tint: UI.mint)
            }

            #if os(macOS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) { days(row, grid: grid) }
            }
            #else
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dot, maximum: dot), spacing: 5, alignment: .leading)],
                      spacing: 5) {
                days(row, grid: grid)
            }
            #endif
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    /// One tappable square per day of the month.
    @ViewBuilder private func days(_ row: HabitGridRow, grid: HabitGridData) -> some View {
        ForEach(0..<max(0, grid.days), id: \.self) { index in
            let on = index < row.marks.count && row.marks[index]
            let isToday = index + 1 == grid.today
            Button {
                Task { await store.setHabit(row.name, !on, on: key(grid, index + 1)) }
            } label: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(on ? UI.mint : Color.primary.opacity(0.06))
                    .frame(width: dot, height: dot)
                    .overlay {
                        if isToday {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(UI.amber, lineWidth: 1.6)
                        }
                    }
                    .overlay {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(on ? .white : .secondary)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func key(_ grid: HabitGridData, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", grid.year, grid.month, day)
    }
}
