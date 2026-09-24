import Foundation

/// The sheet's own tab bar, in the same order — one sidebar row per tab.
enum Pane: String, CaseIterable, Identifiable, Sendable {
    case today, tomorrow, yesterday
    case habits, dash, scheduled, longTerm, body, notes, setup, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:     return "Today"
        case .tomorrow:  return "Tomorrow"
        case .yesterday: return "Yesterday"
        case .habits:    return "Habits"
        case .dash:      return "Dashboard"
        case .scheduled: return "Scheduled"
        case .longTerm:  return "Long Term"
        case .body:      return "Body"
        case .notes:     return "Notes"
        case .setup:     return "Setup"
        case .log:       return "Log"
        }
    }

    var icon: String {
        switch self {
        case .today:     return "checkmark.circle"
        case .tomorrow:  return "arrow.right.circle"
        case .yesterday: return "arrow.left.circle"
        case .habits:    return "flame"
        case .dash:      return "chart.bar"
        case .scheduled: return "calendar"
        case .longTerm:  return "target"
        case .body:      return "figure.walk"
        case .notes:     return "note.text"
        case .setup:     return "gearshape"
        case .log:       return "clock.arrow.circlepath"
        }
    }

    /// The three day tabs map onto the day blocks the sheet sends.
    var dayLabel: String? {
        switch self {
        case .today:     return "Today"
        case .tomorrow:  return "Tomorrow"
        case .yesterday: return "Yesterday"
        default:         return nil
        }
    }
}
