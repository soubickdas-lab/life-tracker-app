import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct LifeTrackerApp: App {
    @State private var store = Store()

    init() { Notifier.wire() }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(store)
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 800)
        .commands {
            CommandGroup(after: .toolbar) {
                ForEach(Array((Pane.main + Pane.rest).enumerated()), id: \.element) { index, pane in
                    Button(pane.title) { store.pane = pane }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        /* Today in the menu bar: one click, tick something off, carry on. */
        MenuBarExtra {
            MenuBarList().environment(store)
        } label: {
            Label(store.menuBarCount, systemImage: "checkmark.circle")
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

/// Tabs on the phone, one window with a toolbar on the Mac.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showChat = false
    @State private var copied = false
    #if os(iOS)
    @AppStorage("phoneTab2") private var phoneTab = 0  /* reopen where you left off */
    @State private var morePath: [Pane] = []
    #endif

    var body: some View {
        Group {
            if !store.isSignedIn {
                SignInView()
            } else if store.waiting {
                WaitingView()
            } else if store.isAdmin {
                OwnerView()
            } else {
                content
                    .overlay(alignment: .bottomTrailing) { chatButton }
            }
        }
        .sheet(isPresented: $showChat) {
            AssistantScreen(onClose: { showChat = false })
                .environment(store)
                #if os(macOS)
                .frame(width: 460, height: 620)
                #endif
        }
        .task {
            /* the day is already on screen from the cache — these two just freshen
               it, and neither waits on the other */
            async let door: Void = store.checkDoor()
            async let day: Void = store.refresh(quietly: !store.state.days.isEmpty)
            _ = await (door, day)
            if store.isConfigured {
                Notifier.askOnce()          /* only once there is something to remind about */
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.checkDoor() }
                store.cameToFront()
            } else {
                store.wentAway()
            }
        }
        .onChange(of: store.token) { _, fresh in
            if !fresh.isEmpty, store.isConfigured {
                Task { await store.refresh(); Notifier.askOnce() }
            }
        }
        .sheet(isPresented: $showSettings) { accountSheet }
    }

    /// The assistant, one tap away from wherever you are.
    private var chatButton: some View {
        Button { showChat = true } label: {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(UI.accent, in: Circle())
                .shadow(color: UI.accent.opacity(0.35), radius: 9, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Assistant")
        #if os(iOS)
        .padding(.trailing, 16)
        .padding(.bottom, 62)            /* clear of the tab bar */
        #else
        .padding(20)
        #endif
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private func copyCalendar() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.calendarLink, forType: .string)
        #else
        UIPasteboard.general.string = store.calendarLink
        #endif
        copied = true
    }

    /// Who you are, and the way out.
    private var accountSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account").font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(store.email.isEmpty ? "Signed in" : store.email)
                    .font(.system(size: 15, weight: .medium))
                Text(store.isAdmin ? "Owner — you can let new people in from the web app"
                                   : "Signed in on this device")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !store.calendarLink.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your calendar").font(.system(size: 14, weight: .medium))
                    Text("Put your timed tasks into the calendar you already use. One tap — it keeps itself up to date.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        open(store.calendarLink.replacingOccurrences(of: "https://", with: "webcal://"))
                    } label: {
                        Label("Add to Apple Calendar", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        let encoded = store.calendarLink
                            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                        open("https://calendar.google.com/calendar/render?cid=" + encoded)
                    } label: {
                        Label("Add to Google Calendar", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }

                    Button("Copy the link instead") { copyCalendar() }
                        .font(.system(size: 12))

                    if copied {
                        Text("Copied").font(.system(size: 11)).foregroundStyle(UI.mint)
                    }
                }
            }

            if let last = store.lastSync {
                Text("Last synced \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Divider()

            Button("Sign out", role: .destructive) {
                store.signOut()
                showSettings = false
            }

            HStack {
                Spacer()
                Button("Done") { showSettings = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 360)
        #endif
    }

    /// The journey is there once you have one, and wears its own name.
    private var mainPanes: [Pane] {
        Pane.main.filter { $0 != .journey || !store.state.journeys.isEmpty }
    }

    private func title(of pane: Pane) -> String {
        if pane == .journey, let first = store.state.journeys.first { return first.name }
        return pane.title
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
        TabView(selection: $phoneTab) {
            wrap(DayScreen(), "")
                .tabItem { Label("Today", systemImage: Pane.today.icon) }
                .tag(0)
            if let journey = store.state.journeys.first {
                wrap(JourneyScreen(), "")
                    .tabItem { Label(shortName(journey.name), systemImage: Pane.journey.icon) }
                    .tag(1)
            }
            wrap(LaterScreen(), "")
                .tabItem { Label("Later", systemImage: Pane.later.icon) }
                .tag(2)
            moreTab
                .tabItem { Label("More", systemImage: "square.grid.2x2") }
                .tag(3)
        }
        .onChange(of: store.jump) { _, page in
            guard let page else { return }
            store.jump = nil
            go(to: page)
        }
        #else
        NavigationSplitView {
            List(selection: Binding<Pane?>(
                get: { store.pane },
                set: { store.pane = $0 ?? .today })) {
                Section {
                    ForEach(mainPanes) { item in
                        Label(title(of: item), systemImage: item.icon).tag(item)
                    }
                }
                Section("More") {
                    ForEach(Pane.rest) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            NavigationStack {
                paneScreen(store.pane)
                    .navigationTitle(title(of: store.pane))
                    .toolbar {
                        ToolbarItem {
                            Button { Task { await store.refresh() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Refresh")
                        }
                        settingsButton
                    }
            }
        }
        #endif
    }

    @ViewBuilder private func paneScreen(_ pane: Pane) -> some View {
        switch pane {
        case .today:     DayScreen()
        case .journey:   JourneyScreen()
        case .later:     LaterScreen()
        case .habits:    HabitsScreen()
        case .scheduled: ScheduledScreen()
        case .dash:      DashboardScreen()
        case .body:      BodyScreen()
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

    /// A page with its own tab gets that tab; everything else opens under More.
    private func go(to page: Pane) {
        switch page {
        case .today:   phoneTab = 0
        case .journey: phoneTab = store.state.journeys.isEmpty ? 0 : 1
        case .later:   phoneTab = 2
        default:
            morePath = [page]
            phoneTab = 3
        }
    }

    private var moreTab: some View {
        NavigationStack(path: $morePath) {
            List {
                Section {
                    ForEach(Pane.rest) { pane in
                        NavigationLink(value: pane) { Label(pane.title, systemImage: pane.icon) }
                    }
                }
            }
            .navigationTitle("More")
            .toolbar { settingsButton }
            .navigationDestination(for: Pane.self) { pane in
                paneScreen(pane)
                    .navigationTitle(pane.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    /// A tab label has room for about twelve characters.
    private func shortName(_ name: String) -> String {
        name.count <= 12 ? name : String(name.prefix(11)) + "…"
    }
    #endif

    private var settingsButton: some ToolbarContent {
        ToolbarItem {
            Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                .help("Account")
        }
    }
}
