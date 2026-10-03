import SwiftUI

/// Say what you want in plain words — "500 food pe gaya", "kal 6 baje gym daal de",
/// "is mahine kitna kharcha hua?" — and it is done or answered. It works through
/// the same calls the buttons make, so everything it changes shows up everywhere.
struct AssistantScreen: View {
    @Environment(Store.self) private var store
    @State private var draft = ""
    @FocusState private var typing: Bool

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
        .toolbar {
            if !store.chat.isEmpty {
                ToolbarItem {
                    Button { store.clearChat() } label: { Image(systemName: "trash") }
                        .help("Start over")
                }
            }
        }
    }

    // MARK: - Before anything is said

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(UI.violet)
                    .frame(width: 44, height: 44)
                    .background(UI.violet.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Assistant")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Tell it what to do, or ask what you want to know.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(ideas, id: \.self) { idea in
                    Button { send(idea) } label: {
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
        HStack(spacing: 10) {
            TextField("Ask, or tell it what to do…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .focused($typing)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))

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
        .padding(.vertical, 10)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(UI.canvas)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.thinking
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !store.thinking else { return }
        draft = ""
        Task { await store.ask(clean) }
    }
}
