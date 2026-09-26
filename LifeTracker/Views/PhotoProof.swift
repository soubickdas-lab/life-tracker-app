import SwiftUI
#if os(iOS)
import UIKit
import PhotosUI
#else
import AppKit
import UniformTypeIdentifiers
#endif

/// Some journey habits only count once you have shown them — the step counter at
/// the end of the day, the morning picture. The photo is the tick: it goes up, the
/// habit goes green, and the run of them is the thing you look back at.
struct ProofRow: View {
    @Environment(Store.self) private var store
    var journey: Journey
    var habit: JourneyHabit

    @State private var picking = false
    @State private var showing = false
    #if os(iOS)
    @State private var fromLibrary: PhotosPickerItem?
    @State private var camera = false
    #endif

    var body: some View {
        HStack(spacing: 9) {
            tick
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.system(size: 14))
                    .strikethrough(habit.ticked, color: .secondary)
                    .foregroundStyle(habit.due ? (habit.ticked ? .secondary : .primary) : .secondary)
                HStack(spacing: 6) {
                    if habit.every > 1 { Tag(text: "every \(habit.every) days") }
                    if !habit.due { Tag(text: "not today") }
                    if habit.needsPhoto {
                        Tag(text: habit.hasPhoto ? "photo in" : "photo needed",
                            tint: habit.hasPhoto ? UI.mint : UI.violet,
                            strong: true)
                    }
                }
            }
            Spacer(minLength: 0)

