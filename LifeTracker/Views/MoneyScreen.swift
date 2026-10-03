import SwiftUI

/// Money: what the month began with, every rupee in and out since, and what is
/// left right now. Nothing here is typed twice — the balance is worked out from
/// the entries, so adding, fixing or removing one changes it on the spot.
struct MoneyScreen: View {
    @Environment(Store.self) private var store

    @State private var amount = ""
    @State private var isIn = false
    @State private var category = ""
    @State private var note = ""
    @State private var askingOpening = false
    @State private var editing: MoneyEntry?
    @FocusState private var typing: Bool

    private var summary: MoneySummary { store.state.money }
    private var month: MoneyMonth { store.extra.money }
    private var thisMonth: Bool { store.moneyIsThisMonth }

    var body: some View {
        Page {
            balance
            if thisMonth { add }
            entries
            if !month.byCategory.isEmpty { breakdown }
            if month.days.contains(where: { $0.out > 0 }) { daily }
        }
        .sheet(isPresented: $askingOpening) {
            OpeningSheet(month: store.moneyShowing, current: shownOpening, typed: shownTyped)
        }
        .sheet(item: $editing) { MoneyEditSheet(entry: $0, categories: month.categories) }
        .refreshable { await store.refresh(quietly: true) }
    }

    // MARK: - What is left

