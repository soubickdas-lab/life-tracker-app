import SwiftUI

/// The time on a task: two wheels, start and end, the way the phone's clock does it.
/// Nothing picked means all day. The same picker serves the add box, a task's own
/// time tag and the Scheduled form, so a time is set the same way everywhere.
struct SlotPicker: View {
    @Binding var slot: String
    var dayIsToday: Bool
    var style: Style = .composer

    enum Style {
        case composer                           /* the "Set time" pill in the add box */
        case row(tint: Color, rings: Bool)      /* a task's own time tag, or a clock when it has none */
        case form                               /* a plain field-like button in a form */
    }

    @State private var open = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var allDay = true

    var body: some View {
        Button {
            readBack()
            open = true
        } label: { label }
        .buttonStyle(.plain)
        .help(slot.isEmpty ? "Give this a time" : "Tap to change the time")
        #if os(macOS)
        .popover(isPresented: $open, arrowEdge: .top) {
            picker.frame(width: 340)
        }
        #else
        .sheet(isPresented: $open) {
            picker.presentationDetents([.medium])
        }
        #endif
    }

    // MARK: - The button

    @ViewBuilder private var label: some View {
        switch style {
        case .composer:
            Text(slot.isEmpty ? "Set time" : slot)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(UI.sky.opacity(slot.isEmpty ? 0.12 : 0.18), in: Capsule())
                .foregroundStyle(UI.sky)
        case .row(let tint, let rings):
            if slot.isEmpty {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .frame(width: 25, height: 25)
                    .background(Color.primary.opacity(0.05), in: Circle())
            } else {
                HStack(spacing: 4) {
                    if rings { Image(systemName: "bell.fill").font(.system(size: 9, weight: .bold)) }
                    Text(slot)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.14), in: Capsule())
                .fixedSize()
            }
        case .form:
            HStack {
                Text(slot.isEmpty ? "All day" : slot)
                    .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                Spacer()
                Image(systemName: "clock").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - The panel

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Set a time").font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    allDay.toggle()
                } label: {
                    Label("All day", systemImage: allDay ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(allDay ? UI.sky : .secondary)
                }
                .buttonStyle(.plain)
            }

            /* the usual answers, one tap each */
            chips(["Now", "+15 min", "+30 min", "+1 hr", "Tonight"]) { pick in
                let now = Self.rounded(Date())
                switch pick {
                case "Now":     start = now
                case "+15 min": start = now.addingTimeInterval(15 * 60)
                case "+30 min": start = now.addingTimeInterval(30 * 60)
                case "+1 hr":   start = now.addingTimeInterval(3600)
                default:        start = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
                }
                end = start.addingTimeInterval(length)
                allDay = false
            }

            HStack(spacing: 8) {
                wheel("Starts", $start)
                wheel("Ends", $end)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(allDay ? 0.4 : 1)
            .onChange(of: start) { _, fresh in
                allDay = false
                if end <= fresh { end = fresh.addingTimeInterval(length) }
            }
            .onChange(of: end) { _, _ in allDay = false }

            /* how long it runs */
            chips(["30 min", "45 min", "1 hr", "1.5 hr", "2 hr"]) { pick in
                let minutes: Double = ["30 min": 30, "45 min": 45, "1 hr": 60, "1.5 hr": 90, "2 hr": 120][pick] ?? 60
                end = start.addingTimeInterval(minutes * 60)
                allDay = false
            }

            HStack {
                Text(allDay ? "No time — it sits with the loose tasks"
                            : Self.label(start) + " – " + Self.label(end) + "  ·  " + Self.lengthText(end.timeIntervalSince(start)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(allDay ? .secondary : UI.sky)
                Spacer()
            }

            HStack {
                Button("Cancel") { open = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button { write(); open = false } label: {
                    Text(allDay ? "Save as all day" : "Set time")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A row of small round choices.
    private func chips(_ names: [String], tap: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Button { tap(name) } label: {
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var length: TimeInterval { max(1800, end.timeIntervalSince(start)) }

    private func wheel(_ title: String, _ time: Binding<Date>) -> some View {
        VStack(spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            #if os(iOS)
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .frame(width: 166, height: 140)
                .clipped()
                .compositingGroup()
            #else
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
                .padding(.vertical, 8)
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Reading and writing the text

    private func write() {
        slot = allDay ? "" : Self.label(start) + " - " + Self.label(end)
    }

    /// Puts "11:00 AM - 12:00 PM" back on the wheels; nothing set means the
    /// next half hour, which is the usual answer.
    private func readBack() {
        let halves = slot.components(separatedBy: " - ")
        if let from = halves.first.flatMap(Self.moment) {
            start = from
            end = halves.count > 1 ? (Self.moment(halves[1]) ?? from.addingTimeInterval(3600))
                                   : from.addingTimeInterval(3600)
            allDay = false
        } else {
            start = Self.rounded(Date())
            end = start.addingTimeInterval(3600)
            allDay = true
        }
    }

    /// Now, to the next five minutes — the wheel then starts where the clock is.
    static func rounded(_ date: Date) -> Date {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = parts.minute ?? 0
        let up = (minute + 4) / 5 * 5
        parts.minute = up % 60
        if up >= 60 { parts.hour = (parts.hour ?? 0) + 1 }
        return calendar.date(from: parts) ?? date
    }

    static func lengthText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : String(format: "%.1f hr", Double(minutes) / 60)
    }

    static func label(_ time: Date) -> String {
        let writer = DateFormatter()
        writer.locale = Locale(identifier: "en_US_POSIX")
        writer.dateFormat = "h:mm a"
        return writer.string(from: time)
    }

    /// "11:00 AM" on today's date.
    private static func moment(_ text: String) -> Date? {
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "h:mm a"
        guard let bare = reader.date(from: text.trimmingCharacters(in: .whitespaces)) else { return nil }
        let calendar = Calendar.current
        let hm = calendar.dateComponents([.hour, .minute], from: bare)
        return calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: Date())
    }
}
