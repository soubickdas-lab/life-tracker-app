import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct LifeTrackerApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
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
    @State private var copied = false
    #if os(iOS)
    @AppStorage("phoneTab") private var phoneTab = 0   /* reopen where you left off */
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
            }
        }
        .task {
            await store.checkDoor()
            if store.isConfigured {
                await store.refresh()
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar").font(.system(size: 14, weight: .medium))
                    Text("Subscribe to this in Calendar and your timed tasks show up there. It refreshes itself every few minutes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button("Copy calendar link") { copyCalendar() }
                        #if os(macOS)
                        Button("Subscribe now") {
                            if let url = URL(string: store.calendarLink.replacingOccurrences(
                                of: "https://", with: "webcal://")) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        #endif
                    }
                    if copied {
                        Text("Copied — paste it into Calendar ▸ New Calendar Subscription")
                            .font(.system(size: 11)).foregroundStyle(UI.mint)
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

    @ViewBuilder private var content: some View {
        #if os(iOS)
        TabView(selection: $phoneTab) {
            wrap(DayScreen(label: "Today"), "Today")
                .tabItem { Label("Today", systemImage: "checkmark.circle") }
                .tag(0)
            wrap(DayScreen(label: "Tomorrow"), "Tomorrow")
                .tabItem { Label("Tomorrow", systemImage: "arrow.right.circle") }
                .tag(1)
            wrap(GoalsScreen(), "Long Term")
                .tabItem { Label("Long Term", systemImage: Pane.longTerm.icon) }
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
                    pageLink(.habits)
                    pageLink(.dash)
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

    private var settingsButton: some ToolbarContent {
        ToolbarItem {
            Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                .help("Account")
        }
    }
}
