import SwiftUI

/// The ⚙️ Setup tab in full: settings, the habit list, categories — plus the 🧾 Log.
struct SetupScreen: View {
    @Environment(Store.self) private var store
    @State private var drafts: [String: String] = [:]
    @State private var newHabit = ""
    @State private var newCategory = ""
    @State private var showSecrets = false
    @State private var showLog = false

    var body: some View {
        Page {
            PageTitle("Setup", subtitle: "Everything the sheet's ⚙️ tab holds")
            settings
            habits
            categories
        }
        .refreshable { await store.refresh(quietly: true) }
    }

    // MARK: - Settings

    private var settings: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Settings").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Toggle("Show keys", isOn: $showSecrets)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption)
                }

                ForEach(store.extra.setup) { item in
                    if item.isBool {
                        Toggle(item.name, isOn: Binding(
                            get: { item.boolValue },
                            set: { on in Task { await store.setSetting(item.name, on ? "true" : "false") } }))
                            .toggleStyle(.switch)
                    } else if item.isSecret && !showSecrets {
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(item.value.isEmpty ? "—" : "••••••••")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        #if os(macOS)
                        HStack {
                            Text(item.name)
                                .frame(minWidth: 180, alignment: .leading)
                            settingField(item)
                        }
                        #else
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            HStack { settingField(item) }
                        }
                        #endif
                    }
                    if item.id != store.extra.setup.last?.id { Divider() }
                }
            }
        }
    }

    @ViewBuilder private func settingField(_ item: SetupItem) -> some View {
        TextField("", text: Binding(
            get: { drafts[item.name] ?? item.value },
            set: { drafts[item.name] = $0 }))
            .textFieldStyle(.roundedBorder)
            .onSubmit { commit(item) }
        if (drafts[item.name] ?? item.value) != item.value {
            Button("Save") { commit(item) }
        }
    }

    private func commit(_ item: SetupItem) {
        let value = drafts[item.name] ?? item.value
        drafts[item.name] = nil
        Task { await store.setSetting(item.name, value) }
    }

    // MARK: - Habits

    private var habits: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Habits").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    TextField("New habit", text: $newHabit)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit(addHabit)
                    Button("Add", action: addHabit)
                        .disabled(newHabit.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ForEach(store.extra.habitCfg) { habit in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { habit.active },
                            set: { on in
                                Task { await store.saveHabit(slot: habit.slot, name: habit.name,
                                                             target: habit.target, active: on) }
                            }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Text(habit.name)
                            .foregroundStyle(habit.active ? .primary : .secondary)
                        Spacer()
                        TextField("target", text: Binding(
                            get: { drafts["h\(habit.slot)"] ?? habit.target },
                            set: { drafts["h\(habit.slot)"] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onSubmit {
                                let target = drafts["h\(habit.slot)"] ?? habit.target
                                drafts["h\(habit.slot)"] = nil
                                Task { await store.saveHabit(slot: habit.slot, name: habit.name,
                                                             target: target, active: habit.active) }
                            }
                        Button {
                            Task { await store.saveHabit(slot: habit.slot, name: habit.name,
                                                         target: habit.target, active: false, remove: true) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func addHabit() {
        let name = newHabit.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newHabit = ""
        Task { await store.saveHabit(slot: 0, name: name, target: "", active: true) }
    }

    // MARK: - Categories

    private var categories: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Categories").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    TextField("New category", text: $newCategory)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit(addCategory)
                    Button("Add", action: addCategory)
                        .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(store.extra.categories, id: \.self) { name in
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.callout)
                            Spacer(minLength: 0)
                            Button {
                                Task { await store.category(name, remove: true) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private func addCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newCategory = ""
        Task { await store.category(name, remove: false) }
    }

}
