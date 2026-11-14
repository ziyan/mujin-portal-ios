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
    /// Which of dictation and reading aloud the server has set up for this person. Neither, until the server says.
    private(set) var voiceAvailability = VoiceAvailability.unavailable
    /// The one message being read aloud, whichever screen asked.
    let readAloud: ReadAloudController
    /// Questions and approvals that wait for the person, in any conversation.
    private(set) var waiting: [WaitingItem] = []
    /// The tab in front. Screens change it to take the person elsewhere.
    var selectedSection = AppSection.assistant
    /// A conversation the Assistant tab should open as soon as it can.
    var conversationToOpen: String?
    /// A chat's conversation the Chats tab should open, from a notification.
    var chatToOpen: String?
    /// The thread the conversation named by `chatToOpen` or `conversationToOpen` should open on, from a notification about a reply.
    var threadToOpen: ThreadToOpen?
    /// A message a link points at, which the chat it is in scrolls to and marks for a moment.
    var messageToFocus: MessageFocus?
    /// Why a link to a message could not be opened, shown in a short alert.
    var linkNotice: String?
    /// Unread messages across the person's chats.
    private(set) var chatUnreadCount = 0
    /// The chat last read to its end, which the chat lists clear from their rows.
    private(set) var lastReadChat: ChatReadMark?
    /// The going calls of the person's chats, kept current by the call feed.
    private(set) var callBook = ChatCallBook()
    /// Whether a media host is alive. False hides the call buttons.
    private(set) var isChatCallAvailable = false
    /// The most people a call holds, from the server.
    private(set) var callMaximumPersonCount = ChatCallRules.maximumParticipants
    private var callFeedTask: Task<Void, Never>?
    /// Told when a ring on this account stopped, such as a call answered on another device.
    var onRingStopped: ((String) -> Void)?
    /// A ticket the Tickets tab should open, from a notification.
    var ticketToOpen: String?
    /// The feedback sheet a screenshot opened, nil while none is up.
    var feedbackRequest: FeedbackRequest?
    /// Set when a notification asks More to show the Automations screen.
    var automationsRequested = false
    var isShowingNotifications = false
    /// Entries in the inbox not read yet.
    private(set) var unreadCount = 0
    /// Counts up whenever the server says a notification was created, so an open inbox reads again.
    private(set) var notificationRevision = 0
    /// Whether the notification feed is up. While it is not, the lists are polled.
    private(set) var isNotificationFeedLive = false
    private var notificationFeedTask: Task<Void, Never>?
    /// A screen More should open at once, for a place that is not on the tab bar.
    var moreScreenToOpen: MoreDestination?
    /// A goal to show in More, from a notification.
    var goalToOpen: String?
    /// Set when a notification about an incident asks More to show the incidents.
    var incidentsRequested = false
    let onError: @MainActor (Error) -> Void
    /// What this account's screens loaded, so going back to one shows it at once. It goes with the session at sign-out or when another account takes over.
    let cache = ResponseCache()
    /// This account's pictures: fetched through its connection, kept on disk, and decoded images held for the session.
    let avatars: AvatarStore
    let avatarImages = AvatarImageMemory()
    /// Every camera the person can see, for the Surveillance wall.
    let surveillance: SurveillanceModel
    private let tabBarStore = TabBarStore()
    /// The sections the person chose for the tab bar, or nil while they never did.
    private(set) var savedTabBar: [String]?
    private var siteModels: [String: SiteModel] = [:]
    private var ticketModels: [String: TicketsModel] = [:]

    init(account: Account, connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.account = account
        self.connection = connection
        self.onError = onError
        self.readAloud = ReadAloudController(connection: connection)
        let directory = Self.avatarDirectory(accountKey: account.accountKey)
        self.avatars = AvatarStore(connection: connection, directory: directory)
        self.surveillance = SurveillanceModel(connection: connection, cache: cache, accountKey: account.accountKey)
        self.savedTabBar = tabBarStore.load(accountKey: account.accountKey)
        // The screenshot of Surveillance as a tab is taken for someone who chose it, since the default bar no longer has it.
        if DemoOptions.screen == "surveillance-tab" || DemoOptions.screen == "surveillance-many" || DemoOptions.screen == "surveillance-many-scrolled" { savedTabBar = [AppSection.site.rawValue, AppSection.surveillance.rawValue] }
    }

    /// The sections on the tab bar, More last, for what the person may use now.
    var tabSections: [AppSection] {
        TabBar.tabs(saved: savedTabBar, persona: persona, hasCameras: surveillance.hasCameras)
    }

    /// The sections the person may put on the bar.
    var choosableSections: [AppSection] {
        TabBar.choosable(persona: persona, hasCameras: surveillance.hasCameras)
    }

    /// Saves the sections of the bar. Nil brings the defaults back.
    func setTabBar(_ sections: [AppSection]?) {
        savedTabBar = sections?.map(\.rawValue)
        tabBarStore.save(savedTabBar, accountKey: account.accountKey)
    }

    /// Where an account's pictures are kept on disk.
    static func avatarDirectory(accountKey: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("avatars", isDirectory: true)
            .appendingPathComponent(accountKey.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined(), isDirectory: true)
    }

    /// A site screen's model lives as long as the session, so a push and a pop, or a switch of tabs, keeps its data.
    func siteModel(for organizationId: String?, siteId: String? = nil, cellId: String? = nil) -> SiteModel {
        let key = SiteModel.sessionKey(organizationId: organizationId, siteId: siteId, cellId: cellId)
        if let existing = siteModels[key] { return existing }
        let model = SiteModel(connection: connection, organizationId: organizationId, pinnedSiteId: siteId, cellId: cellId, cache: cache, accountKey: account.accountKey, onError: onError)
        model.viewerIsMujinUser = isStaff
        model.offersSiteExclusion = capabilities.offersSiteExclusion
        model.offersTelemetrySource = capabilities.offersTelemetrySource
        model.viewerPermissions = profile?.me.permissions ?? []
        model.viewerOrganizationId = self.organizationId
        siteModels[key] = model
        return model
    }

    func existingSiteModel(key: String) -> SiteModel? { siteModels[key] }

    func ticketsModel(for organizationId: String?) -> TicketsModel {
        let key = organizationId ?? ""
        if let existing = ticketModels[key] { return existing }
        let model = TicketsModel(connection: connection, organizationId: organizationId, includesPortalFeedbackFlag: capabilities.offersPortalFeedback, cache: cache, accountKey: account.accountKey, onError: onError)
        ticketModels[key] = model
        return model
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
    /// Every site a Mujin user can see, with the organizations' names, for the Sites tab and the site switcher.
    private(set) var staffSites = StaffSitesSnapshot()
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

    /// Loads every visible site (Mujin users only), showing what was held at once and reading again when it is old or `force` is set.
    func loadStaffSites(force: Bool = false) async throws {
        guard isStaff else { return }
        let key = CacheKey(accountKey: account.accountKey, name: "staffSites")
        try await cache.load(key, force: force, show: { (held: StaffSitesSnapshot) in
            staffSites = held
        }, fetch: { [connection] in
            async let sites = connection.allSites()
            async let organizations = connection.organizations()
            var loaded = StaffSitesSnapshot()
            loaded.sites = try await sites
            loaded.organizationNames = Dictionary(
                ((try? await organizations) ?? []).map { ($0.id, $0.name ?? "") }, uniquingKeysWith: { first, _ in first })
            return loaded
        })
    }

    /// A chat was read to its end. The lists update from this, not from a new read, which a replica could answer with the old count.
    func noteChatRead(conversationId: String) {
        lastReadChat = ChatReadMark(conversationId: conversationId)
        // The server marks the chat's notifications read with it. A replica answers a moment behind that.
        Task {
            try? await Task.sleep(for: .seconds(2))
            await refreshUnreadCount()
        }
    }

    /// The count a chat list worked out after clearing a row.
    func setChatUnreadCount(_ count: Int) {
        chatUnreadCount = count
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

    /// Keeps the going calls current through OnChatCallEvent, which does not replay what happened while it was down: every
    /// reconnect reads the calls again.
    func startCallFeed(socketFactory: @escaping FeedSocketFactory) {
        guard callFeedTask == nil, capabilities.offersChatCalls else { return }
        callFeedTask = Task { [weak self] in
            guard let self else { return }
            for await update in ChatCallFeed.events(connection: connection, socketFactory: socketFactory) {
                switch update {
                case .connected:
                    await refreshCalls()
                case .event(let event):
                    switch callBook.apply(event, userId: userId) {
                    case .stopped(let callId): onRingStopped?(callId)
                    case .refetch(let callId):
                        if let call = try? await connection.chatCall(id: callId) {
                            callBook.apply(ChatCallEvent(eventType: "refetched", callId: call.id, call: call), userId: userId)
                        }
                    case .ringing, .none: break
                    }
                case .signedOut:
                    onError(PortalError.signedOut)
                default:
                    break
                }
            }
        }
    }

    func stopCallFeed() {
        callFeedTask?.cancel()
        callFeedTask = nil
    }

    func refreshCalls() async {
        guard capabilities.offersChatCalls else { return }
        isChatCallAvailable = await connection.isChatCallAvailable()
        callMaximumPersonCount = await connection.chatCallMaximumPersonCount()
        if let calls = try? await connection.goingChatCalls() { callBook.replaceAll(calls) }
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
            selectedSection = .assistant
        case .conversationThread(let id, let threadRootMessageId):
            threadToOpen = ThreadToOpen(conversationId: id, threadRootMessageId: threadRootMessageId)
            conversationToOpen = id
            selectedSection = .assistant
        case .chat(let conversationId):
            chatToOpen = conversationId
            selectedSection = .assistant
        case .chatThread(let conversationId, let threadRootMessageId):
            threadToOpen = ThreadToOpen(conversationId: conversationId, threadRootMessageId: threadRootMessageId)
            chatToOpen = conversationId
            selectedSection = .assistant
        case .goal(let id):
            goalToOpen = id
            selectedSection = .more
        case .ticket(let id):
            ticketToOpen = id
            selectedSection = tabSections.contains(.tickets) ? .tickets : .more
        case .automations:
            automationsRequested = true
            selectedSection = .more
        case .notifications:
            isShowingNotifications = true
        }
    }

    /// Opens a link to a message of a chat: the person's own conversation of it, in the thread the message is in when it is in one.
    func openChatMessage(chatId: String, messageId: String) async {
        do {
            let conversationId = try await connection.openChatMessage(chatId: chatId, messageId: messageId)
            let root = await connection.messageThreadRoot(conversationId: conversationId, messageId: messageId)
            messageToFocus = MessageFocus(conversationId: conversationId, messageId: messageId, threadRootMessageId: root)
            if let root {
                open(.chatThread(conversationId: conversationId, threadRootMessageId: root))
            } else {
                open(.chat(conversationId: conversationId))
            }
        } catch {
            linkNotice = String(localized: "That message could not be found.")
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

    /// The resource an Ask button named, kept until the main chat shows it.
    var referenceHandoff = ReferenceHandoff()
    /// The id of the main chat once the list or an Ask button has seen it.
    private(set) var knownMainConversationId: String?
    /// Counts the times the person chose another main chat, which the list reads again for.
    private(set) var mainChatRevision = 0

    func noteMainChat(conversationId: String) {
        knownMainConversationId = conversationId
        mainChatRevision += 1
    }

    /// A new message the person asked for from a screen: its reference or its words are held here, and
    /// nothing exists on the server until the first send.
    struct ComposeRequest: Identifiable {
        let id = UUID()
        var viewing: Viewing?
        var subject: String?
        var draft = ""
    }

    var composeRequest: ComposeRequest?

    /// Opens a new message about the screen the person is looking at. The resource is a reference above the
    /// composer, not text in it; the conversation is made when the question is sent.
    func beginAsk(about viewing: Viewing, subject: String) async {
        if await openMainChat(about: viewing, subject: subject) { return }
        composeRequest = ComposeRequest(viewing: viewing, subject: subject)
        selectedSection = .assistant
    }

    /// Opens the person's main chat, made on first use, with the reference waiting above its prompt box.
    /// False when the organization has no main agent or the server did not answer: the caller falls back to a new message.
    @discardableResult
    func openMainChat(about viewing: Viewing? = nil, subject: String? = nil) async -> Bool {
        do {
            let main = try await connection.ensureMainConversation()
            knownMainConversationId = main.id
            if let viewing { referenceHandoff.set(conversationId: main.id, viewing: viewing, subject: subject ?? viewing.label ?? viewing.id) }
            conversationToOpen = main.id
            selectedSection = .assistant
            return true
        } catch {
            return false
        }
    }

    /// Opens a new message with `text` waiting in the composer. Nothing is sent.
    func beginDraft(_ text: String) async {
        composeRequest = ComposeRequest(draft: text)
        selectedSection = .assistant
    }

    func load() async {
        do {
            async let loadedProfile = connection.profile()
            async let loadedCapabilities = connection.capabilities()
            let (newProfile, newCapabilities) = try await (loadedProfile, loadedCapabilities)
            profile = newProfile
            capabilities = newCapabilities
            // Active alarms are listed by level where the server does, and all together where it does not.
            AlarmLevelPreference.shared.isAvailable = newCapabilities.offersSiteExclusion
            // A server with voice messages or calls takes their fields of a chat message; an older one refuses them.
            await connection.setChatMedia(hasVoice: newCapabilities.offersVoiceMessages, hasCalls: newCapabilities.offersChatCalls)
            // A server with message threads takes their fields and arguments; an older one refuses them.
            await connection.setMessageThreads(newCapabilities.offersMessageThreads)
            await connection.setInternalNotes(newCapabilities.offersInternalNotes)
            await connection.setChatReferences(newCapabilities.offersChatReferences)
            await connection.setForegroundOnlyLists(newCapabilities.offersForegroundOnlyLists)
            await connection.setOnBehalfOfStaff(newCapabilities.offersOnBehalfOfStaff)
            // Asked only of a server whose schema has the fields; an older one has neither feature.
            voiceAvailability = await connection.voiceAvailability(capabilities: newCapabilities)
            // The first screen needs none of what follows, so a slow network does not hold it back.
            phase = .loaded
            await refreshCalls()
            await refreshWaiting()
            await loadPlaces()
        } catch {
            onError(error)
            if profile == nil { phase = .failed(error.userMessage) }
        }
    }
}

/// DemoOptions are the choices a screenshot run makes through the environment.
enum DemoOptions {
    private static let environment = ProcessInfo.processInfo.environment

    /// The raw screen name, such as `conversation:conversation02` or `section:tickets`.
    static var screen: String? { environment["PORTAL_DEMO_SCREEN"] }

    /// Whether a demo run turns the iPad to landscape, from `PORTAL_DEMO_LAYOUT` naming `landscape`.
    static var isLandscape: Bool { environment["PORTAL_DEMO_LAYOUT"]?.contains("landscape") == true }

    /// Whether a demo run hides the list beside a conversation, from `PORTAL_DEMO_LAYOUT` naming `list-hidden`.
    static var isListHidden: Bool { environment["PORTAL_DEMO_LAYOUT"]?.contains("list-hidden") == true }

    /// The update a demo run offers, from `PORTAL_DEMO_UPDATE` as `<version>:<build>`, or on its own screens.
    static var update: AppUpdate? {
        if let text = environment["PORTAL_DEMO_UPDATE"] {
            let parts = text.split(separator: ":")
            guard parts.count == 2, let build = Int(parts[1]) else { return nil }
            return AppUpdate(channel: .testFlight, version: String(parts[0]), build: build)
        }
        switch screen {
        case "update-available", "settings-update": return AppUpdate(channel: .testFlight, version: "1.0", build: 310)
        case "update-available-store": return AppUpdate(channel: .appStore, version: "1.1")
        default: return nil
        }
    }

    /// The tab to open on, from `section:<name>`.
    static var section: AppSection? {
        guard let screen else { return nil }
        if SearchDemo.owns(screen) { return .search }
        if FeedbackDemo.owns(screen) { return FeedbackDemo.section(for: screen) }
        if SiteViewDemo.owns(screen) { return SiteViewDemo.section }
        if screen.hasPrefix("more-") { return .more }
        if screen.hasPrefix("update-available") { return .assistant }
        if screen.hasPrefix("section:") { return AppSection(rawValue: String(screen.dropFirst("section:".count))) }
        if AccountDemo.owns(screen) || PlatformDemo.owns(screen) { return .more }
        // Screens that live under More.
        if ["automations", "notifications", "about", "settings-update", "settings", "goal", "ideas", "knowledge", "memory-page", "dreams", "assistant-settings", "release", "incidents", "release-image", "accounts", "tab-bar-edit"].contains(where: { screen.hasPrefix($0) }) { return .more }
        if screen.hasPrefix("ticket") || screen.hasPrefix("attachment-viewer") { return .tickets }
        if screen.hasPrefix("chat") || screen.hasPrefix("thread-") { return .chats }
        if screen.hasPrefix("site-staff") || screen == "sites-staff" || screen == "surveillance-staff" { return .site }
        if screen == "surveillance" { return .more }
        if screen == "surveillance-tab" || screen == "surveillance-many" || screen == "surveillance-many-scrolled" { return .surveillance }
        if screen.hasPrefix("site") || screen.hasPrefix("cell") || screen.hasPrefix("incident") || screen.hasPrefix("controller") || screen.hasPrefix("virtual-controller") || screen.hasPrefix("camera") { return .site }
        return nil
    }

    /// The screen under More a demo run opens on.
    static var morePath: [MoreDestination] {
        switch screen ?? "" {
        case let name where name.hasPrefix("automations"): [.automations]
        case "about": [.about]
        case "settings", "settings-update", "accounts", "feedback-form", "feedback-form-open": [.settings]
        case "feedback-list", "feedback-list-empty", "feedback-list-error": [.settings, .myFeedback]
        case "tab-bar-edit": [.settings, .tabBarEditor]
        case "goals": [.goals]
        case "goal": [.goals, .goal("goal01")]
        case "ideas": [.ideas]
        case "knowledge": [.knowledge]
        case "memory-page": [.knowledge, .memoryPage(MemoryPageReference(pageId: "page01", factNumber: 2))]
        case "dreams": [.dreams]
        case "incidents": [.incidents]
        case "assistant-settings": [.assistantSettings]
        case "releases", "release-tap": [.releases]
        case "surveillance": [.surveillance]
        case "release", "release-menu": [.releases, .release("release01")]
        case "release-image": [.releases, .release("release01"), .releaseImage("image01")]
        default:
            AccountDemo.owns(screen ?? "") ? AccountDemo.morePath(screen ?? "") : PlatformDemo.morePath(screen ?? "")
        }
    }

    /// The row of More a screenshot run scrolls to, from `more-platform` or `more-surveillance`.
    static var moreRowToShow: String? {
        switch screen {
        case "more-platform": "platformSettingsRow"
        case "more-surveillance": "surveillanceRow"
        default: nil
        }
    }

    /// Whether the demo person works for the administrator organization.
    static var isStaff: Bool { environment["PORTAL_DEMO_PERSONA"] == "staff" }
}

/// ChatReadMark says a chat was read to its end. Each is new, so reading the same chat again is seen as a change.
struct ChatReadMark: Equatable {
    let conversationId: String
    let id = UUID()
}

/// MessageFocus is the message a link points at, and the thread it is in when it is in one.
struct MessageFocus: Equatable {
    let conversationId: String
    let messageId: String
    let threadRootMessageId: String?
}

/// ThreadToOpen is a thread a notification asked for: the conversation it is in and the message it hangs from.
struct ThreadToOpen: Equatable {
    let conversationId: String
    let threadRootMessageId: String
}
