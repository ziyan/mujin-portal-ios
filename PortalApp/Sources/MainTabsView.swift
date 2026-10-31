import PortalKit
import SwiftUI

extension AppSection {
    var titleKey: LocalizedStringKey {
        switch self {
        case .monitoring: "Monitoring"
        case .assistant: "Assistant"
        case .chats: "Chats"
        case .tickets: "Tickets"
        case .site: "Site"
        case .customers: "Customers"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .monitoring: "waveform.path.ecg"
        case .assistant: "sparkles"
        case .chats: "bubble.left.and.bubble.right"
        case .tickets: "tray.full"
        case .site: "building.2"
        case .customers: "person.2"
        case .more: "ellipsis"
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
            if !appModel.isDemo {
                newSession.startNotificationFeed(socketFactory: appModel.socketFactory)
                if let route = appModel.takeRoute(for: account) { newSession.open(route) }
            }
            var start = DemoOptions.section ?? Navigation.home(for: newSession.persona)
            // Mujin users have no Chats tab: chats are the other half of Assistant.
            if start == .chats && newSession.isStaff {
                start = .assistant
                newSession.assistantPart = .chats
            }
            newSession.selectedSection = start
            if appModel.isDemo, DemoOptions.screen == "ask" || DemoOptions.screen == "conversation-reply" {
                if DemoOptions.screen == "ask" {
                    newSession.pendingReference = SessionModel.PendingReference(
                        conversationId: "conversation01", viewing: Viewing(kind: "ticket", id: "ticket01"), subject: "#1 Gripper drops boxes at pick station 3")
                }
                newSession.conversationToOpen = "conversation01"
            }
        }
    }

    private func badge(for section: AppSection, _ session: SessionModel) -> Int {
        switch section {
        case .assistant: session.waiting.count + (session.isStaff ? session.chatUnreadCount : 0)
        case .chats: session.chatUnreadCount
        default: 0
        }
    }

    private func tabs(_ session: SessionModel) -> some View {
        TabView(selection: Binding(get: { session.selectedSection }, set: { session.selectedSection = $0 })) {
            ForEach(Navigation.sections(for: session.persona)) { section in
                Tab(section.titleKey, systemImage: section.symbol, value: section) {
                    SectionContent(section: section, account: account)
                }
                .badge(badge(for: section, session))
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(session)
        .sheet(isPresented: Binding(get: { session.isShowingNotifications }, set: { session.isShowingNotifications = $0 })) {
            NotificationsView()
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
    let section: AppSection
    let account: Account

    var body: some View {
        switch section {
        case .assistant: AssistantContainer(account: account)
        case .chats: ChatsView(account: account)
        case .more: MoreView(account: account)
        case .tickets: TicketsView()
        case .site: SiteView()
        case .monitoring: MonitoringView()
        case .customers: CustomersView()
        }
    }
}

/// AssistantContainer is the Assistant tab. A Mujin user has no Chats tab, so
/// chats are the other half of this one, chosen by a control at the top.
private struct AssistantContainer: View {
    @Environment(SessionModel.self) private var session
    let account: Account

    var body: some View {
        if session.isStaff && session.capabilities.offersChats {
            VStack(spacing: 0) {
                Picker("Show", selection: Binding(get: { session.assistantPart }, set: { session.assistantPart = $0 })) {
                    Text("Conversations").tag(AssistantPart.conversations)
                    Text(session.chatUnreadCount > 0 ? LocalizedStringKey("Chats (\(session.chatUnreadCount))") : LocalizedStringKey("Chats")).tag(AssistantPart.chats)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch session.assistantPart {
                case .conversations: ConversationListView(account: account)
                case .chats: ChatsView(account: account)
                }
            }
        } else {
            ConversationListView(account: account)
        }
    }
}
