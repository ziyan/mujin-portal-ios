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

    /// The person read a chat to its end: its row shows that at once, ahead of the next read of the list.
    func markRead(id: String) {
        chats = ConversationListUpdate.markedRead(chats, id: id)
    }

    func search(_ text: String) async {
        searchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await load()
    }

    /// Reads the list after a chat was started, again for a moment if a replica is behind and does not list it yet.
    func didStart(conversationId: String) async {
        for attempt in 0..<4 {
            await load()
            if chats.contains(where: { $0.id == conversationId }) { return }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
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
/// person is looking and sends no notification for it. With a `threadRootMessageId` it is one thread of the chat instead:
/// the message it hangs from and its replies, with its own composer.
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
    /// The thread this model shows, by the id of the message it hangs from. Nil for the main history.
    private(set) var threadRootMessageId: String?
    /// Whether the server has message threads. Without them every message is read, as before.
    let offersMessageThreads: Bool

    private(set) var phase = Phase.loading
    private(set) var chatId: String?
    private(set) var room: ChatRoom?
    private(set) var timeline: ChatTimeline
    private(set) var window = MessageWindow()
    /// The cards under messages, asked for and polled by the loader the assistant conversations share.
    let linkPreviews: LinkPreviewLoader
    var previews: [String: [LinkPreviewCard]] { linkPreviews.previews }
    /// Whether the live feed has dropped and not come back. The first connection of an opened chat does not count.
    private(set) var isFeedLost = false
    private(set) var isLoadingEarlier = false
    /// The agents the chat's organization may use, the main one first.
    private(set) var agents: [Agent] = []
    /// The people and agents the person picked from the @ list for the draft.
    private(set) var pickedMentions: [MentionCandidate] = []
    /// Everyone with access to the site of a site chat.
    private(set) var sitePeople: [ChatMember] = []
    /// Whether the server takes structured mentions; otherwise the name text carries them.
    var offersStructuredMentions = false
    /// Whether the server has internal notes. Set by the screen from the server's capabilities.
    var offersInternalNotes = false
    /// The person's own choice on the composer's internal-note lock.
    var isInternalNoteChosen = false
    /// Whether the person may write an internal note here: staff, in a chat a customer reads.
    var canPostInternal: Bool { offersInternalNotes && room?.canPostInternal == true }
    /// The root of the thread this screen shows, when it is loaded.
    var threadRootMessage: ChatMessage? {
        guard let root = ThreadRouting.normalized(threadRootMessageId) else { return nil }
        return timeline.messages.first { $0.id == root }
    }
    /// Whether the lock is held on whatever the person picks: a reply to an internal note, or in an internal thread.
    var isInternalNoteForced: Bool { canPostInternal && InternalNoteRules.isForcedOn(threadRoot: threadRootMessage, replyTo: replyTarget) }
    /// Whether the next send is an internal note.
    var isInternalNote: Bool { canPostInternal && (isInternalNoteForced || isInternalNoteChosen) }
    /// Whether a turn of the assistant the person started is running.
    private(set) var isOwnTurnRunning = false
    /// The thread the assistant's turn at work answers in, when an event or a send said; nil while it is unknown.
    private(set) var workingThreadRootMessageId: String?
    /// Whether a voice message is going up.
    private(set) var isSendingVoice = false
    private(set) var questions: [QuestionCard] = []
    private(set) var approvals: [ApprovalCard] = []
    /// A clock the typing lines read, so they fade out by themselves.
    private(set) var now = Date()
    var replyTarget: ChatMessage?
    var editTarget: ChatMessage?
    var actionError: String?

    private var feedTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var typingThrottle = TypingThrottle()
    private var lastMarkedMessageId: String?
    /// Told the conversation's id when the person has read to the end, so the lists and the tab's count can say so.
    var onRead: (@MainActor (String) -> Void)?

    init(
        conversationId: String, chatId: String?, currentUserId: String, connection: Connection, socketFactory: @escaping FeedSocketFactory,
        threadRootMessageId: String? = nil, offersMessageThreads: Bool = false, onError: @escaping @MainActor (Error) -> Void
    ) {
        self.threadRootMessageId = ThreadRouting.normalized(threadRootMessageId)
        self.offersMessageThreads = offersMessageThreads
        self.timeline = ChatTimeline(threadRootMessageId: threadRootMessageId)
        self.conversationId = conversationId
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.connection = connection
        self.socketFactory = socketFactory
        self.onError = onError
        self.linkPreviews = LinkPreviewLoader(connection: connection, conversationId: conversationId)
    }

    var isThread: Bool { threadRootMessageId != nil }
    /// Whether this screen is the main history of a server with threads: a tap on a message of a thread opens it.
    var canOpenThreads: Bool { offersMessageThreads && !isThread }
    /// The thread a message just sent in the main history started, for the screen to open; the screen clears it once it has.
    var threadStartedBySend: String?
    /// Whether the assistant's turn at work is answering where this screen looks: in this thread, or in no thread on the main history.
    var isAssistantWorkingHere: Bool {
        ThreadRouting.isViewRunning(
            isRunning: isOwnTurnRunning, workingThreadRootMessageId: workingThreadRootMessageId, viewThreadRootMessageId: threadRootMessageId)
    }

    var title: String { room?.title ?? String(localized: "Chat") }
    var canWrite: Bool { room?.canWrite ?? true }
    var isAdmin: Bool { room?.isReaderAdmin == true }
    /// A group takes people from its administrators; a direct chat from either person, and becomes a group.
    var canAddPeople: Bool {
        guard let room, room.canWrite, !room.isSite else { return false }
        return room.isGroup ? isAdmin : true
    }

    /// Who can be mentioned or called: the chat's members, and in a site chat everyone with access to the site, who join when picked.
    var reachablePeople: [ChatMember] {
        let members = room?.currentMembers ?? []
        guard room?.isSite == true else { return members }
        let joined = Set(members.map(\.userId))
        return members + sitePeople.filter { !joined.contains($0.userId) }
    }

    /// The people and agents the @ list offers for what the draft ends with, or none when it is closed.
    /// Whether the server has references, which the # picker finds. Set by the screen from the server's capabilities.
    var offersChatReferences = false
    /// What the # picker offers for the draft as typed now.
    private(set) var referenceCandidates: [ChatReferenceCandidate] = []
    private var referenceSearch: Task<Void, Never>?

    /// Looks up what the # at the end of the draft could name, a moment after the typing stops; nothing when the draft has no #.
    func searchReferences(for draft: String) {
        referenceSearch?.cancel()
        guard offersChatReferences, canWrite, let query = ChatReferences.pickerQuery(in: draft) else {
            referenceCandidates = []
            return
        }
        referenceSearch = Task { [connection, chatId] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let found = (try? await connection.searchChatReferences(query: query, chatId: chatId)) ?? []
            guard !Task.isCancelled else { return }
            referenceCandidates = found
        }
    }

    func clearReferenceCandidates() {
        referenceSearch?.cancel()
        referenceCandidates = []
    }

    func mentionSuggestions(for draft: String) -> [MentionCandidate] {
        guard canWrite, let query = Mentions.query(in: draft) else { return [] }
        return Mentions.candidates(agents: agents, members: reachablePeople, query: query, excludingUserId: currentUserId)
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
    var mentionNames: [String] { agents.compactMap(\.name) + reachablePeople.map(\.shownName) }

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
        linkPreviews.cancel()
    }

    private func handle(_ update: FeedUpdate) async {
        switch update {
        case .connected:
            isFeedLost = false
            await reload()
        case .event(let event):
            await handle(event)
        case .reconnecting:
            isFeedLost = true
        case .signedOut:
            isFeedLost = true
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
        if ThreadRouting.isRunContent(event) { workingThreadRootMessageId = ThreadRouting.workingThreadRootMessageId(of: event) }
        switch event.kind {
        case .textDelta, .toolCall, .modelSwitch: isOwnTurnRunning = true
        case .runComplete, .runError:
            isOwnTurnRunning = false
            workingThreadRootMessageId = nil
            await reloadCards()
        case .pendingQuestion, .pendingApproval: await reloadCards()
        default: break
        }
    }

    /// The demo's chat where the assistant has been asked and has not answered: its run is at work in the thread of that message.
    func stageDemoWorking(inThreadOf messageId: String) {
        isOwnTurnRunning = true
        workingThreadRootMessageId = messageId
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
            async let rows = connection.messages(
                conversationId: conversationId, latestCount: isThread ? ThreadRouting.threadMessageCount : window.reloadCount,
                threadRootMessageId: threadRootMessageId)
            // A thread is read whole, so it has no count of earlier messages.
            let shouldCountMessages = !isThread
            async let total: Int? = shouldCountMessages ? connection.messageCountOrNil(conversationId: conversationId) : nil
            let (newRoom, newRows) = try await (loadedRoom, rows)
            room = newRoom
            if newRoom.isSite, let people = try? await connection.siteChatPeople(chatId: chatId) {
                sitePeople = people.map {
                    ChatMember(
                        id: $0.userId, userId: $0.userId, userName: $0.userName, organizationId: $0.organizationId, organizationName: $0.organizationName,
                        isMujinUser: $0.isMujinUser)
                }
            }
            window.replace(with: newRows, totalCount: await total)
            timeline.load(window.messages)
            var marks: [String: String] = [:]
            for member in newRoom.members ?? [] {
                if let mark = member.lastReadMessageId, !mark.isEmpty { marks[member.userId] = mark }
            }
            timeline.setReadMarks(marks)
            // A thread whose newest message is an internal note opens with the lock on, once; the person can change it after.
            if isThread, phase != .loaded, canPostInternal { isInternalNoteChosen = InternalNoteRules.startsOn(threadMessages: timeline.messages) }
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
            let page = try await connection.messages(
                conversationId: conversationId, latestCount: MessageWindow.pageSize, beforeMessageId: first)
            window.prepend(page)
            timeline.load(window.messages)
            await loadPreviews(page.map(\.id))
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    // MARK: read marks and typing

    /// Tells the room the person has read to the end. The mark only moves forward. A thread leaves the mark to the main history
    /// under it, which lists every message.
    func markRead() async {
        guard !isThread, let chatId, let last = timeline.messages.last?.id else { return }
        if last != lastMarkedMessageId, last != room?.readerLastReadMessageId {
            lastMarkedMessageId = last
            try? await connection.markChatRead(chatId: chatId, messageId: last)
        }
        // Also when the server had the mark already: a list read earlier can still show the chat as unread.
        onRead?(conversationId)
    }

    /// Called as the person types; signals at most every three seconds.
    func noteTyping() {
        guard let chatId, typingThrottle.shouldSend() else { return }
        let connection = connection
        Task { try? await connection.setChatTyping(chatId: chatId) }
    }

    // MARK: sending

    /// Says something to the room, or saves an edit. Files in `attachments` go up first and the message names them as the web app does.
    func send(_ text: String, attachments: AttachmentDrafts? = nil) async -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFiles = editTarget == nil && !(attachments?.items.isEmpty ?? true)
        guard !trimmed.isEmpty || hasFiles else { return false }
        guard trimmed.count <= ChatRules.maximumMessageCharacters else {
            actionError = String(localized: "A message can be up to \(ChatRules.maximumMessageCharacters) characters.")
            return false
        }
        actionError = nil
        do {
            if hasFiles, let attachments {
                let files = try await attachments.upload(using: connection)
                if AttachmentLimits.chatMessageRefusal(text: trimmed, files: files) != nil {
                    actionError = String(localized: "A message can be up to \(ChatRules.maximumMessageCharacters) characters.")
                    return false
                }
                trimmed = SharePayload.assistantMessage(text: trimmed, files: files)
            }
            if let editTarget, let chatId {
                try await connection.editChatMessage(chatId: chatId, messageId: editTarget.id, text: trimmed)
                self.editTarget = nil
                await reload()
                return true
            }
            let mentions = offersStructuredMentions ? Mentions.ranges(of: pickedMentions, in: trimmed) : []
            let isNewThread = canOpenThreads && replyTarget == nil
            let sent = try await connection.sendChatMessage(
                conversationId: conversationId, text: trimmed,
                replyToMessageId: ThreadRouting.replyToMessageId(pickedMessageId: replyTarget?.id, viewThreadRootMessageId: threadRootMessageId),
                mentions: mentions, isInternal: isInternalNote)
            replyTarget = nil
            pickedMentions = []
            if hasFiles { attachments?.removeUploaded() }
            if let message = sent.message { timeline.upsert(message) }
            if isNewThread, let message = sent.message, ThreadRouting.normalized(message.threadRootMessageId) == nil { threadStartedBySend = message.id }
            if !sent.runId.isEmpty {
                isOwnTurnRunning = true
                // The assistant answers in a thread: the one the message is in, or a new one hanging from the message.
                workingThreadRootMessageId = ThreadRouting.normalized(sent.message?.threadRootMessageId) ?? (offersMessageThreads ? sent.message?.id : nil)
            }
            await markRead()
            await followThreadRoot()
            return true
        } catch {
            actionError = error.userMessage
            onError(error)
            return false
        }
    }

    /// An old message with no thread joins its question's thread on its first reply: the screen that was opened from it moves to the
    /// thread the server says it is in now.
    private func followThreadRoot() async {
        guard let openRoot = threadRootMessageId,
            let root = await connection.messageThreadRoot(conversationId: conversationId, messageId: openRoot), root != openRoot
        else { return }
        threadRootMessageId = root
        timeline = ChatTimeline(threadRootMessageId: root)
        await reload()
    }

    /// Uploads a finished recording and says it to the room as a voice message. The file is deleted afterwards.
    func sendVoice(_ recording: VoiceRecording) async {
        isSendingVoice = true
        actionError = nil
        defer {
            isSendingVoice = false
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        do {
            let data = try Data(contentsOf: recording.fileURL)
            let file = try await connection.uploadAttachment(data: data, filename: VoiceMessageRules.filename(at: Date()), contentType: VoiceMessageRules.contentType)
            let row = try await connection.sendChatVoiceMessage(
                conversationId: conversationId, attachmentId: file.id, durationMS: recording.durationMS, waveformLevels: recording.levels,
                replyToMessageId: ThreadRouting.replyToMessageId(pickedMessageId: replyTarget?.id, viewThreadRootMessageId: threadRootMessageId))
            replyTarget = nil
            if let row { timeline.upsert(row) }
            await markRead()
        } catch {
            actionError = error.userMessage
            onError(error)
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

    func loadPreviews(_ ids: [String], force: Bool = false) async {
        let candidates = timeline.messages.filter { ids.contains($0.id) && !$0.isDeleted && !$0.hasPreviewsRemoved }.map { (id: $0.id, text: $0.text) }
        await linkPreviews.load(candidates, force: force)
    }

    func removePreviews(of message: ChatMessage) async {
        do {
            try await linkPreviews.remove(messageId: message.id)
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
