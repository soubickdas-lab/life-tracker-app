import SwiftUI

/// What the tracker did, newest first — the sheet keeps three days of it.
struct LogScreen: View {
    @Environment(Store.self) private var store

    var body: some View {
        Page {
            PageTitle("Log", subtitle: "The last three days")

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    if store.extra.log.isEmpty {
                        EmptyHint(icon: "clock.arrow.circlepath", text: "Nothing logged yet.")
                    } else {
                        ForEach(Array(store.extra.log.enumerated()), id: \.element.id) { index, row in
                            line(row)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                            if index < store.extra.log.count - 1 { RowLine(leading: 18) }
                        }
                    }
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    /// One logged moment: wide on the Mac, two lines on a phone.
    @ViewBuilder private func line(_ row: LogRow) -> some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.when)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(row.what).font(.system(size: 13))
            Text(row.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        #else
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(row.what).font(.system(size: 13))
                Spacer(minLength: 0)
                Text(row.when)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}
