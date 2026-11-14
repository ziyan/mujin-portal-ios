import PortalKit
import SwiftUI
import UIKit

extension AppSection {
    var titleKey: LocalizedStringKey {
        switch self {
        case .assistant: "Chat"
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
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .assistant: "bubble.left.and.bubble.right"
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
        case .search: "magnifyingglass"
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
        case .assistant, .chats, .more, .search: nil
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
                newSession.startCallFeed(socketFactory: appModel.socketFactory)
                newSession.onRingStopped = { [appModel = self.appModel] callId in appModel.callCenter.stopRinging(callId: callId) }
            }
            var start = DemoOptions.section ?? Navigation.home(for: newSession.persona)
            // Chats are part of Chat: there is no tab of their own.
            if start == .chats { start = .assistant }
            if !newSession.tabSections.contains(start) { start = Navigation.home(for: newSession.persona) }
            newSession.selectedSection = start
            // After the tab the app starts on: a notification that launched the app chooses its own.
            if !appModel.isDemo, let route = appModel.takeRoute(for: account) { newSession.open(route) }
            if appModel.isDemo, let screen = DemoOptions.screen, CallDemo.owns(screen), screen.hasPrefix("call-"), screen != "call-picker" {
                appModel.callCenter.showDemo(CallDemo.session(for: screen), isScreenShown: screen != "call-minimized")
            }
            if appModel.isDemo, DemoOptions.screen == "chat-in-call" {
                appModel.callCenter.showDemo(CallDemo.session(for: "chat-in-call"), isScreenShown: false)
            }
            // A notification tapped while the full-screen call is up: the call shrinks to its bar and the conversation shows.
            if appModel.isDemo, DemoOptions.screen == "call-push" {
                Task { [appModel = self.appModel, account] in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    appModel.pendingRoute = AppModel.PendingRoute(userId: account.userId, route: .conversation(id: "conversation01"))
                }
            }
            // A notification about a reply in a thread, as if it had launched the app: the chat opens on that thread.
            if appModel.isDemo, DemoOptions.screen == "thread-push" {
                newSession.open(.chatThread(conversationId: ThreadDemo.chatConversationId, threadRootMessageId: ThreadDemo.chatThreadRootMessageId))
            }
            // A link to a message of the chat that is in a thread: the chat opens on the thread, at that message.
            if appModel.isDemo, DemoOptions.screen == "thread-link" {
                Task { await newSession.openChatMessage(chatId: "chat-thread", messageId: "t03") }
            }
            // A notification tapped a few seconds after launch, for a test that sends the app away first.
            if appModel.isDemo, let screen = DemoOptions.screen, screen.hasPrefix("push:") {
                let conversationId = String(screen.dropFirst("push:".count))
                Task { [appModel = self.appModel, account] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    appModel.pendingRoute = AppModel.PendingRoute(userId: account.userId, route: .conversation(id: conversationId))
                }
            }
            // The screenshot a person takes, as the system announces it: the demo has no side buttons to press.
            if appModel.isDemo, FeedbackDemo.postsScreenshot(DemoOptions.screen) {
                if DemoOptions.screen == "feedback-in-call" {
                    appModel.callCenter.showDemo(CallDemo.session(for: "call-voice"), isScreenShown: false)
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
                }
            }
            if appModel.isDemo, let screen = DemoOptions.screen, screen.hasPrefix("link-") {
                appModel.linkRequest = ControllerLinkRequest(code: screen == "link-confirm" ? DemoServer.linkCode : nil)
            }
            // Once the first tab has settled: choosing a tab closes what is over it, as it does for a person.
            if appModel.isDemo, DemoOptions.screen == "site-from-link" {
                Task { [appModel = self.appModel] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    appModel.openedLink = OpenedLink(link: .site(id: "site03"))
                }
            }
            if appModel.isDemo, DemoOptions.screen == "notifications" || DemoOptions.screen == "notifications-past" {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    newSession.isShowingNotifications = true
                }
            }
            if appModel.isDemo, DemoOptions.screen == "ask" || DemoOptions.screen == "ask-site" || DemoOptions.screen == "conversation-reply" || DemoOptions.screen == "conversation-composer" || DemoOptions.screen == "main-chat" {
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

    /// The link to show in a sheet: only the links that are a screen. The others go where they belong, see `routeLink`.
    private func linkSheetBinding(_ session: SessionModel) -> Binding<OpenedLink?> {
        Binding<OpenedLink?>(
            get: {
                guard let opened = appModel.openedLink else { return nil }
                let resolution = session.resolution(for: opened.link, organizationId: opened.organizationId)
                return resolution.isSheet ? opened : nil
            },
            set: { appModel.openedLink = $0 })
    }

    /// Sends a link that is not a sheet where it belongs: a tab, the inbox, a conversation or the browser.
    private func routeLink(_ opened: OpenedLink, _ session: SessionModel) {
        let resolution = session.resolution(for: opened.link, organizationId: opened.organizationId)
        guard !resolution.isSheet else { return }
        appModel.openedLink = nil
        switch resolution {
        case .conversation(let id): session.open(.conversation(id: id))
        case .chatMessage(let chatId, let messageId): Task { await session.openChatMessage(chatId: chatId, messageId: messageId) }
        case .tab(let section): session.selectedSection = section
        case .notifications: session.isShowingNotifications = true
        case .web:
            let address = opened.link.url(server: account.server)
            Task { await appModel.openInApp(address, account: account) }
        case .screen, .lookup: break
        }
    }

    /// A screenshot was taken. The notification carries no picture, so the app draws its own window. Nothing opens on a server without
    /// feedback, when the person turned it off, during a call, or while the sheet is already up. Nothing is sent until Send is pressed.
    private func offerFeedback(after session: SessionModel) {
        guard session.capabilities.offersPortalFeedback, FeedbackPreference.shouldAskAfterScreenshot, session.feedbackRequest == nil,
            !appModel.callCenter.isInCall, appModel.activeAccount != nil
        else { return }
        session.feedbackRequest = FeedbackRequest(pictureData: ScreenPicture.captureKeyWindow(), screenName: session.selectedSection.rawValue)
    }

    /// Closes whatever covers the screen, so a page that is opened shows instead of opening behind it. The full-screen call shrinks to
    /// its bar and goes on; the feedback sheet goes away keeping the words typed so far, which it shows again when it next opens. A
    /// feedback sheet that is sending stays until it is done, so the ticket is sent once.
    private func closeSheets(_ session: SessionModel) {
        appModel.openedLink = nil
        appModel.openedCitation = nil
        session.isShowingNotifications = false
        if !session.isSendingFeedback { session.feedbackRequest = nil }
        if appModel.callCenter.isScreenShown { appModel.callCenter.minimize() }
    }

    private func tabBar(_ session: SessionModel) -> some View {
        let chosenSections = session.tabSections.filter { $0 != .search }
        return TabView(selection: Binding(get: { session.selectedSection }, set: { session.selectedSection = $0 })) {
            ForEach(chosenSections) { section in
                Tab(value: section) {
                    SectionContent(section: section, account: account)
                } label: {
                    Label {
                        Text(section.titleKey)
                    } icon: {
                        Image(uiImage: TabIcon.image(for: section.symbol))
                    }
                }
                .badge(badge(for: section, session))
            }
            // The system's search tab: set apart at the trailing end of the bar, with the search field at the bottom.
            Tab(value: AppSection.search, role: .search) {
                SectionContent(section: .search, account: account)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(session)
        .alert(
            "That message could not be found.", isPresented: Binding(get: { session.linkNotice != nil }, set: { if !$0 { session.linkNotice = nil } }),
            actions: { Button("OK", role: .cancel) {} })
    }

    private func tabs(_ session: SessionModel) -> some View {
        tabBar(session)
        .onChange(of: session.selectedSection, initial: true) { _, section in
            // A screen that is not on the tab bar opens under More: a notification may point at it, or the person removed its tab.
            guard !session.tabSections.contains(section) else { return }
            session.selectedSection = .more
            session.moreScreenToOpen = section.moreDestination
        }
        .onChange(of: session.tabSections) { _, sections in
            if !sections.contains(session.selectedSection) { session.selectedSection = .more }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                // A conversation, chat or thread on screen shows a call going elsewhere in a strip under its own header instead.
                if session.callStripsShown.isEmpty, let call = appModel.callCenter.session, !appModel.callCenter.isScreenShown, !call.isEnded,
                    appModel.callCenter.chatIdOnScreen != call.chatId
                {
                    CallBar(center: appModel.callCenter, call: call)
                }
                // A call with the assistant whose conversation is off screen goes on here, as a call with people does.
                if session.callStripsShown.isEmpty, let call = session.assistantCall, call.isGoing, session.callPlaceOnScreen != call.place {
                    // The bar sits outside the tab bar, which is where the session is put in the environment.
                    AssistantCallBar(call: call)
                        .environment(session)
                }
            }
        }
        // These show over the top screen, so an incoming call, a link or the inbox shows even while a sheet is up.
        .topPresentation(isPresented: Binding(get: { appModel.callCenter.isScreenShown }, set: { appModel.callCenter.isScreenShown = $0 }), style: .overFullScreen) { [appModel = self.appModel] in
            CallScreen(center: appModel.callCenter)
                .modifier(HostedEnvironment(appModel: appModel, session: session))
        }
        .topPresentation(isPresented: Binding(get: { session.isShowingNotifications }, set: { session.isShowingNotifications = $0 }), style: .pageSheet) { [appModel = self.appModel] in
            NotificationsView()
                .modifier(HostedEnvironment(appModel: appModel, session: session))
        }
        .topPresentation(item: Binding(get: { appModel.linkRequest }, set: { appModel.linkRequest = $0 }), style: .overFullScreen) { [appModel = self.appModel] request in
            LinkControllerView(request: request)
                .modifier(HostedEnvironment(appModel: appModel, session: session))
        }
        .topPresentation(item: linkSheetBinding(session), style: .pageSheet) { [appModel = self.appModel] opened in
            LinkedPageSheet(opened: opened)
                .modifier(HostedEnvironment(appModel: appModel, session: session))
        }
        // Beside the linked page: a memory page reads the signed-in session, which RootView does not have.
        .topPresentation(item: Binding(get: { appModel.openedCitation.map(IdentifiableCitation.init) }, set: { appModel.openedCitation = $0?.citation }), style: .pageSheet) { [appModel = self.appModel] item in
            MemoryCitationSheet(citation: item.citation)
                .modifier(HostedEnvironment(appModel: appModel, session: session))
        }
        // A screenshot opens the feedback sheet, over whatever is on top of the app.
        .topPresentation(item: Binding(get: { session.feedbackRequest }, set: { session.feedbackRequest = $0 }), style: .pageSheet) { [appModel = self.appModel] request in
            FeedbackView(request: request)
                .modifier(HostedEnvironment(appModel: appModel, session: session))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            offerFeedback(after: session)
        }
        // The person asked to go to a tab or a conversation, such as "Ask about" on a page in a sheet: the sheet is over it.
        .onChange(of: session.selectedSection) { _, _ in closeSheets(session) }
        // A page opened on the tab already shown, such as a chat from a notification while on Chat, changes no tab.
        .onChange(of: session.pageOpenCount) { _, _ in closeSheets(session) }
        // A call with the assistant that ends, or fails, while its conversation or thread is off screen is let go of here, with its
        // conversation's live feed; one on screen keeps its own.
        .onChange(of: session.assistantCall?.isGoing ?? false) { _, isGoing in
            guard !isGoing, let call = session.assistantCall, session.callPlaceOnScreen != call.place else { return }
            call.end()
            session.assistantCall = nil
        }
        .onChange(of: session.conversationToOpen) { _, conversationId in if conversationId != nil { closeSheets(session) } }
        .onChange(of: session.composeRequest != nil) { _, isComposing in if isComposing { closeSheets(session) } }
        .onChange(of: appModel.openedLink, initial: true) { _, opened in
            if let opened { routeLink(opened, session) }
        }
        .onChange(of: appModel.pendingRoute) { _, _ in
            if let route = appModel.takeRoute(for: account) { session.open(route) }
        }
        .onDisappear {
            session.stopNotificationFeed()
            session.stopCallFeed()
        }
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
        case .search: SearchTabView()
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
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            MoreDestinationView(destination: root, isTabRoot: true)
                .portalDestinations()
                .navigationDestination(for: MoreDestination.self) { destination in
                    MoreDestinationView(destination: destination)
                        .hidesTabBarWhenCompact()
                }
        }
        .pushesRoutes { route in path.append(route) }
    }
}

/// TabIcon draws a tab's symbol fitted into one square, so a tall symbol (two speech bubbles, a building) and a short
/// one (a camera, three dots) take the same room on the tab bar instead of following each symbol's own proportions.
@MainActor
enum TabIcon {
    private static let side: CGFloat = 26
    private static var images: [String: UIImage] = [:]

    static func image(for symbol: String) -> UIImage {
        if let image = images[symbol] { return image }
        let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        // The tab bar shows filled symbols, so draw the filled variant where there is one.
        guard let source = UIImage(systemName: symbol + ".fill", withConfiguration: configuration)
            ?? UIImage(systemName: symbol, withConfiguration: configuration)
        else { return UIImage() }
        let scale = min(side / source.size.width, side / source.size.height)
        let drawnSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let origin = CGPoint(x: (side - drawnSize.width) / 2, y: (side - drawnSize.height) / 2)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            source.withTintColor(.black).draw(in: CGRect(origin: origin, size: drawnSize))
        }.withRenderingMode(.alwaysTemplate)
        images[symbol] = image
        return image
    }
}
