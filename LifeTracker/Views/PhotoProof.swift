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
    @State private var shown: Data?
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
                        Button("See today's photo") { look() }
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
        .sheet(isPresented: $showing) { viewer }
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
            Button { habit.hasPhoto ? look() : pick() } label: {
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

    // MARK: - Looking at it

    private var viewer: some View {
        VStack(spacing: 14) {
            if let shown, let image = platformImage(shown) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 620, maxHeight: 620)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ProgressView().frame(height: 220)
            }
            Text("\(habit.name) · today")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("Replace") { showing = false; pick() }
                Spacer()
                Button("Done") { showing = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 420)
        #endif
    }

    private func look() {
        shown = nil
        showing = true
        Task { shown = await store.photo(journey: journey.id, habit: habit.name) }
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

    private func platformImage(_ data: Data) -> Image? {
        #if os(iOS)
        UIImage(data: data).map { Image(uiImage: $0) }
        #else
        NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }
}

/// Long side down to 1440 and saved as JPEG, so a year of these is still small.
enum Photo {
    static let longSide: CGFloat = 1440

    static func shrink(_ raw: Data) -> Data? {
        #if os(iOS)
        guard let image = UIImage(data: raw) else { return nil }
        let long = max(image.size.width, image.size.height)
        let scale = long > longSide ? longSide / long : 1
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
        let scale = long > longSide ? longSide / long : 1
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
