import SwiftUI

/// Where the web app link and its key live. Both stay on this device.
/// Paste the whole link from the sheet's "🎙 Siri / Shortcuts setup" and it splits itself.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to your sheet")
                .font(.title3.weight(.semibold))

            Text("In the sheet: menu 🧭 Life Tracker ▸ 🎙 Siri / Shortcuts setup. Copy the whole link it shows — it already has the key in it — then press Paste.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                pasteEverything()
            } label: {
                Label("Paste link (and key) from clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Web app link").font(.callout).foregroundStyle(.secondary)
                TextField("https://script.google.com/macros/s/…/exec", text: $store.endpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.footnote, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Key").font(.callout).foregroundStyle(.secondary)
                SecureField("the key from that same dialog", text: $store.key)
                    .textFieldStyle(.roundedBorder)
            }

            if let result {
                Text(result)
                    .font(.callout)
                    .foregroundStyle(result.hasPrefix("✅") ? UI.mint : .red)
            }

            HStack {
                if let last = store.lastSync {
                    Text("Last synced \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(testing ? "Testing…" : "Test") { test() }
                    .disabled(!store.isConfigured || testing)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 460)
        #endif
    }

    /// Takes whatever the sheet's "🎙 Siri / Shortcuts setup" box holds — the URL line,
    /// the "key = …" line, both at once, or a link with ?key= on the end.
    private func pasteEverything() {
        #if os(macOS)
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        #else
        let text = UIPasteboard.general.string ?? ""
        #endif
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { result = "Clipboard is empty"; return }

        var foundLink = false
        var foundKey = false

        // the /exec link, wherever it sits in the pasted text
        if let range = clean.range(of: "https://script\\.google\\.com/\\S*?/exec", options: .regularExpression) {
            let link = String(clean[range])
            if var parts = URLComponents(string: link) {
                if let key = parts.queryItems?.first(where: { $0.name == "key" })?.value, !key.isEmpty {
                    store.key = key
                    foundKey = true
                }
                parts.query = nil
                store.endpoint = parts.url?.absoluteString ?? link
            } else {
                store.endpoint = link
            }
            foundLink = true
        }

        // a "key = 0ff2…" line, or a bare key on its own
        if !foundKey {
            if let range = clean.range(of: "(?i)key\\s*[=:]\\s*([A-Za-z0-9_-]{8,})", options: .regularExpression) {
                let line = String(clean[range])
                if let value = line.split(whereSeparator: { $0 == "=" || $0 == ":" }).last {
                    store.key = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    foundKey = true
                }
            } else if clean.range(of: "^[A-Za-z0-9_-]{16,}$", options: .regularExpression) != nil {
                store.key = clean
                foundKey = true
            }
        }

        switch (foundLink, foundKey) {
        case (true, true):   result = "✅ Link and key saved"
        case (false, true):  result = "✅ Key saved"
        case (true, false):  result = "Link saved — now copy the key line too"
        default:             result = "That clipboard had no link or key in it"
        }
        if store.isConfigured { test() }
    }

    private func test() {
        testing = true
        result = nil
        Task {
            await store.refresh()
            testing = false
            if let error = store.errorText {
                result = error
            } else {
                let count = store.state.todayBlock?.tasks.count ?? 0
                result = "✅ Connected — \(count) tasks today, \(store.state.habits.count) habits"
            }
        }
    }
}
