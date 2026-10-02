import SwiftUI
import WidgetKit

/// Life Tracker on the home and lock screens. It shows the picture the app left
/// behind, and refreshes itself from the server so it stays right even on a day
/// the app has not been opened.
@main
struct LifeTrackerWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LifeTrackerToday", provider: Feed()) { entry in
            TodayFace(snap: entry.snap)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What is left today, and the journey you are on.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

// MARK: - Where the numbers come from

struct Entry: TimelineEntry {
    var date: Date
    var snap: Shared.Snapshot
}

struct Feed: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snap: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snap: Shared.load() ?? sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let fresh = await Live.fetch() ?? Shared.load() ?? sample
            /* often enough to stay honest, rarely enough that iOS keeps serving it */
            let again = Calendar.current.date(byAdding: .minute, value: 20, to: .now) ?? .now
            completion(Timeline(entries: [Entry(date: .now, snap: fresh)], policy: .after(again)))
        }
    }

    private var sample: Shared.Snapshot {
        var snap = Shared.Snapshot()
        snap.pretty = "Today"
        snap.done = 2
        snap.total = 6
        snap.lines = [
            .init(text: "Gym", slot: "4:00 PM"),
            .init(text: "Upload on all channels", slot: ""),
            .init(text: "Call mom", slot: ""),
        ]
        snap.habitsDone = 5
        snap.habitsTotal = 11
        snap.journey = "Fat loss"
        snap.journeyLeft = 93
        snap.journeyDue = 3
        return snap
    }
}

// MARK: - The faces

struct TodayFace: View {
    @Environment(\.widgetFamily) private var family
    var snap: Shared.Snapshot

    var body: some View {
        switch family {
        case .accessoryInline:    inline
        case .accessoryCircular:  circular
        case .accessoryRectangular: rectangular
        case .systemSmall:        small
        default:                  medium
        }
    }

    // lock screen

    private var inline: some View {
        Text(snap.left == 0 ? "All clear today" : "\(snap.left) left · \(snap.habitsDone)/\(snap.habitsTotal) habits")
    }

    private var circular: some View {
        Gauge(value: snap.share) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(snap.left)")
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snap.left == 0 ? "All clear" : "\(snap.left) left today")
                .font(.headline)
            if let first = snap.lines.first {
                Text(first.slot.isEmpty ? first.text : "\(first.text) · \(first.slot)")
                    .font(.caption)
                    .lineLimit(1)
            }
            if snap.hasJourney {
                Text("\(snap.journey) · \(snap.journeyLeft)d · \(snap.journeyDone)/\(snap.journeyDue)")
                    .font(.caption2)
                    .lineLimit(1)
            } else {
                Text("\(snap.habitsDone)/\(snap.habitsTotal) habits").font(.caption2)
            }
        }
        .widgetURL(URL(string: "lifetracker://today"))
    }

    // home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Ring(share: snap.share, left: snap.left, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Today").font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("\(snap.habitsDone)/\(snap.habitsTotal) habits")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(snap.lines.prefix(3)) { line in
                    Text("· " + line.text)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                if snap.lines.isEmpty {
                    Text("Nothing left — nice.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if snap.hasJourney { journeyLine }
        }
        .widgetURL(URL(string: "lifetracker://today"))
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Ring(share: snap.share, left: snap.left, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Today").font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(snap.pretty.isEmpty ? "\(snap.done)/\(snap.total) done" : snap.pretty)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text("\(snap.habitsDone)/\(snap.habitsTotal) habits")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if snap.hasJourney { journeyLine }
            }
            .frame(width: 118, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                if snap.lines.isEmpty {
                    Text("Nothing left today.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(snap.lines.prefix(5)) { line in
                        HStack(spacing: 6) {
                            Circle().stroke(.secondary.opacity(0.5), lineWidth: 1.2)
                                .frame(width: 9, height: 9)
                            Text(line.text).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 4)
                            if !line.slot.isEmpty {
                                Text(line.slot)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "lifetracker://today"))
    }

    private var journeyLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.checkered").font(.system(size: 8))
            Text("\(snap.journeyLeft)d · \(snap.journeyDone)/\(snap.journeyDue)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.tint)
        .lineLimit(1)
    }
}

/// The day's progress, with what is left in the middle.
struct Ring: View {
    var share: Double
    var left: Int
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.25), lineWidth: size * 0.12)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, share)))
                .stroke(.tint, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(left)")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
    }
}
