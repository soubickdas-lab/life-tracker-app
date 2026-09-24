import SwiftUI

@main
struct LifeTrackerApp: App {
    @State private var store = Store()

    /// The sheet's "Connect the app" button opens lifetracker://connect?url=…&key=…
    /// so the link and key arrive with one click instead of being typed.
    private func connect(from url: URL) {
        guard url.scheme == "lifetracker",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = parts.queryItems ?? []
        if let link = items.first(where: { $0.name == "url" })?.value, !link.isEmpty {
            store.endpoint = link
        }
        if let key = items.first(where: { $0.name == "key" })?.value, !key.isEmpty {
            store.key = key
        }
        if store.isConfigured {
            Task { await store.refresh() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { url in connect(from: url) }
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 800)
        .commands {
            CommandGroup(after: .toolbar) {
                ForEach(Array(Pane.allCases.enumerated()), id: \.element) { index, pane in
                    Button(pane.title) { store.pane = pane }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}

/// Tabs on the phone, one window with a toolbar on the Mac.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    #if os(iOS)
    @AppStorage("phoneTab") private var phoneTab = 0   /* reopen where you left off */
    #endif

    var body: some View {
        content
            .task {
                if store.isConfigured {
                    await store.refresh()
                    Notifier.askOnce()          /* only once there is something to remind about */
                } else {
                    showSettings = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.cameToFront() } else { store.wentAway() }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: showSettings) { _, open in
                if !open, store.isConfigured { Task { await store.refresh() } }
            }
            .onChange(of: store.key) { _, _ in
                if store.isConfigured {
                    Task { await store.refresh(); Notifier.askOnce() }
                }
            }
            .overlay { if !store.isConfigured { connectCover } }
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
        TabView(selection: $phoneTab) {
            wrap(DayScreen(label: "Today"), "Today")
                .tabItem { Label("Today", systemImage: "checkmark.circle") }
                .tag(0)
            wrap(DayScreen(label: "Tomorrow"), "Tomorrow")
                .tabItem { Label("Tomorrow", systemImage: "arrow.right.circle") }
                .tag(1)
            wrap(HabitsScreen(), "Habits")
                .tabItem { Label("Habits", systemImage: "flame") }
                .tag(2)
            wrap(ScheduledScreen(), "Scheduled")
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(3)
            moreTab
                .tabItem { Label("More", systemImage: "square.grid.2x2") }
                .tag(4)
        }
        #else
        NavigationSplitView {
            List(Pane.allCases, selection: Binding<Pane?>(
                get: { store.pane },
                set: { store.pane = $0 ?? .today })) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            NavigationStack {
                paneView
                    .navigationTitle(store.pane.title)
                    .toolbar {
                        ToolbarItem {
                            Button { Task { await store.refresh() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Refresh from the sheet")
                        }
                        settingsButton
                    }
            }
        }
        #endif
    }

    /// Every screen the sheet has, on both platforms.
    @ViewBuilder private func paneScreen(_ pane: Pane) -> some View {
        switch pane {
        case .today, .tomorrow, .yesterday:
            DayScreen(label: pane.dayLabel ?? "Today")
        case .habits:    HabitsScreen()
        case .dash:      DashboardScreen()
        case .scheduled: ScheduledScreen()
        case .longTerm:  GoalsScreen()
        case .body:      BodyScreen()
        case .notes:     NotesScreen()
        case .setup:     SetupScreen()
        case .log:       LogScreen()
        }
    }

    #if os(iOS)
    private func wrap(_ view: some View, _ title: String) -> some View {
        NavigationStack {
            view
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { settingsButton }
        }
    }

    /// The rest of the sheet, so nothing on the phone is out of reach.
    private var moreTab: some View {
        NavigationStack {
            List {
                Section("Days") { pageLink(.yesterday) }
                Section("Tracking") {
                    pageLink(.dash)
                    pageLink(.longTerm)
                    pageLink(.body)
                    pageLink(.notes)
                }
                Section("The sheet") {
                    pageLink(.setup)
                    pageLink(.log)
                }
            }
            .navigationTitle("More")
            .toolbar { settingsButton }
        }
    }

    private func pageLink(_ pane: Pane) -> some View {
        NavigationLink {
            paneScreen(pane)
                .navigationTitle(pane.title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            Label(pane.title, systemImage: pane.icon)
        }
    }
    #else
    @ViewBuilder private var paneView: some View { paneScreen(store.pane) }
    #endif

    /// Nothing can load without the link and key — say so plainly instead of showing an empty grid.
    private var connectCover: some View {
        VStack(spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Not connected yet")
                .font(.title3.weight(.semibold))
            Text("Add the web app link and key once — everything then comes straight from your sheet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Connect") { showSettings = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UI.canvas)
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .help("Connection settings")
        }
    }
}
