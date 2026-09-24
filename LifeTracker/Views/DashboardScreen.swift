import SwiftUI

/// The month in numbers, and how the last two weeks went.
struct DashboardScreen: View {
    @Environment(Store.self) private var store

    var body: some View {
        let dash = store.extra.dash

        Page {
            PageTitle("Dashboard", subtitle: dash.monthLabel)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                StatTile(label: "Tasks done", value: "\(dash.tasksDone)/\(dash.tasksTotal)", tint: UI.mint)
                StatTile(label: "Task rate", value: "\(dash.tasksPct)%", tint: UI.accent)
                StatTile(label: "Habit ticks", value: "\(dash.habitDone)/\(dash.habitCells)", tint: UI.violet)
                StatTile(label: "Habit rate", value: "\(dash.habitPct)%", tint: UI.sky)
                StatTile(label: "Best streak", value: "\(dash.bestStreak)", tint: UI.amber)
                StatTile(label: "Weight", value: store.state.weight.isEmpty ? "—" : "\(store.state.weight) kg", tint: UI.rose)
            }

            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Last 14 days").font(.system(size: 15, weight: .semibold))
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(store.extra.history) { day in
                            VStack(spacing: 6) {
                                Text(day.total == 0 ? "" : "\(day.done)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(day.share >= 1 ? UI.mint : UI.accent.opacity(0.7))
                                    .frame(height: max(5, 90 * day.share))
                                Text(day.date.prefix(2))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(height: 130, alignment: .bottom)
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
    }
}
