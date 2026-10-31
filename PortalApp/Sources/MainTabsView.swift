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
    @State private var selection = AppSection.assistant

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
            selection = DemoOptions.section ?? Navigation.home(for: newSession.persona)
        }
    }

    private func tabs(_ session: SessionModel) -> some View {
        TabView(selection: $selection) {
            ForEach(Navigation.sections(for: session.persona)) { section in
                Tab(section.titleKey, systemImage: section.symbol, value: section) {
                    SectionContent(section: section, account: account)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(session)
    }
}

/// SectionContent is what one tab shows.
private struct SectionContent: View {
    let section: AppSection
    let account: Account

    var body: some View {
        switch section {
        case .assistant: ConversationListView(account: account)
        case .chats: ChatsView()
        case .more: MoreView(account: account)
        case .monitoring, .tickets, .site, .customers: PlaceholderView(section: section)
        }
    }
}

/// PlaceholderView stands in for a part that is not built yet.
private struct PlaceholderView: View {
    let section: AppSection

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(section.titleKey, systemImage: section.symbol)
            } description: {
                Text("This part is coming soon.")
            }
            .navigationTitle(section.titleKey)
        }
    }
}
