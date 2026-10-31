import Foundation
import Observation
import PortalKit

/// SessionModel is what the app knows about the signed-in person once they
/// are in: who they are, which kind of person that is, and what their server
/// offers. The tabs and every screen under them read it.
@MainActor
@Observable
final class SessionModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let account: Account
    let connection: Connection
    private(set) var phase = Phase.loading
    private(set) var profile: Profile?
    private(set) var capabilities = ServerCapabilities()
    /// Questions and approvals that wait for the person, in any conversation.
    private(set) var waiting: [WaitingItem] = []
    /// The tab in front. Screens change it to take the person elsewhere.
    var selectedSection = AppSection.assistant
    /// A conversation the Assistant tab should open as soon as it can.
    var conversationToOpen: String?
    /// For Mujin users, which half of the Assistant tab is in front.
    var assistantPart = AssistantPart.conversations
    /// A chat's conversation the Chats tab should open, from a notification.
    var chatToOpen: String?
    /// Unread messages across the person's chats.
    private(set) var chatUnreadCount = 0
    /// A ticket the Tickets tab should open, from a notification.
    var ticketToOpen: String?
    /// Set when a notification asks More to show the Automations screen.
    var automationsRequested = false
    var isShowingNotifications = DemoOptions.screen == "notifications"
    /// Entries in the inbox not read yet.
    private(set) var unreadCount = 0
    /// Counts up whenever the server says a notification was created, so an open inbox reads again.
    private(set) var notificationRevision = 0
    /// Whether the notification feed is up. While it is not, the lists are polled.
    private(set) var isNotificationFeedLive = false
    private var notificationFeedTask: Task<Void, Never>?
    /// A goal to show in More, from a notification.
    var goalToOpen: String?
    let onError: @MainActor (Error) -> Void

    init(account: Account, connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.account = account
        self.connection = connection
        self.onError = onError
    }

    var persona: Persona { profile?.persona ?? .customer }
    var userId: String { account.userId }
    var organizationId: String? { profile?.me.organizationId }
    var isStaff: Bool { persona == .staff }

    var waitingCounts: [String: Int] { waiting.countsByConversation }

    // MARK: names

    private(set) var personNames: [String: String] = [:]
    private var requestedPeople: Set<String> = []
    private(set) var organizationNames: [String: String] = [:]
    private(set) var siteNames: [String: String] = [:]

    /// How a person is named beside a comment or a ticket.
    func name(ofPerson id: String?) -> String {
        guard let id, !id.isEmpty else { return String(localized: "Nobody") }
        if id == userId { return String(localized: "You") }
        return personNames[id] ?? String(localized: "Someone")
    }

    /// Looks up the names of people not looked up yet.
    func loadPeople(_ ids: [String]) async {
        let wanted = Set(ids.filter { !$0.isEmpty && $0 != userId }).subtracting(requestedPeople)
        guard !wanted.isEmpty else { return }
        requestedPeople.formUnion(wanted)
        let connection = connection
        let found = await withTaskGroup(of: PersonSummary?.self, returning: [PersonSummary].self) { group in
            for id in wanted { group.addTask { try? await connection.person(id: id) } }
            var people: [PersonSummary] = []
            for await person in group { if let person { people.append(person) } }
            return people
        }
        for person in found { if let name = person.shownName { personNames[person.id] = name } }
    }

    /// Names organizations and sites for the lists that show where something is.
    func loadPlaces() async {
        if let sites = try? await connection.sites() {
            siteNames = Dictionary(sites.map { ($0.id, $0.name ?? "") }, uniquingKeysWith: { first, _ in first })
        }
        if isStaff, let organizations = try? await connection.organizations() {
            organizationNames = Dictionary(organizations.map { ($0.id, $0.name ?? "") }, uniquingKeysWith: { first, _ in first })
        } else if let id = organizationId, let name = profile?.organizationName {
            organizationNames[id] = name
        }
    }

    /// Reads what waits for the person. The web app asks every 30 seconds too.
    func refreshChatUnread() async {
        guard capabilities.offersChats, let chats = try? await connection.chats() else { return }
        chatUnreadCount = chats.reduce(0) { $0 + ($1.chat?.unreadCount ?? 0) }
    }

    func refreshUnreadCount() async {
        if let count = try? await connection.unreadNotificationCount() { unreadCount = count }
    }

    /// Keeps the inbox current through the server's OnNotification feed
    /// instead of polling it. The feed reconnects by itself, renews the token
    /// when the server closes it with 4401, and says nothing about what it
    /// missed, so every reconnect reads the lists again.
    func startNotificationFeed(socketFactory: @escaping FeedSocketFactory) {
        guard notificationFeedTask == nil, capabilities.offersNotificationFeed else { return }
        notificationFeedTask = Task { [weak self] in
            guard let self else { return }
            for await update in NotificationFeed.updates(connection: connection, socketFactory: socketFactory) {
                switch update {
                case .connected:
                    isNotificationFeedLive = true
                    notificationRevision += 1
                    await refreshWaiting()
                case .created(_, let kind):
                    notificationRevision += 1
                    await refreshUnreadCount()
                    if kind == "agent_waiting" || kind == "agent_message" { await refreshWaitingList() }
                    if kind == "chat_message" { await refreshChatUnread() }
                case .reconnecting:
                    isNotificationFeedLive = false
                case .signedOut:
                    isNotificationFeedLive = false
                    onError(PortalError.signedOut)
                }
            }
        }
    }

    func stopNotificationFeed() {
        notificationFeedTask?.cancel()
        notificationFeedTask = nil
        isNotificationFeedLive = false
    }

    /// Goes where a notification or the assistant speaking first points.
    func open(_ route: PushRoute) {
        switch route {
        case .conversation(let id):
            conversationToOpen = id
            assistantPart = .conversations
            selectedSection = .assistant
        case .chat(let conversationId):
            chatToOpen = conversationId
            assistantPart = .chats
            selectedSection = isStaff ? .assistant : .chats
        case .goal(let id):
            goalToOpen = id
            selectedSection = .more
        case .automations:
            automationsRequested = true
            selectedSection = .more
        case .notifications:
            isShowingNotifications = true
        }
    }

    func refreshWaitingList() async {
        do {
            waiting = try await connection.waiting()
        } catch {
            onError(error)
        }
    }

    func refreshWaiting() async {
        await refreshUnreadCount()
        await refreshChatUnread()
        await refreshWaitingList()
    }

    /// Answers a question that waits, from the list, without opening the conversation.
    func answer(_ item: WaitingItem, with text: String) async -> String? {
        do {
            try await connection.answerQuestion(id: item.interactionId, answer: text)
            waiting.removeAll { $0.id == item.id }
            return nil
        } catch {
            if case PortalError.cardNoLongerWaiting = error { waiting.removeAll { $0.id == item.id } }
            onError(error)
            return error.userMessage
        }
    }

    func decide(_ item: WaitingItem, isApproved: Bool) async -> String? {
        do {
            try await connection.resolveToolApproval(id: item.interactionId, isApproved: isApproved)
            waiting.removeAll { $0.id == item.id }
            return nil
        } catch {
            if case PortalError.cardNoLongerWaiting = error { waiting.removeAll { $0.id == item.id } }
            onError(error)
            return error.userMessage
        }
    }

    /// A resource the next message in a conversation asks about, kept until the conversation opens.
    struct PendingReference {
        let conversationId: String
        let viewing: Viewing
        let subject: String
    }

    var pendingReference: PendingReference?

    /// Starts a conversation about the screen the person is looking at and
    /// opens it. The resource is a reference above the composer, not text in
    /// it: the person types the question and sends it with the reference.
    func beginAsk(about viewing: Viewing, subject: String) async {
        do {
            let agent = try await connection.mainAgent()
            let conversation = try await connection.createConversation(agentId: agent.id)
            pendingReference = PendingReference(conversationId: conversation.id, viewing: viewing, subject: subject)
            conversationToOpen = conversation.id
            assistantPart = .conversations
            selectedSection = .assistant
        } catch {
            onError(error)
        }
    }

    func load() async {
        do {
            async let loadedProfile = connection.profile()
            async let loadedCapabilities = connection.capabilities()
            let (newProfile, newCapabilities) = try await (loadedProfile, loadedCapabilities)
            profile = newProfile
            capabilities = newCapabilities
            phase = .loaded
            await refreshWaiting()
            await loadPlaces()
        } catch {
            onError(error)
            if profile == nil { phase = .failed(error.userMessage) }
        }
    }
}

/// AssistantPart is a half of the Assistant tab for Mujin users, who have no Chats tab.
enum AssistantPart: String, CaseIterable, Identifiable {
    case conversations
    case chats
    var id: String { rawValue }
}

/// DemoOptions are the choices a screenshot run makes through the environment.
enum DemoOptions {
    private static let environment = ProcessInfo.processInfo.environment

    /// The raw screen name, such as `conversation:conversation02` or `section:tickets`.
    static var screen: String? { environment["PORTAL_DEMO_SCREEN"] }

    /// The tab to open on, from `section:<name>`.
    static var section: AppSection? {
        guard let screen else { return nil }
        if screen.hasPrefix("section:") { return AppSection(rawValue: String(screen.dropFirst("section:".count))) }
        // Screens that live under More.
        if ["automations", "notifications", "about", "settings"].contains(where: { screen.hasPrefix($0) }) { return .more }
        if screen.hasPrefix("ticket") { return .tickets }
        if screen.hasPrefix("chat") { return .chats }
        if screen.hasPrefix("site") || screen.hasPrefix("incident") { return .site }
        return nil
    }

    /// Whether the demo person works for the administrator organization.
    static var isStaff: Bool { environment["PORTAL_DEMO_PERSONA"] == "staff" }
}
