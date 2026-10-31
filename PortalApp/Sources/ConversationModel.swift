import Foundation
import Observation
import PortalKit

/// ConversationModel is one open conversation: its transcript, kept current
/// by the subscription feed, and what the person does in it.
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

    private(set) var transcript = Transcript()
    private(set) var window = MessageWindow()
    private(set) var phase = Phase.loading
    private(set) var title: String?
    /// Whether the live feed is up. False while it reconnects.
    private(set) var isFeedLive = false
    private(set) var isLoadingEarlier = false
    /// Background work this conversation started that has not ended.
    private(set) var backgroundWork: [BackgroundWork] = []
    /// Questions the person set aside, so what they type goes out as a message.
    private(set) var dismissedQuestionIds: Set<String> = []
    /// Why the last send or answer failed, shown beside the composer.
    var actionError: String?

    private var feedTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var cards: (questions: [QuestionCard], approvals: [ApprovalCard]) = ([], [])

    init(
        conversationId: String, currentUserId: String, connection: Connection, socketFactory: @escaping FeedSocketFactory,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.conversationId = conversationId
        self.currentUserId = currentUserId
        self.connection = connection
        self.socketFactory = socketFactory
        self.onError = onError
    }

    var isRunning: Bool { transcript.isRunning }

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
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if !self.backgroundWork.isEmpty { await self.refreshBackgroundWork() }
            }
        }
    }

    func stop() {
        feedTask?.cancel()
        feedTask = nil
        pollTask?.cancel()
        pollTask = nil
    }

    private func handle(_ update: FeedUpdate) async {
        switch update {
        case .connected:
            isFeedLive = true
            // What was said while the feed was down is only in the history;
            // the server replays the running turn on this socket. Reactions
            // are never replayed, so older local changes give way to the history.
            transcript.dropLiveEntries()
            transcript.expireFoldedReactions(olderThan: 60)
            await reload()
        case .event(let event):
            transcript.apply(event)
            switch event.kind {
            case .runComplete, .runError: await reload(isRunFinished: true)
            case .pendingQuestion, .pendingApproval: await reload()
            default: break
            }
        case .reconnecting:
            isFeedLive = false
        case .signedOut:
            isFeedLive = false
            onError(PortalError.signedOut)
        }
    }

    /// Loads the persisted conversation and the questions and approvals still waiting.
    func reload(isRunFinished: Bool = false) async {
        do {
            async let summary = connection.conversation(id: conversationId)
            async let messages = connection.messages(conversationId: conversationId, latestCount: window.reloadCount)
            async let waitingCards = connection.waitingCards(conversationId: conversationId)
            async let total = try? connection.messageCount(conversationId: conversationId)
            let (loadedSummary, loadedMessages, loadedCards) = try await (summary, messages, waitingCards)
            window.replace(with: loadedMessages, totalCount: await total)
            cards = loadedCards
            title = loadedSummary.title
            transcript.load(
                messages: window.messages, questions: cards.questions, approvals: cards.approvals,
                isRunning: !isRunFinished && (loadedSummary.isRunning || transcript.hasPendingUser))
            phase = .loaded
            await refreshBackgroundWork()
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    /// Shows the page of messages before the first one held.
    func loadEarlier() async {
        guard let first = window.firstMessageId, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let page = try await connection.messages(conversationId: conversationId, latestCount: MessageWindow.pageSize, beforeMessageId: first)
            window.prepend(page)
            transcript.load(messages: window.messages, questions: cards.questions, approvals: cards.approvals, isRunning: transcript.isRunning)
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
    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let question = activeQuestion {
            await answer(question, with: trimmed)
            return actionError == nil
        }
        actionError = nil
        transcript.appendPendingUser(trimmed)
        do {
            try await connection.sendMessage(conversationId: conversationId, text: trimmed)
            return true
        } catch {
            transcript.removePendingUser(trimmed)
            actionError = error.userMessage
            onError(error)
            return false
        }
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
}