    private var balance: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    pager
                    Spacer()
                    Button { askingOpening = true } label: {
                        Label(thisMonth && !summary.openingTyped ? "Set starting balance" : "Starting balance",
                              systemImage: "pencil")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(thisMonth ? "BALANCE NOW" : "CLOSED AT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(Rupees.text(shownBalance))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(shownBalance < 0 ? UI.rose : .primary)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: shownBalance)
                    Text(openingLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    StatTile(label: "In", value: Rupees.text(shownIn), tint: UI.mint)
                    StatTile(label: "Out", value: Rupees.text(shownOut), tint: UI.rose)
                    if thisMonth {
                        StatTile(label: "Today", value: Rupees.text(summary.todayOut), tint: UI.amber)
                    }
                }
            }
        }
    }

    private var openingLine: String {
        if shownTyped { return "started the month at \(Rupees.text(shownOpening))" }
        if shownOpening == 0 { return "no starting balance yet — set one, or just start adding" }
        return "started at \(Rupees.text(shownOpening)) · carried over from last month"
    }

    private var pager: some View {
        HStack(spacing: 4) {
            Button { Task { await store.showMoney(month: shift(store.moneyShowing, by: -1)) } } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(monthName(store.moneyShowing))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(minWidth: 110)

            Button { Task { await store.showMoney(month: shift(store.moneyShowing, by: 1)) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(thisMonth)
            .opacity(thisMonth ? 0.3 : 1)
        }
    }

    /* This month's numbers ride with every reply and move the instant you add
       something; an older month's come with that month. */
    private var shownIn: Double { thisMonth ? summary.came : month.came }
    private var shownOut: Double { thisMonth ? summary.went : month.went }
    private var shownOpening: Double { thisMonth ? summary.opening : month.opening }
    private var shownTyped: Bool { thisMonth ? summary.openingTyped : month.openingTyped }
    private var shownBalance: Double { thisMonth ? summary.balance : month.balance }

    // MARK: - Adding one

    private var add: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Picker("", selection: $isIn) {
                        Text("Out").tag(false)
                        Text("In").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 130)
                    .onChange(of: isIn) { _, _ in category = "" }

                    HStack(spacing: 4) {
                        Text("₹").font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amount)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .focused($typing)
                            .onSubmit(save)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                ChipRow(options: isIn ? month.categories.in : month.categories.out,
                        picked: $category, tint: isIn ? UI.mint : UI.rose)

                HStack(spacing: 10) {
                    TextField("What was it? (optional)", text: $note)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit(save)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Button(action: save) {
                        Text(isIn ? "Add income" : "Add expense")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isIn ? UI.mint : UI.accent)
                    .disabled(parsed == nil)
                }
            }
        }
    }

    private var parsed: Double? {
        let clean = amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(clean), value > 0 else { return nil }
        return value
    }

    private func save() {
        guard let value = parsed else { return }
        let kind = isIn, tag = category, words = note.trimmingCharacters(in: .whitespaces)
        amount = ""
        note = ""
        Task { await store.addMoney(amount: value, isIn: kind, category: tag, note: words) }
    }

    // MARK: - The month, line by line

    private var entries: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("ENTRIES")
                        .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(month.entries.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(UI.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(UI.accent)
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 8)

                if month.entries.isEmpty {
                    EmptyHint(icon: "indianrupeesign.circle",
                              text: thisMonth ? "Nothing yet this month.\nAdd the first one above."
                                              : "Nothing was written down this month.")
                } else {
                    ForEach(grouped, id: \.day) { group in
                        dayHeader(group.day, rows: group.rows)
                        ForEach(group.rows) { entry in
                            row(entry)
                            if entry.id != group.rows.last?.id { RowLine(leading: 56) }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private var grouped: [(day: String, rows: [MoneyEntry])] {
        var order: [String] = []
        var bucket: [String: [MoneyEntry]] = [:]
        for entry in month.entries {
            if bucket[entry.day] == nil { order.append(entry.day) }
            bucket[entry.day, default: []].append(entry)
        }
        return order.map { ($0, bucket[$0] ?? []) }
    }

    private func dayHeader(_ day: String, rows: [MoneyEntry]) -> some View {
        let net = rows.reduce(0.0) { $0 + ($1.isIn ? $1.amount : -$1.amount) }
        return HStack {
            Text(dayName(day))
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(Rupees.text(net, sign: true))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
    }

    private func row(_ entry: MoneyEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isIn ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(entry.isIn ? UI.mint : UI.rose)
                .frame(width: 28, height: 28)
                .background((entry.isIn ? UI.mint : UI.rose).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category.isEmpty ? (entry.isIn ? "Income" : "Expense") : entry.category)
                    .font(.system(size: 14, weight: .medium))
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            Text(Rupees.text(entry.isIn ? entry.amount : -entry.amount, sign: true))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.isIn ? UI.mint : .primary)
                .opacity(entry.id < 0 ? 0.55 : 1)        /* still on its way to the server */

            Menu {
                Button("Edit") { editing = entry }
                    .disabled(entry.id < 0)
                Button("Remove", role: .destructive) { Task { await store.deleteMoney(entry) } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Where it went

    private var breakdown: some View {
        let total = max(1, month.byCategory.reduce(0) { $0 + $1.total })
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("WHERE IT WENT")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(.secondary)
                ForEach(Array(month.byCategory.enumerated()), id: \.element.id) { index, slice in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(slice.name).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(Rupees.text(slice.total))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("\(Int((slice.total / total * 100).rounded()))%")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        Meter(pct: Int((slice.total / total * 100).rounded()),
                              tint: Self.tints[index % Self.tints.count])
                    }
                }
            }
        }
    }

    private static let tints: [Color] = [UI.rose, UI.amber, UI.violet, UI.sky, UI.mint, UI.accent]

    // MARK: - Day by day

    private var daily: some View {
        let top = max(1, month.days.map(\.out).max() ?? 1)
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SPENT EACH DAY")
                        .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("most \(Rupees.text(top))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(month.days) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.day == store.state.today ? UI.accent : UI.rose.opacity(0.55))
                                .frame(height: max(3, 74 * day.out / top))
                            Text(String(Int(day.day.suffix(2)) ?? 0))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 92, alignment: .bottom)
            }
        }
    }

    // MARK: - Dates

    private func shift(_ month: String, by step: Int) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return month }
        var year = parts[0], number = parts[1] + step
        if number < 1 { number = 12; year -= 1 }
        if number > 12 { number = 1; year += 1 }
        return String(format: "%04d-%02d", year, number)
    }

    private func monthName(_ month: String) -> String {
        let take = DateFormatter(); take.dateFormat = "yyyy-MM"
        guard let date = take.date(from: month) else { return month }
        let show = DateFormatter(); show.dateFormat = "MMMM yyyy"
        return show.string(from: date)
    }

    private func dayName(_ day: String) -> String {
        if day == store.state.today { return "Today" }
        let take = DateFormatter(); take.dateFormat = "yyyy-MM-dd"
        guard let date = take.date(from: day) else { return day }
        let show = DateFormatter(); show.dateFormat = "EEE d MMM"
        return show.string(from: date)
    }
}

