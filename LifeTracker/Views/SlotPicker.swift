import SwiftUI

/// The time on a task you are about to add. Nothing picked means all day.
/// Offers half hours from the next one onward, so the common case is one tap.
struct SlotPicker: View {
    @Binding var slot: String
    var dayIsToday: Bool

    @State private var open = false
    @State private var start: Date?
    @State private var end: Date?
    @State private var typed = ""

    var body: some View {
        Button {
            readBack()
            open = true
        } label: {
            Text(slot.isEmpty ? "Set time" : slot)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(UI.sky.opacity(slot.isEmpty ? 0.12 : 0.18), in: Capsule())
                .foregroundStyle(UI.sky)
        }
        .buttonStyle(.plain)
        .help("Pick when this starts — leave it and the task is all day")
        #if os(macOS)
        .popover(isPresented: $open, arrowEdge: .top) {
            picker.frame(width: 320)
        }
        #else
        .sheet(isPresented: $open) {
            picker.presentationDetents([.medium, .large])
        }
        #endif
    }

    // MARK: - The panel

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Set a time").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("All day") { slot = ""; start = nil; end = nil; open = false }
                    .font(.system(size: 12))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    /* once a start is set, the next decision goes on top where it can be seen */
                    if let start {
                        section("Ends", times: endTimes(after: start), picked: end) { choice in
                            end = choice
                            write()
                        }
                    }

                    section(start == nil ? "Starts" : "Change the start",
                            times: startTimes, picked: start) { choice in
                        start = choice
                        end = choice.addingTimeInterval(3600)   /* an hour, unless changed above */
                        write()
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 260)

            VStack(alignment: .leading, spacing: 6) {
                Text("or type it").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("8:15-9 pm", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { useTyped() }
                    Button("Use") { useTyped() }
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Done") { open = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private func section(_ title: String, times: [Date], picked: Date?,
                         tap: @escaping (Date) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 7)], spacing: 7) {
                ForEach(times, id: \.self) { time in
                    let on = picked.map { Calendar.current.isDate($0, equalTo: time, toGranularity: .minute) } ?? false
                    Button { tap(time) } label: {
                        Text(Self.label(time))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(on ? UI.sky : Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - The times on offer

    /// Half hours: from the next one when the day is today, otherwise the whole day.
    private var startTimes: [Date] {
        let calendar = Calendar.current
        let now = Date()
        var first = calendar.startOfDay(for: now)

        if dayIsToday {
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            let minute = parts.minute ?? 0
            parts.minute = minute < 30 ? 30 : 0
            if minute >= 30 { parts.hour = (parts.hour ?? 0) + 1 }
            first = calendar.date(from: parts) ?? now
        }

        let slots = halfHours(from: first)
        return slots.isEmpty ? halfHours(from: calendar.startOfDay(for: now)) : slots
    }

    private func endTimes(after start: Date) -> [Date] {
        Array(halfHours(from: start.addingTimeInterval(1800)).prefix(16))
    }

    /// Every half hour from `first` until that day is out.
    private func halfHours(from first: Date) -> [Date] {
        let calendar = Calendar.current
        let stop = calendar.startOfDay(for: first).addingTimeInterval(24 * 3600)
        var out: [Date] = []
        var cursor = first
        while cursor < stop && out.count < 48 {
            out.append(cursor)
            cursor = cursor.addingTimeInterval(1800)
        }
        return out
    }

    // MARK: - Reading and writing the text

    private func write() {
        guard let start else { return }
        let finish = end ?? start.addingTimeInterval(3600)
        slot = Self.label(start) + " - " + Self.label(finish)
    }

    private func useTyped() {
        let clean = typed.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        slot = clean
        start = nil
        end = nil
        open = false
    }

    /// Puts the two halves of "11:00 AM - 12:00 PM" back on the grid.
    private func readBack() {
        typed = ""
        let halves = slot.components(separatedBy: " - ")
        start = halves.first.flatMap(Self.moment)
        end = halves.count > 1 ? Self.moment(halves[1]) : nil
        if start == nil { typed = slot }
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
