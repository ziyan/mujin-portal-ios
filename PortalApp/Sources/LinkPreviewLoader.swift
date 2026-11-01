import Observation
import PortalKit

/// LinkPreviewLoader asks the server for the cards under messages that hold a link, in a people chat or a conversation
/// with the assistant alike. The server fetches a link the first time it is asked about, so while any is still being
/// fetched the loader asks again every few seconds, a bounded number of times.
@MainActor
@Observable
final class LinkPreviewLoader {
    private(set) var previews: [String: [LinkPreviewCard]] = [:]
    @ObservationIgnored private var askedIds: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let connection: Connection
    @ObservationIgnored private let conversationId: String

    init(connection: Connection, conversationId: String) {
        self.connection = connection
        self.conversationId = conversationId
    }

    /// Asks about the messages whose text may hold a link and that were not asked about yet (or all of them when `force` is set).
    func load(_ messages: [(id: String, text: String)], force: Bool = false) async {
        let wanted = messages.filter { LinkPreviewRules.mayHoldLink($0.text) && (force || !askedIds.contains($0.id)) }.map(\.id)
        guard !wanted.isEmpty else { return }
        askedIds.formUnion(wanted)
        var firstPending: [String] = []
        for start in stride(from: 0, to: wanted.count, by: LinkPreviewRules.maximumMessagesPerRequest) {
            firstPending += await fetch(Array(wanted[start..<min(start + LinkPreviewRules.maximumMessagesPerRequest, wanted.count)]))
        }
        guard !firstPending.isEmpty else { return }
        task?.cancel()
        let started = firstPending
        task = Task { [weak self] in
            var pending = started
            var attempts = 0
            while !pending.isEmpty, attempts < LinkPreviewRules.maximumRetries, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(LinkPreviewRules.pendingRetryInterval * 1_000_000_000))
                if Task.isCancelled { return }
                attempts += 1
                guard let self else { return }
                pending = await self.fetch(pending)
            }
        }
    }

    /// Reads the cards of messages and returns the ones still being fetched.
    private func fetch(_ ids: [String]) async -> [String] {
        guard let rows = try? await connection.linkPreviews(conversationId: conversationId, messageIds: ids) else { return [] }
        var pending: [String] = []
        for row in rows {
            previews[row.messageId] = row.linkPreviews ?? []
            if row.isPending == true { pending.append(row.messageId) }
        }
        return pending
    }

    /// Removes the cards under one of the person's own messages.
    func remove(messageId: String) async throws {
        try await connection.removeLinkPreviews(conversationId: conversationId, messageId: messageId)
        previews[messageId] = []
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
