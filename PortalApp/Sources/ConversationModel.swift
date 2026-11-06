import Foundation
import Observation
import PortalKit

/// ConversationModel is one open conversation: its transcript, kept current
/// by the subscription feed, and what the person does in it. With a `threadRootMessageId` it is one thread of the conversation
/// instead: the message it hangs from and its replies, with its own composer.
@MainActor
@Observable
final class ConversationModel {
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

    private(set) var transcript: Transcript
    /// The cards under messages that hold a link: asked for and polled the way a people chat does.
    let linkPreviews: LinkPreviewLoader
    private(set) var window = MessageWindow()
    private(set) var phase = Phase.loading
    private(set) var title: String?
    /// Told when the server gives the conversation another title, such as the one it writes after the first answer.
    var onTitleChanged: (@MainActor (String) -> Void)?
    private(set) var isMain = false
    /// Whether the live feed has dropped and not come back. The first connection of an opened conversation does not count.
    private(set) var isFeedLost = false
    private(set) var isLoadingEarlier = false
    /// Background work this conversation started that has not ended.
    private(set) var backgroundWork: [BackgroundWork] = []
    /// Questions the person set aside, so what they type goes out as a message.
    private(set) var dismissedQuestionIds: Set<String> = []
    /// The message the next send replies to, shown above the composer.
    var replyTarget: ReplyReference?
    /// The screen the next send asks about ("Ask about this"), shown above the composer.
    var viewingReference: (viewing: Viewing, subject: String)?
    /// Why the last send or answer failed, shown beside the composer.
    var actionError: String?
    /// Whose conversation this is, when the server said. The speak-first buttons are for its owner.
    private(set) var ownerUserId: String?
    /// What happened after "Not now" or "Stop these", in a line that replaces the buttons.
    private(set) var speakFirstOutcome: String?
    /// Told the assistant's answer as it streams in, for reading it aloud in a call.
    var onAssistantText: (@MainActor (_ messageId: String, _ text: String, _ isFinal: Bool) -> Void)?
    private var streamingAnswer: (id: String, text: String)?

    var isOwnConversation: Bool { ownerUserId == nil || ownerUserId == currentUserId }

    /// The latest pass that filed this conversation into memory and still has facts.
    private(set) var filingNote: MemoryFiling?

    private var feedTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?
    private var isTitleCustom = false
    /// Whether the summary, and so the server's own title, has been written already.
    private var hasSummary = false
    private var hasHeardTitleEvent = false
    private var cards: (questions: [QuestionCard], approvals: [ApprovalCard]) = ([], [])

    init(
        conversationId: String, currentUserId: String, connection: Connection, socketFactory: @escaping FeedSocketFactory,
        threadRootMessageId: String? = nil, offersMessageThreads: Bool = false, onError: @escaping @MainActor (Error) -> Void
    ) {
        self.threadRootMessageId = ThreadRouting.normalized(threadRootMessageId)
        self.offersMessageThreads = offersMessageThreads
        self.transcript = Transcript(threadRootMessageId: threadRootMessageId)
        self.conversationId = conversationId
        self.currentUserId = currentUserId
        self.connection = connection
        self.socketFactory = socketFactory
        self.onError = onError
        self.linkPreviews = LinkPreviewLoader(connection: connection, conversationId: conversationId)
    }

    var isRunning: Bool { transcript.isRunning }
    var isThread: Bool { threadRootMessageId != nil }
    /// Whether this screen is the main history of a server with threads: a tap on a message of a thread opens it.
    var canOpenThreads: Bool { offersMessageThreads && !isThread }
    /// Whether the run at work answers where this screen looks: in this thread, or in no thread on the main history.
    var isRunningHere: Bool { transcript.isRunningInView }

    /// A turn is running and nothing of the answer has shown yet: the last thing in the transcript is the person's own message.
    var isAwaitingFirstWords: Bool {
        guard isRunningHere, let last = transcript.entries.last(where: { entry in
            if case .note = entry { return false }
            return true
        }) else { return false }
        if case .user = last { return true }
        return false
    }

