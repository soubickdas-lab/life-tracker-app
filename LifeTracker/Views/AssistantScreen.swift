import SwiftUI

/// Say what you want in plain words — "500 food pe gaya", "kal 6 baje gym daal de",
/// "is mahine kitna kharcha hua?" — and it is done or answered. It works through
/// the same calls the buttons make, so everything it changes shows up everywhere.
struct AssistantScreen: View {
    @Environment(Store.self) private var store
    var onClose: (() -> Void)?
    @State private var draft = ""
    @State private var voice = VoiceNote()
    @FocusState private var typing: Bool

    /// The starts of the things said most. A tap puts one in the box, ready to finish.
    private let shortcuts: [(label: String, icon: String, text: String)] = [
        ("Add task", "plus.circle", "Add task: "),
        ("Tomorrow", "arrow.right.circle", "Tomorrow: "),
        ("Spent", "arrow.up.right", "Spent: "),
        ("Received", "arrow.down.left", "Received: "),
        ("Tick habit", "flame", "Tick habit: "),
        ("Weight", "scalemass", "Weight: "),
        ("Note", "note.text", "Note: "),
    ]

    private let ideas = [
        "Aaj kya kya bacha hai?",
        "200 chai nashta pe kharch hua",
        "Kal subah 7 baje run add kar de",
        "Is mahine kitna kharcha hua aur kahan?",
        "Water 3L tick kar de",
        "Aaj ka weight 80.4 likh de",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.chat.isEmpty { welcome }
                        ForEach(store.chat) { line in bubble(line).id(line.id) }
                        if store.thinking { thinkingRow.id("thinking") }
                    }
                    .padding(UI.gutter)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: store.chat.count) { _, _ in
                    withAnimation(.snappy(duration: 0.2)) {
                        if let last = store.chat.last { reader.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: store.thinking) { _, now in
                    if now { withAnimation { reader.scrollTo("thinking", anchor: .bottom) } }
                }
            }

            Divider()
            composer
        }
        .background(UI.canvas)
        .onAppear { typing = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.violet)
            Text("Assistant").font(.system(size: 15, weight: .semibold))
            Spacer()
            if !store.chat.isEmpty {
                Button { store.clearChat() } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Start over")
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Before anything is said

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tell it what to do, or ask what you want to know. Try one:")
                .font(.system(size: 13)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(ideas, id: \.self) { idea in
                    Button { fill(idea) } label: {
                        HStack {
                            Text(idea).font(.system(size: 13))
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(UI.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(UI.hairline, lineWidth: 0.8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - The talk

    private func bubble(_ line: Store.ChatLine) -> some View {
        HStack {
            if line.mine { Spacer(minLength: 50) }
            Text(line.text)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .foregroundStyle(line.mine ? .white : (line.failed ? UI.rose : .primary))
                .background(line.mine ? UI.accent : UI.surface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if !line.mine {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(line.failed ? UI.rose.opacity(0.35) : UI.hairline, lineWidth: 0.8)
                    }
                }
            if !line.mine { Spacer(minLength: 50) }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("thinking…").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Saying something

    private var composer: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(shortcuts, id: \.label) { shortcut in
                        Button { fill(shortcut.text) } label: {
                            Label(shortcut.label, systemImage: shortcut.icon)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(UI.accent.opacity(0.10), in: Capsule())
                                .foregroundStyle(UI.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, UI.gutter)
            }

            if let problem = voice.problem {
                Text(problem)
                    .font(.system(size: 11)).foregroundStyle(UI.rose)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, UI.gutter)
            }

            inputRow
        }
        .padding(.vertical, 10)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(UI.canvas)
        .onChange(of: voice.seconds) { _, now in
            if now >= VoiceNote.limit { sendVoice() }        /* long enough — off it goes */
        }
        .onDisappear { voice.cancel() }
    }

    @ViewBuilder private var inputRow: some View {
        if voice.recording {
            recordingRow
        } else {
            typingRow
        }
    }

    private var typingRow: some View {
        HStack(spacing: 10) {
            TextField("Type, or tap the mic and speak…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .focused($typing)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button { voice.start() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(UI.accent)
                    .frame(width: 38, height: 38)
                    .background(UI.accent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.thinking)
            .help("Tap to record a voice message")

            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(canSend ? UI.accent : Color.secondary.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, UI.gutter)
    }

    /// While it listens: a red dot, the time, a way out, and one big button to send.
    private var recordingRow: some View {
        HStack(spacing: 12) {
            Button { voice.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Throw this recording away")

            HStack(spacing: 9) {
                Circle().fill(UI.rose).frame(width: 9, height: 9)
                    .opacity(voice.seconds % 2 == 0 ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.6), value: voice.seconds)
                Text("Recording  \(voice.seconds / 60):\(String(format: "%02d", voice.seconds % 60))")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("bolo… phir bhejo")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(UI.rose.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button { sendVoice() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(UI.rose, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop and send")
        }
        .padding(.horizontal, UI.gutter)
    }

    private func sendVoice() {
        guard let sound = voice.finish() else {
            voice.cancel()
            return
        }
        Task { await store.ask(voice: sound) }
    }

    /// Puts a start in the box — replacing any other start already there — and
    /// leaves the cursor after it.
    private func fill(_ text: String) {
        var rest = draft
        for shortcut in shortcuts where rest.hasPrefix(shortcut.text) {
            rest = String(rest.dropFirst(shortcut.text.count))
        }
        draft = text.hasSuffix(": ") ? text + rest : text
        typing = true
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.thinking
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !store.thinking else { return }
        voice.cancel()
        draft = ""
        Task { await store.ask(clean) }
    }
}
