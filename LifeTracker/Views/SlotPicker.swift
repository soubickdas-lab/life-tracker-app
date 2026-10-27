import SwiftUI

/// The "Set time" pill in the add box, and the field in the Scheduled form.
/// Both open the same TimeSheet, so a time is set the same way everywhere.
struct SlotPicker: View {
    @Binding var slot: String
    var dayIsToday: Bool
    var style: Style = .composer

    enum Style { case composer, form }

    @State private var open = false

    var body: some View {
        Button { open = true } label: { label }
            .buttonStyle(.plain)
            .help(slot.isEmpty ? "Give this a time" : "Change the time")
            .timeSheet(isPresented: $open, slot: slot, dayIsToday: dayIsToday) { slot = $0 }
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .composer:
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                Text(slot.isEmpty ? "Time" : TimeSheet.short(slot))
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(UI.sky.opacity(slot.isEmpty ? 0.10 : 0.18), in: Capsule())
            .foregroundStyle(slot.isEmpty ? Color.secondary : UI.sky)
        case .form:
            HStack {
                Text(slot.isEmpty ? "No time" : slot)
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
}

extension View {
    /// The time sheet: a popover on the Mac, a half-height sheet on the phone.
    func timeSheet(isPresented: Binding<Bool>, slot: String, dayIsToday: Bool,
                   onDone: @escaping (String) -> Void) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: .top) {
            TimeSheet(initial: slot, dayIsToday: dayIsToday,
                      onDone: { isPresented.wrappedValue = false; onDone($0) },
                      onCancel: { isPresented.wrappedValue = false })
                .frame(width: 360)
        }
        #else
        sheet(isPresented: isPresented) {
            TimeSheet(initial: slot, dayIsToday: dayIsToday,
                      onDone: { isPresented.wrappedValue = false; onDone($0) },
                      onCancel: { isPresented.wrappedValue = false })
                .presentationDetents([.height(480), .large])
        }
        #endif
    }
}

/// Start and end on two wheels, quick picks above, how-long below.
/// It opens on the task's own time, or on now when there is none.
struct TimeSheet: View {
    var initial: String
    var dayIsToday: Bool
    var onDone: (String) -> Void
    var onCancel: () -> Void

    @State private var start = Date()
    @State private var end = Date()
    @State private var noTime = true
    @State private var ready = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(initial.isEmpty ? "Set a time" : "Change the time")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    noTime.toggle()
                } label: {
                    Label("No time", systemImage: noTime ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(noTime ? UI.sky : .secondary)
                }
                .buttonStyle(.plain)
            }

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
                noTime = false
            }

            HStack(spacing: 8) {
                wheel("Starts", $start)
                wheel("Ends", $end)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(noTime ? 0.4 : 1)
            .onChange(of: start) { was, fresh in
                guard ready else { return }
                noTime = false
                /* moving the start carries the end with it, keeping the length */
                let kept = max(1800, end.timeIntervalSince(was))
                if end <= fresh || end.timeIntervalSince(was) > 0 { end = fresh.addingTimeInterval(kept) }
            }
            .onChange(of: end) { _, _ in if ready { noTime = false } }

            chips(["30 min", "45 min", "1 hr", "1.5 hr", "2 hr"]) { pick in
                let minutes: Double = ["30 min": 30, "45 min": 45, "1 hr": 60, "1.5 hr": 90, "2 hr": 120][pick] ?? 60
                end = start.addingTimeInterval(minutes * 60)
                noTime = false
            }

            Text(noTime ? "No time — it goes in To do"
                        : Self.label(start) + " – " + Self.label(end) + "  ·  " + Self.lengthText(end.timeIntervalSince(start)))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(noTime ? .secondary : UI.sky)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onDone(noTime ? "" : Self.label(start) + " - " + Self.label(end))
                } label: {
                    Text(noTime ? "Save without time" : "Set time")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            readBack()
            DispatchQueue.main.async { ready = true }   /* the first fill is not a change */
        }
    }

    private var length: TimeInterval { max(1800, end.timeIntervalSince(start)) }

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

    /// "11:00 AM - 12:00 PM" back onto the wheels; nothing set means now.
    private func readBack() {
        let halves = initial.components(separatedBy: " - ")
        if let from = halves.first.flatMap(Self.moment) {
            start = from
            end = halves.count > 1 ? (Self.moment(halves[1]) ?? from.addingTimeInterval(3600))
                                   : from.addingTimeInterval(3600)
            noTime = false
        } else {
            start = Self.rounded(Date())
            end = start.addingTimeInterval(3600)
            noTime = true
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

    /// "11:00 AM - 12:00 PM" → "11:00 AM", for a pill with little room.
    static func short(_ slot: String) -> String {
        slot.components(separatedBy: " - ").first ?? slot
    }

    /// "11:00 AM" on today's date.
    static func moment(_ text: String) -> Date? {
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "h:mm a"
        guard let bare = reader.date(from: text.trimmingCharacters(in: .whitespaces)) else { return nil }
        let calendar = Calendar.current
        let hm = calendar.dateComponents([.hour, .minute], from: bare)
        return calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: Date())
    }
}
