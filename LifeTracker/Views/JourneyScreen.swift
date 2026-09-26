import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A journey is one thing you are working towards by a date — losing weight, say —
/// and the handful of habits that get you there. Nothing here is ticked twice: the
/// habits are your ordinary habits, so a tick anywhere counts here too.
struct JourneyScreen: View {
    @Environment(Store.self) private var store
    @State private var writing = false
    @State private var editing: Journey?
    @State private var clearing: Journey?
    #if os(iOS)
    @State private var saved: SavedFile?
    #endif

    private var journeys: [Journey] { store.state.journeys }

    var body: some View {
        Page {
            if journeys.isEmpty {
                Panel {
                    VStack(spacing: 12) {
                        EmptyHint(icon: "flag.checkered",
                                  text: "No journey yet.\nSet a target and a date, and the days start counting down.")
                        Button { writing = true } label: {
                            Label("Start a journey", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ForEach(journeys) { journey in
                    countdown(journey)
                    if journey.hasTarget { target(journey) }
                    habits(journey)
                    shelf(journey)
                    record(journey)
                }
                Button { writing = true } label: {
                    Label("Start another", systemImage: "plus")
                }
                .font(.system(size: 13))
            }
        }
        .sheet(isPresented: $writing) { JourneyForm(journey: nil) }
        .sheet(item: $editing) { JourneyForm(journey: $0) }
        #if os(iOS)
        .sheet(item: $saved) { ShareSheet(item: $0) }
        #endif
        .alert("Delete every photo?", isPresented: Binding(
            get: { clearing != nil },
            set: { if !$0 { clearing = nil } })) {
            Button("Cancel", role: .cancel) { clearing = nil }
            Button("Delete", role: .destructive) {
                if let journey = clearing { Task { await store.clearPhotos(journey: journey.id) } }
                clearing = nil
            }
        } message: {
            Text("Download the zip first — this cannot be undone.")
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    // MARK: - The clock

    private func countdown(_ journey: Journey) -> some View {
        Panel {
            HStack(alignment: .center, spacing: 18) {
                Ring(progress: Double(journey.timePct) / 100, size: 68, width: 7)
                VStack(alignment: .leading, spacing: 5) {
                    Text(journey.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(pretty(journey.starts)) → \(pretty(journey.ends))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        Tag(text: "day \(journey.dayNumber) of \(journey.daysTotal)", tint: UI.accent)
                        Tag(text: "\(journey.daysLeft) left", tint: UI.violet, strong: true)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Edit") { editing = journey }
                    Button("End this journey", role: .destructive) {
                        Task { await store.stopJourney(journey.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - The number you are chasing

    private func target(_ journey: Journey) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                heading("Where you are")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(journey.from).font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text("\(journey.to) \(journey.unit)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Spacer()
                    if !journey.now.isEmpty {
                        Text("now \(journey.now) \(journey.unit)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(UI.violet)
                    }
                }
                Meter(pct: journey.movedPct ?? 0, tint: UI.violet)
                Text(journey.movedPct == nil
                     ? "Log today's weight and this fills in."
                     : "\(journey.movedPct ?? 0)% of the way there")
                    .font(.system(size: 11)).foregroundStyle(.secondary)

                WeightLine(readings: journey.weights,
                           from: Double(journey.from),
                           to: Double(journey.to))
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - The habits that get you there

    private func habits(_ journey: Journey) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    heading("What gets you there")
                    Spacer()
                    Text("\(journey.doneToday)/\(journey.dueToday) today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(journey.dueToday > 0 && journey.doneToday == journey.dueToday
                                         ? UI.mint : .secondary)
                }

                if journey.habits.isEmpty {
                    Text("Attach the habits this journey lives on — ticking them anywhere counts here.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(journey.habits) { habit in
                    ProofRow(journey: journey, habit: habit)
                }

                let spare = store.state.habits
                    .map(\.name)
                    .filter { name in !journey.habits.contains { $0.name == name } }
                if !spare.isEmpty {
                    Menu {
                        ForEach(spare, id: \.self) { name in
                            Button(name) {
                                Task { await store.journeyHabit(journey.id, habit: name, remove: false) }
                            }
                        }
                    } label: {
                        Label("Add a habit", systemImage: "plus.circle")
                            .font(.system(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - The photos

    @ViewBuilder private func shelf(_ journey: Journey) -> some View {
        if journey.habits.contains(where: { $0.needsPhoto }) {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        heading("Photos")
                        Spacer()
                        if journey.photos > 0 {
                            Text("\(journey.photos) saved")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(journey.photos > 0
                         ? "Keep them until the journey is done, take the zip, then start clean."
                         : "The habits marked with a camera tick when their photo is in.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button { save(journey) } label: {
                            Label("Download all (zip)", systemImage: "square.and.arrow.down")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(journey.photos == 0)

                        Button(role: .destructive) { clearing = journey } label: {
                            Text("Delete them").font(.system(size: 13))
                        }
                        .disabled(journey.photos == 0)
                    }
                }
            }
        }
    }

    /// Writes the zip somewhere the pictures will outlive the journey.
    private func save(_ journey: Journey) {
        Task {
            guard let zip = await store.photoZip(journey: journey.id) else { return }
            let name = journey.name.replacingOccurrences(of: " ", with: "-").lowercased() + "-photos.zip"
            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            guard panel.runModal() == .OK, let where_ = panel.url else { return }
            try? zip.write(to: where_)
            store.toast = "📦 Saved"
            #else
            let where_ = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? zip.write(to: where_)
            saved = SavedFile(url: where_)
            #endif
        }
    }

    // MARK: - How it has gone

    private func record(_ journey: Journey) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                heading("So far")
                HStack(spacing: 10) {
                    StatTile(label: "Kept", value: "\(journey.keptPct)%", tint: UI.mint)
                    StatTile(label: "Perfect days", value: "\(journey.perfectDays)", tint: UI.accent)
                    StatTile(label: "On a run of", value: "\(journey.perfectRun)", tint: UI.amber)
                }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
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
                        Text("· day \(journey.dayNumber) of \(journey.daysTotal)")
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
                     ? "Log your weight on Today and the line starts here."
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
