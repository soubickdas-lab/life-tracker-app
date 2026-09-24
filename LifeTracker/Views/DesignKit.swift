import SwiftUI

/// The look of the app: soft surfaces, one accent, generous spacing.
/// No grid lines, no banners — rows breathe and the type carries the hierarchy.
enum UI {
    static let accent = Color(red: 0.36, green: 0.42, blue: 0.95)
    static let mint   = Color(red: 0.20, green: 0.72, blue: 0.51)
    static let amber  = Color(red: 0.96, green: 0.68, blue: 0.24)
    static let rose   = Color(red: 0.93, green: 0.35, blue: 0.45)
    static let violet = Color(red: 0.55, green: 0.40, blue: 0.93)
    static let sky    = Color(red: 0.22, green: 0.60, blue: 0.95)

    static let radius: CGFloat = 16
    #if os(macOS)
    static let rowHeight: CGFloat = 46
    #else
    static let rowHeight: CGFloat = 58
    #endif

    #if os(macOS)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let canvas  = Color(nsColor: .underPageBackgroundColor)
    #else
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas  = Color(uiColor: .systemGroupedBackground)
    #endif

    static let hairline = Color.primary.opacity(0.055)

    #if os(macOS)
    static let gutter: CGFloat = 22
    #else
    static let gutter: CGFloat = 16
    #endif
}

/// A soft panel. Everything on a screen sits in one of these.
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UI.surface, in: RoundedRectangle(cornerRadius: UI.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                    .stroke(UI.hairline, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.035), radius: 9, y: 3)
    }
}

/// Screen title with its subtitle, used at the top of every page.
struct PageTitle: View {
    var title: String
    var subtitle: String?
    var trailing: AnyView?

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> some View = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

/// Small rounded label for times, streaks and counts.
struct Tag: View {
    var text: String
    var tint: Color = .secondary
    var strong: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(strong ? 0.18 : 0.10), in: Capsule())
            .foregroundStyle(strong ? tint : .secondary)
    }
}

/// The tick circle on a task row.
struct TickCircle: View {
    var on: Bool
    var tint: Color = UI.mint
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(on ? tint : Color.secondary.opacity(0.32), lineWidth: 1.7)
                    .background(Circle().fill(on ? tint : Color.primary.opacity(0.001)))
                    .frame(width: 21, height: 21)
                    .shadow(color: on ? tint.opacity(0.35) : .clear, radius: 5, y: 1)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)          /* a comfortable target, not a 21pt dot */
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: on)
    }
}

/// Ring used for the day's progress.
struct Ring: View {
    var progress: Double
    var size: CGFloat = 52
    var width: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(progress >= 1 ? UI.mint : UI.accent,
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            Text("\(Int(progress * 100))")
                .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

/// One number on the dashboard.
struct StatTile: View {
    var label: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Thin line between rows, inset so it never touches the panel edge.
struct RowLine: View {
    var leading: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(UI.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

/// Shown when a list has nothing in it yet.
struct EmptyHint: View {
    var icon: String
    var text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

/// Every page shares this frame: centred column, calm background.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(UI.gutter)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(UI.canvas)
        .overlay(alignment: .top) { StatusStrip() }
    }
}

/// The one line that tells you where a change is: on screen already, being saved,
/// or refused. Sits at the top of every page, so no screen has to say it itself.
struct StatusStrip: View {
    @Environment(Store.self) private var store

    var body: some View {
        Group {
            if let text = store.toast ?? store.errorText {
                pill(text, tint: store.errorText == nil ? UI.accent : UI.rose, working: false)
                    .onTapGesture { store.toast = nil; store.errorText = nil }
            } else if store.busy {
                pill("Updating…", tint: UI.accent, working: true)
            }
        }
        .padding(.top, 10)
        .animation(.snappy(duration: 0.2), value: store.busy)
        .animation(.snappy(duration: 0.2), value: store.toast)
        .animation(.snappy(duration: 0.2), value: store.errorText)
    }

    private func pill(_ text: String, tint: Color, working: Bool) -> some View {
        HStack(spacing: 7) {
            if working {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint, in: Capsule())
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.16), radius: 9, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
