import Foundation
import Observation
import PortalKit

/// ChatListModel loads the person's chats.
@MainActor
@Observable
final class ChatListModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var chats: [ConversationSummary] = []
    private(set) var searchText = ""

    init(connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.onError = onError
    }

    var unreadCount: Int { chats.reduce(0) { $0 + ($1.chat?.unreadCount ?? 0) } }

    func search(_ text: String) async {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await load()
    }

    func load() async {
        do {
            chats = try await connection.chats(search: searchText)
            phase = .loaded
        } catch {
            onError(error)
            if chats.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

/// ChatModel is one open chat: the room's messages, kept current by the
/// conversation's feed, and what the person does in it. The feed stays open
/// only while the chat is on screen, which is how the server knows the
/// person is looking and sends no notification for it.
@MainActor
@Observable
final class ChatModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let conversationId: String
    let currentUserId: String
    let connection: Connection
    let socketFactory: FeedSocketFactory
    let onError: @MainActor (Error) -> Void

    private(set) var phase = Phase.loading
    private(set) var chatId: String?
    private(set) var room: ChatRoom?
    private(set) var timeline = ChatTimeline()
    private(set) var window = MessageWindow()
    private(set) var previews: [String: [LinkPreviewCard]] = [:]
    private(set) var isFeedLive = false
    private(set) var isLoadingEarlier = false
    /// The agents the chat's organization may use, the main one first.
    private(set) var agents: [Agent] = []
    /// The people and agents the person picked from the @ list for the draft.
    private(set) var pickedMentions: [MentionCandidate] = []
    /// Whether the server takes structured mentions; otherwise the name text carries them.
    var offersStructuredMentions = false
    /// Whether a turn of the assistant the person started is running.
    private(set) var isOwnTurnRunning = false
    private(set) var questions: [QuestionCard] = []
    private(set) var approvals: [ApprovalCard] = []
    /// A clock the typing lines read, so they fade out by themselves.
    private(set) var now = Date()
    var replyTarget: ChatMessage?
    var editTarget: ChatMessage?
    var actionError: String?

    private var feedTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var typingThrottle = TypingThrottle()
    private var lastMarkedMessageId: String?
    private var previewAskedIds: Set<String> = []

    init(
        conversationId: String, chatId: String?, currentUserId: String, connection: Connection, socketFactory: @escaping FeedSocketFactory,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.conversationId = conversationId
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.connection = connection
        self.socketFactory = socketFactory
        self.onError = onError
    }

    var title: String { room?.title ?? String(localized: "Chat") }
    var canWrite: Bool { room?.canWrite ?? true }
    var isAdmin: Bool { room?.isReaderAdmin == true }

    /// The people and agents the @ list offers for what the draft ends with, or none when it is closed.
    func mentionSuggestions(for draft: String) -> [MentionCandidate] {
        guard canWrite, let query = Mentions.query(in: draft) else { return [] }
        return Mentions.candidates(agents: agents, members: room?.members ?? [], query: query, excludingUserId: currentUserId)
    }

    func pick(_ candidate: MentionCandidate) {
        if !pickedMentions.contains(where: { $0.id == candidate.id }) { pickedMentions.append(candidate) }
    }

    /// The agent the draft or the reply addresses, when there is one.
    func addressedAgent(in draft: String) -> Agent? {
        if let agent = ChatRules.addressedAgent(in: draft, agents: agents) { return agent }
        if let reply = replyTarget, reply.isAssistant {
            return agents.first { $0.name == reply.authorName } ?? agents.first { $0.isMain == true } ?? agents.first
        }
        return nil
    }

    /// The names that read as chips in a sent message.
    var mentionNames: [String] { agents.compactMap(\.name) + (room?.members ?? []).map(\.shownName) }

    func member(_ userId: String?) -> ChatMember? { room?.members?.first { $0.userId == userId } }

    var peopleTyping: [String] { timeline.peopleTyping(now: now, excluding: currentUserId) }
    var isAssistantAnswering: Bool { timeline.isAssistantAnswering(now: now, isOwnTurnRunning: isOwnTurnRunning) }

    func start() {
        guard feedTask == nil else { return }
        feedTask = Task { [weak self] in
            guard let self else { return }
            await self.reload()
            let updates = ConversationFeed.updates(connection: connection, conversationId: conversationId, socketFactory: socketFactory)
            for await update in updates { await self.handle(update) }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.now = Date()
            }
        }
    }

    func stop() {
        feedTask?.cancel()
        feedTask = nil
        clockTask?.cancel()
        clockTask = nil
        previewTask?.cancel()
        previewTask = nil
    }

    private func handle(_ update: FeedUpdate) async {
        switch update {
        case .connected:
            isFeedLive = true
            await reload()
        case .event(let event):
            await handle(event)
        case .reconnecting:
            isFeedLive = false
        case .signedOut:
            isFeedLive = false
            onError(PortalError.signedOut)
        }
    }

    private func handle(_ event: ConversationEvent) async {
        if event.chat != nil {
            switch timeline.apply(event) {
            case .refetchChat: await reloadRoom()
            case .refetchPreviews(let id): await loadPreviews([id], force: true)
            case .received(let id):
                await markRead()
                await loadPreviews([id])
            case .none: break
            }
            return
        }
        switch event.kind {
        case .textDelta, .toolCall, .modelSwitch: isOwnTurnRunning = true
        case .runComplete, .runError:
            isOwnTurnRunning = false
            await reloadCards()
        case .pendingQuestion, .pendingApproval: await reloadCards()
        default: break
        }
    }

    func reloadRoom() async {
        guard let chatId else { return }
        if let loaded = try? await connection.chat(id: chatId) { room = loaded }
    }

    private func reloadCards() async {
        if let cards = try? await connection.waitingCards(conversationId: conversationId) {
            questions = cards.questions
            approvals = cards.approvals
        }
    }

    func reload() async {
        do {
            if chatId == nil { chatId = try await connection.conversation(id: conversationId).chatId }
            guard let chatId else { throw PortalError.refused("This is not a chat.") }
            async let loadedRoom = connection.chat(id: chatId)
            async let rows = connection.messages(conversationId: conversationId, latestCount: window.reloadCount)
            async let total = try? connection.messageCount(conversationId: conversationId)
            let (newRoom, newRows) = try await (loadedRoom, rows)
            room = newRoom
            window.replace(with: newRows, totalCount: await total)
            timeline.load(window.messages)
            var marks: [String: String] = [:]
            for member in newRoom.members ?? [] {
                if let mark = member.lastReadMessageId, !mark.isEmpty { marks[member.userId] = mark }
            }
            timeline.setReadMarks(marks)
            phase = .loaded
            await reloadCards()
            await markRead()
            if agents.isEmpty, let loaded = try? await connection.authorizedAgents(organizationId: newRoom.organizationId) { agents = loaded }
            await loadPreviews(timeline.messages.suffix(30).map(\.id))
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    func loadEarlier() async {
        guard let first = window.firstMessageId, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let page = try await connection.messages(conversationId: conversationId, latestCount: MessageWindow.pageSize, beforeMessageId: first)
            window.prepend(page)
            timeline.load(window.messages)
            await loadPreviews(page.map(\.id))
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    // MARK: read marks and typing

    /// Tells the room the person has read to the end. The mark only moves forward.
    func markRead() async {
        guard let chatId, let last = timeline.messages.last?.id, last != lastMarkedMessageId, last != room?.readerLastReadMessageId else { return }
        lastMarkedMessageId = last
        try? await connection.markChatRead(chatId: chatId, messageId: last)
    }

    /// Called as the person types; signals at most every three seconds.
    func noteTyping() {
        guard let chatId, typingThrottle.shouldSend() else { return }
        let connection = connection
        Task { try? await connection.setChatTyping(chatId: chatId) }
    }

    // MARK: sending

    /// Says something to the room, or saves an edit.
    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= ChatRules.maximumMessageCharacters else {
            actionError = String(localized: "A message can be up to \(ChatRules.maximumMessageCharacters) characters.")
            return false
        }
        actionError = nil
        do {
            if let editTarget, let chatId {
                try await connection.editChatMessage(chatId: chatId, messageId: editTarget.id, text: trimmed)
                self.editTarget = nil
                await reload()
                return true
            }
            let mentions = offersStructuredMentions ? Mentions.ranges(of: pickedMentions, in: trimmed) : []
            let sent = try await connection.sendChatMessage(
                conversationId: conversationId, text: trimmed, replyToMessageId: replyTarget?.id, mentions: mentions)
            replyTarget = nil
            pickedMentions = []
            if let message = sent.message { timeline.upsert(message) }
            if !sent.runId.isEmpty { isOwnTurnRunning = true }
            await markRead()
            return true
        } catch {
            actionError = error.userMessage
            onError(error)
            return false
        }
    }

    func canEdit(_ message: ChatMessage) -> Bool { !message.isAssistant && !message.isDeleted && message.authorUserId == currentUserId && canWrite }
    func canDelete(_ message: ChatMessage) -> Bool { !message.isDeleted && (message.authorUserId == currentUserId || (isAdmin && room?.isGroup == true)) && canWrite }

    func delete(_ message: ChatMessage) async {
        guard let chatId else { return }
        do {
            try await connection.deleteChatMessage(chatId: chatId, messageId: message.id)
            await reload()
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    func react(messageId: String, emoji: String) async {
        let chosen = Reactions.emojiToSend(chosen: emoji, in: timeline.reactions(for: messageId), currentUserId: currentUserId)
        do {
            let reactions = try await connection.react(conversationId: conversationId, messageId: messageId, emoji: chosen)
            timeline.setReactions(reactions, for: messageId)
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    func answer(_ card: QuestionCard, with text: String) async {
        do {
            try await connection.answerQuestion(id: card.id, answer: text)
            questions.removeAll { $0.id == card.id }
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    func decide(_ card: ApprovalCard, isApproved: Bool) async {
        do {
            try await connection.resolveToolApproval(id: card.id, isApproved: isApproved)
            approvals.removeAll { $0.id == card.id }
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    // MARK: link previews

    /// Asks for the cards under messages that hold a link; while any link is
    /// still being fetched it asks again every three seconds, up to 20 times.
    func loadPreviews(_ ids: [String], force: Bool = false) async {
        let wanted = timeline.messages.filter { message in
            ids.contains(message.id) && !message.isDeleted && !message.hasPreviewsRemoved && LinkPreviewRules.mayHoldLink(message.text)
                && (force || !previewAskedIds.contains(message.id))
        }.map(\.id)
        guard !wanted.isEmpty else { return }
        previewAskedIds.formUnion(wanted)
        let firstPending = await fetchPreviews(wanted)
        guard !firstPending.isEmpty else { return }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            var pending = firstPending
            var attempts = 0
            while !pending.isEmpty, attempts < LinkPreviewRules.maximumRetries, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(LinkPreviewRules.pendingRetryInterval * 1_000_000_000))
                if Task.isCancelled { return }
                attempts += 1
                guard let self else { return }
                pending = await self.fetchPreviews(pending)
            }
        }
    }

    /// Reads the previews of messages and returns those still pending.
    private func fetchPreviews(_ ids: [String]) async -> [String] {
        guard let rows = try? await connection.linkPreviews(conversationId: conversationId, messageIds: ids) else { return [] }
        var pending: [String] = []
        for row in rows {
            previews[row.messageId] = row.linkPreviews ?? []
            if row.isPending == true { pending.append(row.messageId) }
        }
        return pending
    }

    func removePreviews(of message: ChatMessage) async {
        do {
            try await connection.removeLinkPreviews(conversationId: conversationId, messageId: message.id)
            previews[message.id] = []
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    // MARK: members and settings

    func apply(_ change: () async throws -> ChatRoom) async {
        do {
            room = try await change()
            actionError = nil
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }
}
