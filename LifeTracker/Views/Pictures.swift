import SwiftUI
#if os(iOS)
import UIKit
import PhotosUI
#else
import AppKit
import UniformTypeIdentifiers
#endif

/// A button that ends in a picture: from the photo library on the phone, from a
/// file or straight off the clipboard on the Mac (where a screenshot usually is).
struct PictureButton<Label: View>: View {
    var onPick: (Data) -> Void
    @ViewBuilder var label: Label

    #if os(iOS)
    @State private var picked: PhotosPickerItem?
    #endif

    var body: some View {
        #if os(iOS)
        PhotosPicker(selection: $picked, matching: .images) { label }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let raw = try? await item.loadTransferable(type: Data.self) { onPick(raw) }
                    picked = nil
                }
            }
        #else
        Menu {
            Button("Choose a file…") { choose() }
            Button("Paste from clipboard") { paste() }
                .disabled(!NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil))
        } label: { label }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    #if os(macOS)
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this picture"
        guard panel.runModal() == .OK, let url = panel.url, let raw = try? Data(contentsOf: url) else { return }
        onPick(raw)
    }

    private func paste() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let tiff = image.tiffRepresentation else { return }
        onPick(tiff)
    }
    #endif
}

/// Pictures already fetched, kept while the app is open.
@MainActor
enum PictureShelf {
    private static var held: [String: Data] = [:]
    static func have(_ key: String) -> Data? { held[key] }
    static func keep(_ data: Data, _ key: String) { held[key] = data }
    static func forget(_ id: Int) { held = held.filter { !$0.key.hasPrefix("plan-\(id)-") } }
}

func pictureView(_ data: Data) -> Image? {
    #if os(iOS)
    UIImage(data: data).map { Image(uiImage: $0) }
    #else
    NSImage(data: data).map { Image(nsImage: $0) }
    #endif
}

/// One picture belonging to a plan, loaded when it comes on screen.
struct PlanShot: View {
    @Environment(Store.self) private var store
    var id: Int
    var small: Bool
    var fill = true

    @State private var data: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05))
            if let data, let image = pictureView(data) {
                image.resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .task(id: "\(id)-\(small)") {
            let key = "plan-\(id)-\(small ? "t" : "f")"
            if let held = PictureShelf.have(key) { data = held; return }
            guard let got = await store.planPicture(id: id, thumb: small) else { return }
            PictureShelf.keep(got, key)
            data = got
        }
    }
}

/// The pictures kept with a plan: a strip to look along, and a way to add another.
struct PlanPictures: View {
    @Environment(Store.self) private var store
    var goal: Goal

    @State private var opened: PictureRef?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(goal.images, id: \.self) { id in
                    Button { opened = PictureRef(id: id) } label: {
                        PlanShot(id: id, small: true).frame(width: 64, height: 64)
                    }
                    .buttonStyle(.plain)
                }
                PictureButton(onPick: { raw in Task { await store.addPlanPicture(raw, to: goal) } }) {
                    VStack(spacing: 3) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 15))
                        Text(goal.images.isEmpty ? "Add picture" : "Add").font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(UI.accent)
                    .frame(width: goal.images.isEmpty ? 84 : 64, height: 64)
                    .background(UI.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 1)
        }
        .sheet(item: $opened) { ref in
            VStack(spacing: 12) {
                PlanShot(id: ref.id, small: false, fill: false)
                    .frame(maxWidth: 760, maxHeight: 560)
                Text(goal.goal).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button("Remove this picture", role: .destructive) {
                        opened = nil
                        PictureShelf.forget(ref.id)
                        Task { await store.dropPlanPicture(id: ref.id) }
                    }
                    .font(.system(size: 12))
                    Spacer()
                    Button("Done") { opened = nil }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 460)
            #endif
        }
    }
}

struct PictureRef: Identifiable {
    var id: Int
}
