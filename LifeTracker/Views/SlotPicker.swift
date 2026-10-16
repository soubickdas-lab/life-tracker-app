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

    // MARK: - The wheels

    private var picker: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 2)
            HStack {
                Text("Set a time").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(allDay ? "All day ✓" : "All day") { allDay = true }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(allDay ? UI.sky : .secondary)
            }

            /* the phone's wheels ignore the width they are given — each is boxed and clipped */
            HStack(spacing: 8) {
                wheel("Starts", $start)
                wheel("Ends", $end)
            }
            .frame(maxWidth: .infinity)
            .opacity(allDay ? 0.35 : 1)
            .onChange(of: start) { _, fresh in
                allDay = false
                if end <= fresh { end = fresh.addingTimeInterval(3600) }
            }
            .onChange(of: end) { _, _ in allDay = false }

            Text(allDay ? "No time — it sits with the loose tasks."
                        : Self.label(start) + " – " + Self.label(end))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(allDay ? .secondary : UI.sky)

            HStack {
                Button("Cancel") { open = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { write(); open = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func wheel(_ title: String, _ time: Binding<Date>) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            #if os(iOS)
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .frame(width: 166, height: 150)
                .clipped()
                .compositingGroup()
            #else
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
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
            start = Self.nextHalfHour(today: dayIsToday)
            end = start.addingTimeInterval(3600)
            allDay = true
        }
    }

    private static func nextHalfHour(today: Bool) -> Date {
        let calendar = Calendar.current
        let now = Date()
        guard today else { return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now }
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = parts.minute ?? 0
        parts.minute = minute < 30 ? 30 : 0
        if minute >= 30 { parts.hour = (parts.hour ?? 0) + 1 }
        return calendar.date(from: parts) ?? now
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
