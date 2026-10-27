import Foundation

/// The app's places. Three you live in — Today, the journey and Later — and the
/// rest, which you visit now and then, tucked under More.
enum Pane: String, CaseIterable, Identifiable, Sendable {
    case today, journey, later
    case habits, scheduled, dash, body, setup, log

    var id: String { rawValue }

    /// The ones that get a tab of their own.
    static let main: [Pane] = [.today, .journey, .later]
    /// The ones under More.
    static let rest: [Pane] = [.habits, .scheduled, .dash, .body, .setup, .log]

    var title: String {
        switch self {
        case .today:     return "Today"
        case .journey:   return "Journey"
        case .later:     return "Later"
        case .habits:    return "Habits"
        case .scheduled: return "Scheduled"
        case .dash:      return "Dashboard"
        case .body:      return "Body"
        case .setup:     return "Setup"
        case .log:       return "Log"
        }
    }

    var icon: String {
        switch self {
        case .today:     return "checkmark.circle"
        case .journey:   return "flame"
        case .later:     return "tray.full"
        case .habits:    return "repeat"
        case .scheduled: return "calendar"
        case .dash:      return "chart.bar"
        case .body:      return "figure.walk"
        case .setup:     return "gearshape"
        case .log:       return "clock.arrow.circlepath"
        }
    }
}
