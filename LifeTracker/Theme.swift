import SwiftUI

/// Small shared bits of look and feel, so every screen matches.
enum Theme {
    static let corner: CGFloat = 16
    static let amber = Color(red: 0.90, green: 0.60, blue: 0.10)
    static let green = Color(red: 0.18, green: 0.68, blue: 0.40)
    static let teal  = Color(red: 0.12, green: 0.60, blue: 0.62)

    #if os(macOS)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let page = Color(nsColor: .windowBackgroundColor)
    #else
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let page = Color(uiColor: .systemGroupedBackground)
    #endif
}

/// A rounded panel used for every block on the page.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// The ring on the header that fills up as the day gets done.
struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(progress >= 1 ? Theme.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            Text("\(Int(progress * 100))%")
                .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

/// Little rounded label — used for times, streaks and 🔁.
struct Chip: View {
    var text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}
