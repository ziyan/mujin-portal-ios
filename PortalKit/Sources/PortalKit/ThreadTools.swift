import Foundation

/// Thread-native interactions: a server that has them says, on each question, approval, waiting item, artifact and todo, which
/// thread of the conversation it belongs to. A thread shows its own, and the main history the rest, with a pointer to a thread
/// where something waits.
extension ServerCapabilities {
    /// Whether questions, approvals, waiting items, artifacts and todos say their thread.
    public var offersThreadTools: Bool { questionFieldNames.contains("threadRootMessageId") }
    /// Whether the server keeps the assistant's todo list for a conversation.
    public var offersTodos: Bool { offersQuery("ListConversationTodos") }
}

extension ConversationEvent {
    /// Whether this event is the result of the assistant's todo tool, after which the todo list is read again.
    public var mayChangeTodos: Bool {
        kind == .toolResult && (toolResult?.toolName ?? "").lowercased().contains("todo")
    }
}

extension Documents {
    /// The fields each document that lists them adds on a server with thread-native interactions.
    static let threadToolAnchors = [
        "id question choices allowOther askedAt answeredAt cancelledAt",
        "id toolCallId toolName policyReason risk arguments requestedAt decidedAt cancelledAt",
        "conversationId organizationId ownerUserId conversationTitle waitingKind interactionId promptText toolName toolRisk askedAt expiresAt",
        "id conversationId attachmentId title artifactKind sizeBytes createdAt",
        "id title status priority createdAt completedAt",
    ]

    /// A document with each question's, approval's, waiting item's, artifact's and todo's thread added.
    /// Fields are matched whatever whitespace separates them, so a document laid out on several lines still gets its field.
    public static func withThreadTools(_ document: String) -> String {
        threadToolAnchors.reduce(document) { result, fields in addThreadField(to: result, after: fields) }
    }

    static func addThreadField(to document: String, after fields: String) -> String {
        let pattern = fields.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        return document.replacingOccurrences(of: pattern, with: "$0 threadRootMessageId", options: .regularExpression)
    }

    public static let listTodos = """
        query ListConversationTodos($conversationId: String) {
          ListConversationTodos(conversationId: $conversationId) { id title status priority createdAt completedAt }
        }
        """

    static var threadToolDocuments: [String] { [listTodos] }
}

/// ConversationTodo is an item of the assistant's todo list for a conversation, or for one thread of it.
public struct ConversationTodo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    /// `open`, `in_progress` or `done`, as the server says it.
    public let status: String?
    public let priority: String?
    public let createdAt: String?
    public let completedAt: String?
    public let threadRootMessageId: String?

    public init(
        id: String, title: String?, status: String?, priority: String? = nil, createdAt: String? = nil, completedAt: String? = nil,
        threadRootMessageId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.threadRootMessageId = threadRootMessageId
    }

    public var isDone: Bool { status?.lowercased() == "done" }
}

/// ThreadViews decides what belongs to which view of a conversation: the main history, or one thread.
public enum ThreadViews {
    /// Whether something said to be in a thread (nil for the main history) shows in the view of that thread (nil for the main history).
    public static func belongs(threadRootMessageId: String?, toView viewThreadRootMessageId: String?) -> Bool {
        ThreadRouting.normalized(threadRootMessageId) == ThreadRouting.normalized(viewThreadRootMessageId)
    }

    /// The todo list of one view: open items first, then done ones, each oldest first.
    public static func todos(_ todos: [ConversationTodo], inView viewThreadRootMessageId: String?) -> [ConversationTodo] {
        let shown = todos.filter { belongs(threadRootMessageId: $0.threadRootMessageId, toView: viewThreadRootMessageId) }
        let byAge: (ConversationTodo, ConversationTodo) -> Bool = { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        return shown.filter { !$0.isDone }.sorted(by: byAge) + shown.filter(\.isDone).sorted(by: byAge)
    }

    /// The threads where a question or an approval waits, in the order they were asked, each once: the main history points to them.
    public static func waitingThreads(questions: [QuestionCard], approvals: [ApprovalCard]) -> [String] {
        var roots: [String] = []
        for root in questions.compactMap(\.threadRootMessageId) + approvals.compactMap(\.threadRootMessageId) where !roots.contains(root) {
            roots.append(root)
        }
        return roots
    }

    /// The thread a conversation opens on: the one where something waits, when nothing waits in the main history.
    public static func threadToOpenOn(questions: [QuestionCard], approvals: [ApprovalCard]) -> String? {
        let isMainWaiting = questions.contains { $0.threadRootMessageId == nil } || approvals.contains { $0.threadRootMessageId == nil }
        return isMainWaiting ? nil : waitingThreads(questions: questions, approvals: approvals).first
    }

    /// The artifacts a view lists, newest first: those made in it, and in a thread also any whose card is among the thread's messages.
    /// The server lists them oldest first, so they are put in order here, by when each was made and then by id, both descending.
    public static func artifacts(_ artifacts: [ArtifactReference], inView viewThreadRootMessageId: String?, cardIds: Set<String>) -> [ArtifactReference] {
        newestFirst(artifacts.filter { artifact in
            belongs(threadRootMessageId: artifact.threadRootMessageId, toView: viewThreadRootMessageId)
                || (viewThreadRootMessageId != nil && cardIds.contains(artifact.id))
        })
    }

    /// Artifacts newest first: by when each was made, then by id, both descending. One that does not say when sorts last.
    public static func newestFirst(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        artifacts.sorted { first, second in
            let firstDate = PortalDate.parse(first.createdAt) ?? .distantPast
            let secondDate = PortalDate.parse(second.createdAt) ?? .distantPast
            if firstDate != secondDate { return firstDate > secondDate }
            return first.id > second.id
        }
    }
}

extension Connection {
    /// The assistant's todo list for a conversation, every thread's together.
    public func todos(conversationId: String) async throws -> [ConversationTodo] {
        struct Answer: Decodable, Sendable { let ListConversationTodos: [ConversationTodo]? }
        return try await execute(Documents.listTodos, variables: ["conversationId": .string(conversationId)], as: Answer.self).ListConversationTodos ?? []
    }
}