    /// The open question that typed text would answer.
    var activeQuestion: QuestionCard? { transcript.answerableQuestion(dismissedIds: dismissedQuestionIds) }

    func start() {
        guard feedTask == nil else { return }
        feedTask = Task { [weak self] in
            guard let self else { return }
            await self.reload()
            let updates = ConversationFeed.updates(connection: connection, conversationId: conversationId, socketFactory: socketFactory)
            for await update in updates {
                await self.handle(update)
            }
        }
        // Work in the background reports through the conversation's own
        // stream only when the assistant wakes, so progress is polled.
        pollTask = Task { [weak self] in
            var round = 0
            await self?.refreshFiling()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if !self.backgroundWork.isEmpty { await self.refreshBackgroundWork() }
                // Filing has no event: the note is read again about every 20 seconds.
                round += 1
                if round % 4 == 0 { await self.refreshFiling() }
            }
        }
    }

    func stop() {
        feedTask?.cancel()
        feedTask = nil
        pollTask?.cancel()
        pollTask = nil
        titleTask?.cancel()
        titleTask = nil
        linkPreviews.cancel()
    }

    private func handle(_ update: FeedUpdate) async {
        switch update {
        case .connected:
            isFeedLost = false
            // What was said while the feed was down is only in the history;
            // the server replays the running turn on this socket. Reactions
            // are never replayed, so older local changes give way to the history.
            transcript.dropLiveEntries()
            transcript.expireFoldedReactions(olderThan: 60)
            await reload()
        case .event(let event):
            transcript.apply(event)
            noteSpeech(event)
            if let announced = event.announcedTitle(for: conversationId) {
                hasHeardTitleEvent = true
                isTitleCustom = announced.isCustom
                applyTitle(announced.title)
            }
            switch event.kind {
            case .runComplete, .runError: await reload(isRunFinished: true)
            case .pendingQuestion, .pendingApproval: await reload()
            default: break
            }
        case .reconnecting:
            isFeedLost = true
        case .signedOut:
            isFeedLost = true
            onError(PortalError.signedOut)
        }
    }

    /// Passes the answer being written to a call that reads it aloud. A tool
    /// call, a card or the end of the turn ends the text written so far.
    private func noteSpeech(_ event: ConversationEvent) {
        guard let onAssistantText else { return }
        switch event.kind {
        case .textDelta:
            guard let id = event.textDelta?.messageId,
                case .assistant(_, let text, _)? = transcript.entries.first(where: { $0.id == "assistant:\(id)" })
            else { return }
            streamingAnswer = (id, text)
            onAssistantText(id, Transcript.visibleText(text), false)
        case .toolCall, .pendingQuestion, .pendingApproval, .runComplete, .runError:
            if let streamingAnswer { onAssistantText(streamingAnswer.id, Transcript.visibleText(streamingAnswer.text), true) }
            streamingAnswer = nil
        default:
            break
        }
    }

    /// Sends what was said in a call: an ordinary message marked as spoken,
    /// with what the person heard when they talked over the last answer.
    func sendVoice(_ text: String, interruptedAnswer: InterruptedAnswer?) async {
        actionError = nil
        if let question = activeQuestion {
            await answer(question, with: text)
            return
        }
        transcript.appendPendingUser(text, viewing: nil)
        do {
            try await connection.sendMessage(conversationId: conversationId, text: text, isVoice: true, interruptedAnswer: interruptedAnswer)
        } catch {
            transcript.removePendingUser(text)
            actionError = error.userMessage
            onError(error)
        }
    }

    /// Loads the persisted conversation and the questions and approvals still waiting.
    func reload(isRunFinished: Bool = false) async {
        do {
            async let summary = connection.conversation(id: conversationId)
            async let messages = connection.messages(
                conversationId: conversationId, latestCount: isThread ? ThreadRouting.threadMessageCount : window.reloadCount,
                threadRootMessageId: threadRootMessageId)
            async let waitingCards = connection.waitingCards(conversationId: conversationId)
            // A thread is read whole, so it has no count of earlier messages.
            let shouldCountMessages = !isThread
            async let total: Int? = shouldCountMessages ? connection.messageCountOrNil(conversationId: conversationId) : nil
            let (loadedSummary, loadedMessages, loadedCards) = try await (summary, messages, waitingCards)
            window.replace(with: loadedMessages, totalCount: await total)
            cards = loadedCards
            isTitleCustom = loadedSummary.isTitleCustom == true
            hasSummary = !(loadedSummary.summary ?? "").isEmpty
            applyTitle(loadedSummary.title)
            isMain = loadedSummary.isMain == true
            ownerUserId = loadedSummary.userId
            transcript.load(
                messages: window.messages, questions: cards.questions, approvals: cards.approvals,
                isRunning: !isRunFinished && (loadedSummary.isRunning || transcript.hasPendingUser))
            phase = .loaded
            if isRunFinished { watchForServerTitle() }
            await refreshBackgroundWork()
            await askForPreviews(window.messages.suffix(30))
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    /// A conversation keeps the title it has: a read that comes back without one, from a replica that is
    /// a moment behind, does not take it away.
    private func applyTitle(_ newTitle: String?) {
        guard let newTitle, !newTitle.isEmpty, newTitle != title else { return }
        title = newTitle
        onTitleChanged?(newTitle)
    }

    /// The server announces every title it writes as an event, so the title shows at once. This one read,
    /// ten seconds after the first turn ends, is for the case where no event came: the feed was down just
    /// then, or the server is older than the event. It is skipped once an event was heard, for a title the
    /// person set, and after the summary exists (later turns never retitle).
    private func watchForServerTitle() {
        guard !isTitleCustom, !hasSummary, titleTask == nil else { return }
        hasHeardTitleEvent = false
        titleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if !self.hasHeardTitleEvent, let read = try? await self.connection.conversation(id: self.conversationId) {
                self.isTitleCustom = read.isTitleCustom == true
                self.applyTitle(read.title)
            }
            self.titleTask = nil
        }
    }

    /// Asks the server for the link cards under messages that hold a link, as a people chat does.
    private func askForPreviews<Messages: Sequence>(_ messages: Messages) async where Messages.Element == ConversationMessage {
        let candidates = messages.filter { ($0.linkPreviewsRemovedAt ?? "").isEmpty }.map { (id: $0.id, text: $0.content?.stringValue ?? "") }
        await linkPreviews.load(candidates)
    }

    /// Shows the page of messages before the first one held.
    func loadEarlier() async {
        guard let first = window.firstMessageId, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let page = try await connection.messages(
                conversationId: conversationId, latestCount: MessageWindow.pageSize, beforeMessageId: first)
            window.prepend(page)
            transcript.load(messages: window.messages, questions: cards.questions, approvals: cards.approvals, isRunning: transcript.isRunning)
            await askForPreviews(page)
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    func refreshBackgroundWork() async {
        if let work = try? await connection.backgroundWork(conversationId: conversationId) {
            backgroundWork = work.filter(\.isInProgress)
        }
    }

    func stopBackgroundWork(_ work: BackgroundWork) async {
        do {
            try await connection.stopBackgroundWork(id: work.id)
            await refreshBackgroundWork()
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    /// Sends what the person typed. While a fresh question is open the text
    /// answers it; otherwise it goes out as a message.
    func send(_ text: String, attachments: AttachmentDrafts? = nil) async -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFiles = !(attachments?.items.isEmpty ?? true)
        guard !trimmed.isEmpty || hasFiles else { return false }
        if hasFiles, let attachments {
            // Files go up first, then the message names them the way the web app does.
            do {
                let files = try await attachments.upload(using: connection)
                trimmed = SharePayload.assistantMessage(text: trimmed, files: files)
            } catch {
                actionError = error.userMessage
                onError(error)
                return false
            }
        }
        if let question = activeQuestion {
            await answer(question, with: trimmed)
            if actionError == nil { attachments?.removeUploaded() }
            return actionError == nil
        }
        actionError = nil
        let reply = replyTarget
        let viewing = viewingReference?.viewing
        transcript.appendPendingUser(trimmed, viewing: viewing)
        do {
            try await connection.sendMessage(
                conversationId: conversationId, text: trimmed, viewing: viewing,
                replyToMessageId: ThreadRouting.replyToMessageId(pickedMessageId: reply?.messageId, viewThreadRootMessageId: threadRootMessageId),
                pageTitle: title)
            replyTarget = nil
            viewingReference = nil
            attachments?.removeUploaded()
            await followThreadRoot()
            return true
        } catch {
            transcript.removePendingUser(trimmed)
            actionError = error.userMessage
            onError(error)
            return false
        }
    }

    /// An old answer with no thread joins its question's thread on its first reply: the screen that was opened from it moves to the
    /// thread the server says it is in now.
    private func followThreadRoot() async {
        guard let openRoot = threadRootMessageId,
            let root = await connection.messageThreadRoot(conversationId: conversationId, messageId: openRoot), root != openRoot
        else { return }
        threadRootMessageId = root
        transcript = Transcript(threadRootMessageId: root)
        await reload()
    }

    func cancelRun() async {
        do {
            try await connection.cancelRun(conversationId: conversationId)
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    func answer(_ card: QuestionCard, with text: String) async {
        actionError = nil
        do {
            try await connection.answerQuestion(id: card.id, answer: text)
            transcript.removeQuestion(id: card.id)
        } catch {
            // Answered somewhere else, cancelled or timed out: the card is not open any more.
            if case PortalError.cardNoLongerWaiting = error { transcript.removeQuestion(id: card.id) }
            actionError = error.userMessage
            onError(error)
        }
    }

    /// Sets a question aside: what the person types next goes out as a message.
    func dismissQuestion(_ card: QuestionCard) {
        dismissedQuestionIds.insert(card.id)
    }

    func decide(_ card: ApprovalCard, isApproved: Bool) async {
        actionError = nil
        do {
            try await connection.resolveToolApproval(id: card.id, isApproved: isApproved)
            transcript.removeApproval(id: card.id)
        } catch {
            if case PortalError.cardNoLongerWaiting = error { transcript.removeApproval(id: card.id) }
            actionError = error.userMessage
            onError(error)
        }
    }

    /// Reacts to an answer. Choosing the emoji already chosen takes it back.
    func react(messageId: String, emoji: String) async {
        actionError = nil
        let chosen = Reactions.emojiToSend(chosen: emoji, in: transcript.reactions(for: messageId), currentUserId: currentUserId)
        do {
            let reactions = try await connection.react(conversationId: conversationId, messageId: messageId, emoji: chosen)
            transcript.setReactions(reactions, for: messageId)
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    func rename(to newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let renamed = try await connection.renameConversation(id: conversationId, title: trimmed)
            title = renamed?.title ?? trimmed
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    /// "Not now" under the first message of a conversation the assistant started.
    func snoozeSpeakFirst() async {
        do {
            try await connection.snoozeSpeakFirst(isSnoozed: true)
            speakFirstOutcome = String(localized: "The assistant will not start conversations for 24 hours.")
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    /// "Stop these": the reason's own switch, or the whole feature for onboarding.
    func stopSpeakingFirst(reason: String) async {
        do {
            try await connection.stopSpeakingFirst(reason: reason)
            speakFirstOutcome = String(localized: "The assistant will not start conversations like this again. You can change it in More.")
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }

    // MARK: memory filing

    func refreshFiling() async {
        if let filings = try? await connection.memoryFilings(conversationId: conversationId) {
            filingNote = MemoryFilingNote.latestWithFacts(filings)
        }
    }

    func forgetFiledFact(_ fact: MemoryFact, in filing: MemoryFiling) async {
        do {
            try await connection.forgetFiledFact(filingId: filing.id, factId: fact.id)
            await refreshFiling()
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }
}
