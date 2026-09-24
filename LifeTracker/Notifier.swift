import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Local reminders for today's timed tasks: one alert a few minutes before each,
/// re-planned every time the sheet answers so it always matches what is on screen.
@MainActor
enum Notifier {
    private static let prefix = "task-"

    /// Asked for once, the first time the app has a day to show — never while the
    /// connect sheet is up, where the alert used to land on top and get dismissed.
    static func askOnce() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            let status = await state()
            guard status == .notDetermined else { return }
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Asked again from Setup, by the button.
    @discardableResult
    static func ask() async -> UNAuthorizationStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .denied }
        if await state() == .notDetermined {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
        return await state()
    }

    /// What iOS/macOS currently allows.
    static func state() async -> UNAuthorizationStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .denied }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// How many reminders are actually waiting — the honest proof that it works.
    static func waiting() async -> Int {
        guard Bundle.main.bundleIdentifier != nil else { return 0 }
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(prefix) }.count
    }

    /// Opens the page where the switch lives, once the answer was no.
    static func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Clears the old plan and lays out a fresh one for what is still ahead today.
    static func reschedule(_ state: TrackerState, leadMinutes: Int) {
        guard Bundle.main.bundleIdentifier != nil,
              let today = state.todayBlock else { return }

        let centre = UNUserNotificationCenter.current()
        centre.getPendingNotificationRequests { pending in
            let mine = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            centre.removePendingNotificationRequests(withIdentifiers: mine)

            for task in today.tasks where !task.done && !task.pending {
                guard let start = moment(day: today.date, time: task.start) else { continue }
                let fire = start.addingTimeInterval(-Double(max(0, leadMinutes)) * 60)
                guard fire > Date() else { continue }

                let note = UNMutableNotificationContent()
                note.title = task.task
                note.body = task.slot.isEmpty ? "Starting soon" : "Starts at \(task.slot)"
                note.sound = .default

                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(
                    identifier: prefix + task.id,
                    content: note,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                centre.add(request)
            }
        }
    }

    /// "2026-09-24" + "5:00 PM" → a real moment.
    private static func moment(day: String, time: String) -> Date? {
        guard !time.isEmpty else { return nil }
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd h:mm a", "yyyy-MM-dd HH:mm"] {
            reader.dateFormat = format
            if let date = reader.date(from: day + " " + time) { return date }
        }
        return nil
    }
}