/// A row of things to pick one of — categories, here. Tap again to unpick.
struct ChipRow: View {
    var options: [String]
    @Binding var picked: String
    var tint: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(options, id: \.self) { name in
                    Button { picked = picked == name ? "" : name } label: {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(picked == name ? tint.opacity(0.18) : Color.primary.opacity(0.05),
                                        in: Capsule())
                            .foregroundStyle(picked == name ? tint : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

/// What the month began with.
struct OpeningSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var month: String
    var current: Double
    var typed: Bool

    @State private var amount = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Starting balance").font(.title3.weight(.semibold))
            Text("What you had when the month began. Everything you add after is counted from here.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text("₹").font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("0", text: $amount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .onSubmit(save)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                if typed {
                    Button("Carry on from last month") {
                        dismiss()
                        Task { await store.setOpening("", month: month) }
                    }
                    .font(.system(size: 12))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(Double(amount.replacingOccurrences(of: ",", with: "")) == nil)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 380)
        #endif
        .onAppear {
            amount = current == 0 ? "" : (current == current.rounded() ? String(Int(current)) : String(current))
        }
    }

    private func save() {
        let clean = amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard Double(clean) != nil else { return }
        dismiss()
        Task { await store.setOpening(clean, month: month) }
    }
}

/// Fixing one line.
struct MoneyEditSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var entry: MoneyEntry
    var categories: MoneyCategories

    @State private var amount = ""
    @State private var isIn = false
    @State private var category = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit entry").font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                Picker("", selection: $isIn) {
                    Text("Out").tag(false)
                    Text("In").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130)

                HStack(spacing: 4) {
                    Text("₹").font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $amount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            ChipRow(options: isIn ? categories.in : categories.out, picked: $category,
                    tint: isIn ? UI.mint : UI.rose)

            TextField("What was it?", text: $note)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack {
                Button("Remove", role: .destructive) {
                    dismiss()
                    Task { await store.deleteMoney(entry) }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    guard let value = Double(amount.replacingOccurrences(of: ",", with: "")), value > 0 else { return }
                    dismiss()
                    Task { await store.editMoney(entry, amount: value, isIn: isIn, category: category, note: note) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 420)
        #endif
        .onAppear {
            amount = entry.amount == entry.amount.rounded() ? String(Int(entry.amount)) : String(entry.amount)
            isIn = entry.isIn
            category = entry.category
            note = entry.note
        }
    }
}

/// The line on Today: what is left, and what today has cost so far.
struct MoneyStrip: View {
    var money: MoneySummary

    var body: some View {
        Panel(padding: 14) {
            HStack(spacing: 14) {
                Image(systemName: "indianrupeesign")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(UI.mint)
                    .frame(width: 38, height: 38)
                    .background(UI.mint.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(Rupees.text(money.balance))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(money.balance < 0 ? UI.rose : .primary)
                        .contentTransition(.numericText())
                    Text("balance")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    if money.todayOut > 0 {
                        Tag(text: "today " + Rupees.text(-money.todayOut), tint: UI.rose, strong: true)
                    }
                    if money.todayIn > 0 {
                        Tag(text: "today " + Rupees.text(money.todayIn, sign: true), tint: UI.mint, strong: true)
                    }
                    if money.todayOut == 0 && money.todayIn == 0 {
                        Tag(text: "nothing spent today", tint: UI.mint)
                    }
                }
            }
        }
    }
}
