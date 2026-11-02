import PortalKit
import SwiftUI

extension AppSection {
    var titleKey: LocalizedStringKey {
        switch self {
        case .assistant: "Messages"
        case .chats: "Chats"
        case .tickets: "Tickets"
        case .site: "Sites"
        case .more: "More"
        case .surveillance: "Surveillance"
        case .releases: "Releases"
        case .goals: "Goals"
        case .ideas: "Ideas"
        case .knowledge: "What it knows"
        case .automations: "Automations"
        case .incidents: "Incidents"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .assistant: "sparkles"
        case .chats: "bubble.left.and.bubble.right"
        case .tickets: "tray.full"
        case .site: "building.2"
        case .more: "ellipsis"
        case .surveillance: "video"
        case .releases: "shippingbox"
        case .goals: "scope"
        case .ideas: "lightbulb"
        case .knowledge: "brain.head.profile"
        case .automations: "clock.arrow.2.circlepath"
        case .incidents: "exclamationmark.shield"
        case .settings: "gearshape"
        }
    }

    /// The screen of More that fills a tab of this section, for the sections that are such a screen.
    var moreDestination: MoreDestination? {
        switch self {
        case .surveillance: .surveillance
        case .releases: .releases
        case .goals: .goals
        case .ideas: .ideas
        case .knowledge: .knowledge
        case .automations: .automations
        case .incidents: .incidents
        case .settings: .settings
        case .site: .sites
        case .tickets: .tickets
        case .assistant, .chats, .more: nil
        }
    }
}

/// MainTabsView is the signed-in app: the tabs of the person's kind, which
/// become a sidebar on a wide iPad window.
struct MainTabsView: View {
    @Environment(AppModel.self) private var appModel
    let account: Account

    @State private var session: SessionModel?

    var body: some View {
        Group {
            if let session {
                switch session.phase {
                case .loading:
                    ProgressView()
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could not load your account", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await session.load() } }
                    }
                case .loaded:
                    tabs(session)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: account.accountKey) {
            let newSession = SessionModel(
                account: account, connection: appModel.connection(for: account),
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            session = newSession
            await newSession.load()
            // The tab bar offers Surveillance only to a person with cameras, so the cameras are read at launch. The screenshot run waits for them.
            if appModel.isDemo {
                try? await newSession.surveillance.load()
            } else {
                Task { try? await newSession.surveillance.load() }
            }
            if !appModel.isDemo {
                newSession.startNotificationFeed(socketFactory: appModel.socketFactory)
                if let route = appModel.takeRoute(for: account) { newSession.open(route) }
            }
            var start = DemoOptions.section ?? Navigation.home(for: newSession.persona)
            // Chats are part of Messages: there is no tab of their own.
            if start == .chats { start = .assistant }
            if !newSession.tabSections.contains(start) { start = Navigation.home(for: newSession.persona) }
            newSession.selectedSection = start
            if appModel.isDemo, DemoOptions.screen == "ask" || DemoOptions.screen == "ask-site" || DemoOptions.screen == "conversation-reply" || DemoOptions.screen == "main-chat" {
                if DemoOptions.screen == "ask-site" {
                    Task { await newSession.beginAsk(about: Viewing(kind: "site", id: "site01"), subject: "Example Yard") }
                } else if DemoOptions.screen == "ask" {
                    Task { await newSession.beginAsk(about: Viewing(kind: "ticket", id: "ticket01"), subject: "#1 Gripper drops boxes at pick station 3") }
                } else if DemoOptions.screen == "main-chat" {
                    newSession.conversationToOpen = "conversation-main"
                } else {
                    newSession.conversationToOpen = "conversation01"
                }
            }
        }
    }

    private func badge(for section: AppSection, _ session: SessionModel) -> Int {
        switch section {
        case .assistant: session.waiting.count + session.chatUnreadCount
        case .chats: session.chatUnreadCount
        default: 0
        }
    }

    private func tabs(_ session: SessionModel) -> some View {
        TabView(selection: Binding(get: { session.selectedSection }, set: { session.selectedSection = $0 })) {
            ForEach(session.tabSections) { section in
                Tab(section.titleKey, systemImage: section.symbol, value: section) {
                    SectionContent(section: section, account: account)
                }
                .badge(badge(for: section, session))
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(session)
        .onChange(of: session.selectedSection, initial: true) { _, section in
            // A screen that is not on the tab bar opens under More: a notification may point at it, or the person removed its tab.
            guard !session.tabSections.contains(section) else { return }
            session.selectedSection = .more
            session.moreScreenToOpen = section.moreDestination
        }
        .onChange(of: session.tabSections) { _, sections in
            if !sections.contains(session.selectedSection) { session.selectedSection = .more }
        }
        .sheet(isPresented: Binding(get: { session.isShowingNotifications }, set: { session.isShowingNotifications = $0 })) {
            NotificationsView()
                .environment(session)
        }
        .sheet(item: Binding(get: { appModel.openedLink }, set: { appModel.openedLink = $0 })) { opened in
            LinkedPageSheet(link: opened.link)
                .environment(appModel)
                .environment(session)
        }
        .onChange(of: appModel.pendingRoute) { _, _ in
            if let route = appModel.takeRoute(for: account) { session.open(route) }
        }
        .onDisappear { session.stopNotificationFeed() }
        .task {
            // The notification feed tells the app when something changes. Without it
            // (an older server, or while it reconnects) the web app's 30 second poll is kept.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if !session.isNotificationFeedLive { await session.refreshWaiting() }
            }
        }
    }
}

/// SectionContent is what one tab shows.
private struct SectionContent: View {
    @Environment(SessionModel.self) private var session
    let section: AppSection
    let account: Account

    var body: some View {
        switch section {
        case .assistant: ConversationListView(account: account)
        case .chats: ConversationListView(account: account)
        case .more: MoreView(account: account)
        case .tickets: TicketsView()
        case .site: session.persona == .staff ? AnyView(StaffSitesView()) : AnyView(SiteView())
        case .surveillance, .releases, .goals, .ideas, .knowledge, .automations, .incidents, .settings:
            if let destination = section.moreDestination { DestinationTab(root: destination) }
        }
    }
}

/// DestinationTab is a screen of More shown as a tab: the same screen, with the same screens it pushes.
private struct DestinationTab: View {
    let root: MoreDestination

    var body: some View {
        NavigationStack {
            MoreDestinationView(destination: root, isTabRoot: true)
                .portalDestinations()
                .navigationDestination(for: MoreDestination.self) { destination in
                    MoreDestinationView(destination: destination)
                        .toolbarVisibility(.hidden, for: .tabBar)
                }
        }
    }
}
