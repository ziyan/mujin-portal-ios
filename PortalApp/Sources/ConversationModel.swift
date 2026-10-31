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
    let connection: Connection
    let socketFactory: FeedSocketFactory
    let onError: @MainActor (Error) -> Void

    private(set) var transcript = Transcript()
    private(set) var phase = Phase.loading
    private(set) var title: String?
    /// Whether the live feed is up. False while it reconnects.
    private(set) var isFeedLive = false
    /// Why the last send or answer failed, shown beside the composer.
    var actionError: String?

    private var feedTask: Task<Void, Never>?

    init(conversationId: String, connection: Connection, socketFactory: @escaping FeedSocketFactory, onError: @escaping @MainActor (Error) -> Void) {
        self.conversationId = conversationId
        self.connection = connection
        self.socketFactory = socketFactory
        self.onError = onError
    }

    var isRunning: Bool { transcript.isRunning }

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
    }

    func stop() {
        feedTask?.cancel()
        feedTask = nil
    }

    private func handle(_ update: FeedUpdate) async {
        switch update {
        case .connected:
            isFeedLive = true
            // What was said while the feed was down is only in the history;
            // the server replays the running turn on this socket.
            transcript.dropLiveEntries()
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
            async let messages = connection.messages(conversationId: conversationId)
            async let cards = connection.waitingCards(conversationId: conversationId)
            let (loadedSummary, loadedMessages, loadedCards) = try await (summary, messages, cards)
            title = loadedSummary.title
            transcript.load(
                messages: loadedMessages, questions: loadedCards.questions, approvals: loadedCards.approvals,
                isRunning: !isRunFinished && (loadedSummary.isRunning || transcript.hasPendingUser))
            phase = .loaded
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
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
}
