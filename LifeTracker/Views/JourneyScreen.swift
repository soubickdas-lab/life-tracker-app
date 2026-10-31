import SwiftUI

/// The journey, top to bottom: where you are in it, what today asks for,
/// and how the two numbers that matter — weight and calories — are moving.
struct JourneyScreen: View {
    @Environment(Store.self) private var store
    @State private var writing = false
    @State private var editing: Journey?
    @State private var ending: Journey?
    @State private var kg = ""
    @State private var kcal = ""

    private var journeys: [Journey] { store.state.journeys }

    var body: some View {
        Page {
            if let journey = journeys.first {
                hero(journey)
                today(journey)
                weight(journey)
                calories(journey)
                stats(journey)
            } else {
                Panel {
                    VStack(spacing: 12) {
                        EmptyHint(icon: "flame",
                                  text: "No journey yet.\nSet a target and a date, and the days start counting down.")
                        Button { writing = true } label: { Label("Start a journey", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .sheet(isPresented: $writing) { JourneyForm(journey: nil) }
        .sheet(item: $editing) { JourneyForm(journey: $0) }
        .alert("End this journey?", isPresented: Binding(
            get: { ending != nil },
            set: { if !$0 { ending = nil } })) {
            Button("Keep it", role: .cancel) { ending = nil }
            Button("End journey", role: .destructive) {
                if let journey = ending { Task { await store.stopJourney(journey.id) } }
                ending = nil
            }
        } message: {
            Text("This deletes \(ending?.name ?? "it") and its day count for good. Your habits and weight history stay.")
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    // MARK: - Where you are in it

    private func hero(_ journey: Journey) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(journey.name.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .opacity(0.8)
                    Text(journey.startsIn == 1 ? "Starts tomorrow" : journey.startsIn > 1 ? "Starts in \(journey.startsIn) days" : "Day \(journey.dayNumber)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .tracking(-1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(journey.startsIn > 0 ? "\(journey.daysTotal) days" : "of \(journey.daysTotal)")  ·  \(pretty(journey.starts)) → \(pretty(journey.ends))")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                }
                Spacer()
                menu(journey)
            }

            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { space in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white)
                            .frame(width: max(8, space.size.width * Double(journey.timePct) / 100))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("\(journey.timePct)% of the way")
                    Spacer()
                    Text("\(journey.daysLeft) days left").fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [UI.violet, UI.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: UI.violet.opacity(0.25), radius: 14, y: 6)
    }

    private func menu(_ journey: Journey) -> some View {
        Menu {
            Button("Edit dates and target") { editing = journey }
            let spare = store.state.habits.map(\.name).filter { name in !journey.habits.contains { $0.name == name } }
            if !spare.isEmpty {
                Menu("Add a habit") {
                    ForEach(spare, id: \.self) { name in
                        Button(name) { Task { await store.journeyHabit(journey.id, habit: name, remove: false) } }
                    }
                }
            }
            if !journey.habits.isEmpty {
                Menu("Remove a habit") {
                    ForEach(journey.habits) { habit in
                        Button(habit.name) { Task { await store.journeyHabit(journey.id, habit: habit.name, remove: true) } }
                    }
                }
            }
            Divider()
            Button("Start a new journey") { writing = true }
            Button("End this journey", role: .destructive) { ending = journey }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.18), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Today

    private func today(_ journey: Journey) -> some View {
        let due = journey.habits.filter(\.due)
        let finished = due.filter(\.done).count
        return Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    title("Today")
                    Spacer()
                    Text(due.isEmpty ? "" : "\(finished) of \(due.count)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(!due.isEmpty && finished == due.count ? UI.mint : .secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

                if journey.habits.isEmpty {
                    Text("Add the habits this journey runs on from the ⋯ menu.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(16)
                }
                ForEach(Array(journey.habits.enumerated()), id: \.element.id) { index, habit in
                    Button {
                        guard habit.due else { return }
                        Task { await store.toggle(journeyHabit: habit.name, on: !habit.done) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundStyle(habit.done ? UI.mint : Color.secondary.opacity(0.4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(habit.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(habit.done ? .secondary : .primary)
                                    .strikethrough(habit.done, color: .secondary)
                                if !habit.due {
                                    Text("not due today").font(.system(size: 11)).foregroundStyle(.tertiary)
                                } else if habit.every > 1 {
                                    Text("every \(habit.every) days").font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .opacity(habit.due ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    if index < journey.habits.count - 1 { RowLine(leading: 52) }
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Weight

    private func weight(_ journey: Journey) -> some View {
        let start = Double(journey.from), goal = Double(journey.to)
        let now = Double(journey.now)
        let left = (now ?? start).flatMap { current in goal.map { current - $0 } }
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    title("Weight")
                    Spacer()
                    if let left, left > 0 {
                        Text(String(format: "%.1f %@ to go", left, journey.unit))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(UI.violet)
                    }
                }
                if journey.hasTarget {
                    HStack(spacing: 0) {
                        figure("Start", journey.from, journey.unit, .primary)
                        figure("Now", journey.now.isEmpty ? "—" : journey.now, journey.unit, UI.violet)
                        figure("Goal", journey.to, journey.unit, UI.mint)
                    }
                }
                WeightLine(readings: journey.weights, from: start, to: goal)
                logRow(placeholder: store.state.weight.isEmpty ? "80.5" : store.state.weight, unit: journey.unit.isEmpty ? "kg" : journey.unit,
                       text: $kg, logged: todayRow?.wt ?? "", decimal: true, tint: UI.violet) {
                    let clean = kg.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                    guard Double(clean) != nil else { return }
                    kg = ""
                    Task { await store.logWeight(clean) }
                }
            }
        }
    }

    // MARK: - Calories

    private func calories(_ journey: Journey) -> some View {
        let eaten = Int(store.state.calories)
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    title("Calories")
                    Spacer()
                    if let goal = journey.caloriesGoal {
                        if let eaten {
                            Text(eaten <= goal ? "\(goal - eaten) under" : "\(eaten - goal) over")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(eaten <= goal ? UI.mint : UI.rose)
                        } else {
                            Text("goal \(goal)").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                }
                CalorieBars(days: journey.calories, goal: journey.caloriesGoal)
                logRow(placeholder: "1800", unit: "kcal", text: $kcal, logged: store.state.calories,
                       decimal: false, tint: UI.amber) {
                    let clean = kcal.trimmingCharacters(in: .whitespaces)
                    guard Int(clean) != nil else { return }
                    kcal = ""
                    Task { await store.logCalories(clean) }
                }
            }
        }
    }

    // MARK: - So far

    private func stats(_ journey: Journey) -> some View {
        HStack(spacing: 10) {
            StatTile(label: "Kept", value: "\(journey.keptPct)%", tint: UI.mint)
            StatTile(label: "Perfect days", value: "\(journey.perfectDays)", tint: UI.accent)
            StatTile(label: "Streak", value: "\(journey.perfectRun)", tint: UI.amber)
        }
    }

    // MARK: - Pieces

    private var todayRow: BodyRow? { store.extra.body.first { $0.date == store.state.today } }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 17, weight: .bold, design: .rounded))
    }

    private func figure(_ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(tint)
                if value != "—" { Text(unit).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Today: 82.1 kg" once it is in; a box and a tick until then.
    private func logRow(placeholder: String, unit: String, text: Binding<String>, logged: String,
                        decimal: Bool, tint: Color, save: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            if logged.isEmpty {
                Text("Today").font(.system(size: 14, weight: .medium))
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(UI.mint)
                Text("Today \(logged) \(unit)").font(.system(size: 14, weight: .medium))
            }
            Spacer()
            TextField(logged.isEmpty ? placeholder : "change", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
                #if os(iOS)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                #endif
                .onSubmit(save)
            Text(unit).font(.system(size: 12)).foregroundStyle(.secondary)
            Button(action: save) {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(text.wrappedValue.isEmpty ? tint.opacity(0.15) : tint, in: Capsule())
                    .foregroundStyle(text.wrappedValue.isEmpty ? tint : .white)
            }
            .buttonStyle(.plain)
            .disabled(text.wrappedValue.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pretty(_ day: String) -> String {
        let take = DateFormatter()
        take.dateFormat = "yyyy-MM-dd"
        take.timeZone = TimeZone(identifier: "Asia/Kolkata")
        guard let date = take.date(from: day) else { return day }
        let show = DateFormatter()
        show.dateFormat = "d MMM"
        show.timeZone = take.timeZone
        return show.string(from: date)
    }
}

/// A flat bar — the journey's own progress, next to the ring that counts the days.
struct Meter: View {
    var pct: Int
    var tint: Color

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.14))
                Capsule().fill(tint)
                    .frame(width: max(4, space.size.width * min(1, max(0, Double(pct) / 100))))
                    .animation(.snappy, value: pct)
            }
        }
        .frame(height: 8)
    }
}

/// Start or edit a journey: what it is, when it ends, and the number it moves.
struct JourneyForm: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var journey: Journey?

    @State private var name = ""
    @State private var months = 2
    @State private var byDate = false
    @State private var ends = Date()
    @State private var from = ""
    @State private var to = ""
    @State private var unit = "kg"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(journey == nil ? "Start a journey" : "Edit journey")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("What are you working towards?").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Fat loss", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("By when?").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach([1, 2, 3, 6], id: \.self) { count in
                        Button {
                            months = count; byDate = false
                        } label: {
                            Text(count == 1 ? "1 month" : "\(count) months")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(!byDate && months == count ? UI.accent.opacity(0.18)
                                                                       : Color.primary.opacity(0.05),
                                            in: Capsule())
                                .foregroundStyle(!byDate && months == count ? UI.accent : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        byDate = true
                    } label: {
                        Text("A date")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(byDate ? UI.accent.opacity(0.18) : Color.primary.opacity(0.05),
                                        in: Capsule())
                            .foregroundStyle(byDate ? UI.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
                if byDate {
                    DatePicker("", selection: $ends, in: Date()..., displayedComponents: .date)
                        .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("The number it moves (optional)").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("84", text: $from).textFieldStyle(.roundedBorder).frame(width: 74)
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                    TextField("76", text: $to).textFieldStyle(.roundedBorder).frame(width: 74)
                    TextField("kg", text: $unit).textFieldStyle(.roundedBorder).frame(width: 60)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(journey == nil ? "Start" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 400)
        #endif
        .onAppear { fill() }
    }

    private func fill() {
        guard let journey else { return }
        name = journey.name
        from = journey.from
        to = journey.to
        unit = journey.unit.isEmpty ? "kg" : journey.unit
        let take = DateFormatter()
        take.dateFormat = "yyyy-MM-dd"
        if let date = take.date(from: journey.ends) { ends = date; byDate = true }
    }

    private func save() {
        var fields = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "from": from.trimmingCharacters(in: .whitespaces),
            "to": to.trimmingCharacters(in: .whitespaces),
            "unit": unit.trimmingCharacters(in: .whitespaces),
            "kind": "fatloss",
        ]
        if let journey { fields["id"] = String(journey.id) }
        if byDate {
            let show = DateFormatter()
            show.dateFormat = "yyyy-MM-dd"
            fields["ends"] = show.string(from: ends)
        } else {
            fields["months"] = String(months)
        }
        dismiss()
        Task { await store.startJourney(fields) }
    }
}

/// The line on Today: how far in you are, how far is left, and today's share of it.
struct JourneyStrip: View {
    @Environment(Store.self) private var store
    var journey: Journey

    var body: some View {
        Panel(padding: 14) {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text("\(journey.daysLeft)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(UI.violet)
                    Text(journey.daysLeft == 1 ? "day left" : "days left")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(journey.name)
                            .font(.system(size: 15, weight: .semibold))
                        Text("· " + journey.pace)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Meter(pct: journey.timePct, tint: UI.violet)
                    HStack(spacing: 7) {
                        if journey.dueToday > 0 {
                            Tag(text: "\(journey.doneToday)/\(journey.dueToday) today",
                                tint: journey.doneToday == journey.dueToday ? UI.mint : UI.amber,
                                strong: true)
                        }
                        if let moved = journey.movedPct {
                            Tag(text: "\(moved)% there", tint: UI.violet)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Calories eaten, one bar a day, the goal ruled across. A day over the line is warm.
struct CalorieBars: View {
    var days: [CalorieDay]
    var goal: Int?

    private var points: [(day: String, kcal: Double)] {
        Array(days.compactMap { d in d.value.map { (d.day, $0) } }.suffix(21))
    }

    var body: some View {
        let shown = points
        if shown.isEmpty {
            Text("Log today’s calories below — the bars start here.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            let top = max(Double(goal ?? 0), shown.map(\.kcal).max() ?? 1) * 1.12
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    let height = geo.size.height
                    let slot = geo.size.width / CGFloat(shown.count)
                    let bar = max(6, slot * 0.6)
                    ZStack(alignment: .bottomLeading) {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.offset) { _, p in
                                let over = goal.map { p.kcal > Double($0) } ?? false
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill((over ? UI.rose : UI.mint).opacity(0.85))
                                    .frame(width: bar, height: max(2, CGFloat(p.kcal / top) * height))
                                    .frame(width: slot)
                            }
                        }
                        if let goal {
                            Path { path in
                                let y = height - CGFloat(Double(goal) / top) * height
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                            .stroke(UI.amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }
                    }
                }
                .frame(height: 96)
                HStack {
                    Text(String(shown.first!.day.suffix(5))).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    if let last = shown.last {
                        Text("\(Int(last.kcal)) kcal on \(String(last.day.suffix(5)))"
                             + (goal.map { last.kcal > Double($0) ? " · \(Int(last.kcal) - $0) over" : " · \($0 - Int(last.kcal)) under" } ?? ""))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The weight, day by day, with the target drawn across it. A line, not bars —
/// what matters here is the slope, and whether it points at the mark.
struct WeightLine: View {
    var readings: [WeighIn]
    var from: Double?
    var to: Double?

    private var points: [(day: String, kg: Double)] {
        readings.compactMap { r in r.value.map { (r.day, $0) } }
    }

    /// The window the line is drawn in — wide enough to hold the target too.
    private var span: (low: Double, high: Double) {
        var all = points.map(\.kg)
        if let from { all.append(from) }
        if let to { all.append(to) }
        guard let low = all.min(), let high = all.max() else { return (0, 1) }
        let pad = max(0.4, (high - low) * 0.12)
        return (low - pad, high + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if points.count < 2 {
                Text(points.isEmpty
                     ? "Log today’s weight below — the line starts here."
                     : "One reading so far — log tomorrow's and the line begins.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(height: 60, alignment: .center)
            } else {
                chart
                HStack {
                    Text(short(points.first?.day ?? ""))
                    Spacer()
                    if let latest = points.last {
                        Text("\(trim(latest.kg)) kg")
                            .foregroundStyle(UI.violet)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Text(short(points.last?.day ?? ""))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        GeometryReader { space in
            let width = space.size.width
            let height = space.size.height
            let window = span
            let reach = max(0.001, window.high - window.low)
            let at = { (kg: Double) in height - CGFloat((kg - window.low) / reach) * height }
            let step = points.count > 1 ? width / CGFloat(points.count - 1) : width

            ZStack {
                /* the mark being aimed at */
                if let to {
                    let y = at(to)
                    Path { line in
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(UI.mint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Text("target \(trim(to))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(UI.mint)
                        .position(x: 36, y: max(7, y - 8))
                }

                /* the run of readings, and the ground under it */
                let path = Path { line in
                    for (index, point) in points.enumerated() {
                        let spot = CGPoint(x: CGFloat(index) * step, y: at(point.kg))
                        if index == 0 { line.move(to: spot) } else { line.addLine(to: spot) }
                    }
                }
                path.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .fill(UI.violet)

                Path { shape in
                    shape.addPath(path)
                    shape.addLine(to: CGPoint(x: CGFloat(points.count - 1) * step, y: height))
                    shape.addLine(to: CGPoint(x: 0, y: height))
                    shape.closeSubpath()
                }
                .fill(LinearGradient(colors: [UI.violet.opacity(0.22), UI.violet.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))

                /* today's reading, marked */
                if let last = points.last {
                    Circle()
                        .fill(UI.violet)
                        .frame(width: 7, height: 7)
                        .position(x: CGFloat(points.count - 1) * step, y: at(last.kg))
                }
            }
        }
        .frame(height: 110)
    }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func short(_ day: String) -> String {
        let take = DateFormatter()
        take.dateFormat = "yyyy-MM-dd"
        guard let date = take.date(from: day) else { return day }
        let show = DateFormatter()
        show.dateFormat = "d MMM"
        return show.string(from: date)
    }
}
