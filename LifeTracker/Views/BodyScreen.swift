import SwiftUI

/// Weight and measurements, one row a day.
struct BodyScreen: View {
    @Environment(Store.self) private var store
    @State private var wt = ""
    @State private var waist = ""
    @State private var chest = ""
    @State private var arm = ""
    @State private var fat = ""
    @State private var notes = ""
    @State private var day = Date()

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        Page {
            PageTitle("Body", subtitle: store.state.weight.isEmpty ? nil : "Last weight \(store.state.weight) kg") {
                DatePicker("", selection: $day, displayedComponents: .date).labelsHidden()
            }

            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        field("Weight kg", $wt)
                        field("Waist", $waist)
                        field("Chest", $chest)
                        field("Arm", $arm)
                        field("Body fat %", $fat)
                    }
                    TextField("Notes for the day", text: $notes)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Save", action: save)
                            .buttonStyle(.borderedProminent)
                            .disabled(store.busy)
                    }
                }
            }

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    if store.extra.body.isEmpty {
                        EmptyHint(icon: "figure.walk", text: "Nothing logged yet.")
                    } else {
                        ForEach(Array(store.extra.body.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 12) {
                                Text(row.pretty)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(row.wt.isEmpty ? "—" : "\(row.wt) kg")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                Spacer()
                                ForEach(extras(row), id: \.self) { bit in Tag(text: bit) }
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture { load(row) }
                            if index < store.extra.body.count - 1 { RowLine(leading: 18) }
                        }
                    }
                }
            }
        }
        .refreshable { await store.refresh(quietly: true) }
        .onAppear { if let latest = store.extra.body.first { load(latest) } }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            TextField("—", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func extras(_ row: BodyRow) -> [String] {
        var out: [String] = []
        if !row.waist.isEmpty { out.append("waist \(row.waist)") }
        if !row.chest.isEmpty { out.append("chest \(row.chest)") }
        if !row.arm.isEmpty { out.append("arm \(row.arm)") }
        if !row.fat.isEmpty { out.append("fat \(row.fat)%") }
        return out
    }

    private func load(_ row: BodyRow) {
        wt = row.wt; waist = row.waist; chest = row.chest
        arm = row.arm; fat = row.fat; notes = row.notes
        if let parsed = Self.stamp.date(from: row.date) { day = parsed }
    }

    private func save() {
        let fields = ["wt": wt, "waist": waist, "chest": chest, "arm": arm, "fat": fat, "notes": notes]
        Task { await store.saveBody(date: Self.stamp.string(from: day), fields: fields) }
    }
}
