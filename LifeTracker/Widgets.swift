#if os(iOS)
import WidgetKit

/// Tells the home and lock screens that the day has moved on.
enum Widgets {
    static func nudge() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