            Menu {
                if habit.needsPhoto {
                    if habit.hasPhoto {
                        Button("See the photos") { showing = true }
                        Button("Replace it") { pick() }
                        Button("Remove it", role: .destructive) {
                            Task { await store.dropPhoto(journey: journey.id, habit: habit.name) }
                        }
                    } else {
                        Button("Add today's photo") { pick() }
                    }
                    Divider()
                    Button("Stop asking for a photo") {
                        Task { await store.journeyHabit(journey.id, habit: habit.name, remove: false, photo: false) }
                    }
                } else {
                    Button("Ask for a photo before this ticks") {
                        Task { await store.journeyHabit(journey.id, habit: habit.name, remove: false, photo: true) }
                    }
                }
                Divider()
                Button("Take off this journey", role: .destructive) {
                    Task { await store.journeyHabit(journey.id, habit: habit.name, remove: true) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(habit.ticked ? UI.violet.opacity(0.10) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $showing) {
            PhotoGallery(journey: journey, habit: habit, start: max(0, habit.days.count - 1))
                .environment(store)
        }
        #if os(iOS)
        .photosPicker(isPresented: $picking, selection: $fromLibrary, matching: .images)
        .onChange(of: fromLibrary) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) { send(raw) }
                fromLibrary = nil
            }
        }
        .fullScreenCover(isPresented: $camera) { CameraSheet { send($0) } }
        #endif
    }

    // MARK: - The circle

    @ViewBuilder private var tick: some View {
        if !habit.due {
            Image(systemName: "moon.zzz")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .frame(width: 34, height: 34)
        } else if habit.needsPhoto {
            Button { habit.hasPhoto ? (showing = true) : pick() } label: {
                ZStack {
                    Circle()
                        .strokeBorder(UI.violet.opacity(habit.hasPhoto ? 1 : 0.5), lineWidth: 1.7)
                        .background(Circle().fill(habit.hasPhoto ? UI.violet : Color.primary.opacity(0.001)))
                        .frame(width: 21, height: 21)
                    Image(systemName: habit.hasPhoto ? "checkmark" : "camera.fill")
                        .font(.system(size: habit.hasPhoto ? 11 : 8, weight: .bold))
                        .foregroundStyle(habit.hasPhoto ? .white : UI.violet)
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(habit.hasPhoto ? "Today's photo is in" : "Show it to tick it")
        } else {
            TickCircle(on: habit.done, tint: UI.violet) {
                Task { await store.toggle(journeyHabit: habit.name, on: !habit.done) }
            }
        }
    }

    // MARK: - Getting one in

    private func pick() {
        #if os(iOS)
        if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { picking = true }
        #else
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this photo"
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? Data(contentsOf: url) else { return }
        send(raw)
        #endif
    }

    private func send(_ raw: Data) {
        guard let small = Photo.shrink(raw) else {
            store.errorText = "That file is not a picture."
            return
        }
        Task { await store.sendPhoto(small, journey: journey.id, habit: habit.name) }
    }

}

/// Long side down to 1440 and saved as JPEG, so a year of these is still small.
enum Photo {
    static let longSide: CGFloat = 1440

    static func shrink(_ raw: Data, longSide wanted: CGFloat = longSide) -> Data? {
        #if os(iOS)
        guard let image = UIImage(data: raw) else { return nil }
        let long = max(image.size.width, image.size.height)
        let scale = long > wanted ? wanted / long : 1
        let size = CGSize(width: (image.size.width * scale).rounded(),
                          height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.82)
        #else
        guard let source = NSImage(data: raw),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let long = CGFloat(max(cg.width, cg.height))
        let scale = long > wanted ? wanted / long : 1
        let width = Int((CGFloat(cg.width) * scale).rounded())
        let height = Int((CGFloat(cg.height) * scale).rounded())

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        #endif
    }
}

#if os(iOS)
/// A file waiting to be put somewhere — the share sheet takes it from here.
struct SavedFile: Identifiable {
    var url: URL
    var id: String { url.path }
}

/// The system's own "where should this go" sheet.
struct ShareSheet: UIViewControllerRepresentable {
    var item: SavedFile

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The camera, for the picture you take right now.
struct CameraSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var got: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraSheet
        init(_ parent: CameraSheet) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let raw = image.jpegData(compressionQuality: 1) {
                parent.got(raw)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif

/// Pictures already fetched, kept for as long as the app is open so sliding back
/// through the days is instant. They are small; the whole run is a few megabytes.
@MainActor
final class PhotoStore {
    static let shared = PhotoStore()
    private var held: [String: Data] = [:]

    private func at(_ journey: Int, _ habit: String, _ day: String, _ small: Bool) -> String {
        "\(journey)|\(habit)|\(day)|\(small ? "t" : "f")"
    }

    func have(journey: Int, habit: String, day: String, small: Bool) -> Data? {
        held[at(journey, habit, day, small)]
    }

    func keep(_ data: Data, journey: Int, habit: String, day: String, small: Bool) {
        held[at(journey, habit, day, small)] = data
    }

    /// After a photo changes, the old one must not come back out of here.
    func forget(journey: Int, habit: String) {
        held = held.filter { !$0.key.hasPrefix("\(journey)|\(habit)|") }
    }
}

/// One day's picture, loaded when it comes on screen.
struct Shot: View {
    @Environment(Store.self) private var store
    var journey: Int
    var habit: String
    var day: String
    var small: Bool
    var corner: CGFloat = 10

    @State private var data: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            if let data, let image = picture(data) {
                image.resizable().scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: "\(journey)|\(habit)|\(day)|\(small)") { await fetch() }
    }

    private func fetch() async {
        if let held = PhotoStore.shared.have(journey: journey, habit: habit, day: day, small: small) {
            data = held
            return
        }
        data = nil
        guard let got = await store.photo(journey: journey, habit: habit, day: day, thumb: small) else { return }
        PhotoStore.shared.keep(got, journey: journey, habit: habit, day: day, small: small)
        data = got
    }

    private func picture(_ raw: Data) -> Image? {
        #if os(iOS)
        UIImage(data: raw).map { Image(uiImage: $0) }
        #else
        NSImage(data: raw).map { Image(nsImage: $0) }
        #endif
    }
}

/// One habit's run of days, side by side and newest last — the thing you scroll
/// back through to see the change.
struct PhotoStrip: View {
    @Environment(Store.self) private var store
    var journey: Journey
    var habit: JourneyHabit

    @State private var opening: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(habit.name).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(habit.days.count) \(habit.days.count == 1 ? "day" : "days")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if habit.days.isEmpty {
                Text("nothing yet").font(.system(size: 12)).foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { rail in
                        HStack(spacing: 8) {
                            ForEach(Array(habit.days.enumerated()), id: \.element) { index, day in
                                Button { opening = index } label: {
                                    ZStack(alignment: .bottom) {
                                        Shot(journey: journey.id, habit: habit.name, day: day, small: true)
                                            .frame(width: 74, height: 98)
                                        Text(short(day))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 3)
                                            .background(.black.opacity(0.45))
                                    }
                                    .frame(width: 74, height: 98)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .padding(.vertical, 1)
                        .onAppear { rail.scrollTo(habit.days.count - 1, anchor: .trailing) }
                    }
                }
            }
        }
        .sheet(item: Binding(get: { opening.map { Opening(index: $0) } },
                             set: { opening = $0?.index })) { spot in
            PhotoGallery(journey: journey, habit: habit, start: spot.index)
                .environment(store)
        }
    }

    private func short(_ day: String) -> String {
        let take = DateFormatter(); take.dateFormat = "yyyy-MM-dd"
        guard let date = take.date(from: day) else { return day }
        let show = DateFormatter(); show.dateFormat = "d MMM"
        return show.string(from: date)
    }
}

private struct Opening: Identifiable {
    var index: Int
    var id: Int { index }
}

/// The run, full size, one day at a time — swipe on the phone, arrow keys on the Mac.
struct PhotoGallery: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var journey: Journey
    var habit: JourneyHabit
    var start: Int

    @State private var at = 0

    private var days: [String] { habit.days }

    var body: some View {
        VStack(spacing: 12) {
            if days.isEmpty {
                EmptyHint(icon: "photo", text: "No photos on this one yet.")
            } else {
                #if os(iOS)
                TabView(selection: $at) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        Shot(journey: journey.id, habit: habit.name, day: day, small: false, corner: 14)
                            .aspectRatio(contentMode: .fit)
                            .padding(.horizontal, 8)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                #else
                HStack(spacing: 10) {
                    arrow("chevron.left", by: -1)
                    Shot(journey: journey.id, habit: habit.name,
                         day: days[min(at, days.count - 1)], small: false, corner: 14)
                        .frame(maxWidth: 560, maxHeight: 480)
                    arrow("chevron.right", by: 1)
                }
                #endif

                Text("\(habit.name) · \(pretty(days[min(at, days.count - 1)])) · \(at + 1) of \(days.count)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack {
                if !days.isEmpty {
                    Button("Remove this one", role: .destructive) {
                        let day = days[min(at, days.count - 1)]
                        dismiss()
                        Task { await store.dropPhoto(journey: journey.id, habit: habit.name, day: day) }
                    }
                    .font(.system(size: 12))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 440)
        #endif
        .onAppear { at = min(max(0, start), max(0, days.count - 1)) }
    }

    #if os(macOS)
    private func arrow(_ icon: String, by step: Int) -> some View {
        Button { at = (at + step + days.count) % max(1, days.count) } label: {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(step < 0 ? .leftArrow : .rightArrow, modifiers: [])
        .disabled(days.count < 2)
    }
    #endif

    private func pretty(_ day: String) -> String {
        let take = DateFormatter(); take.dateFormat = "yyyy-MM-dd"
        guard let date = take.date(from: day) else { return day }
        let show = DateFormatter(); show.dateFormat = "d MMM"
        return show.string(from: date)
    }
}
