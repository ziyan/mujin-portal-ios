import Foundation

/// ConversationEvent is one thing Portal says about a running conversation
/// through OnConversationEvent. The type names the variant; one of the
/// optional fields holds its details.
public struct ConversationEvent: Codable, Equatable, Sendable {
    public struct TextDelta: Codable, Equatable, Sendable {
        public let messageId: String
        public let text: String
        public init(messageId: String, text: String) {
            self.messageId = messageId
            self.text = text
        }
    }

    public struct ToolCall: Codable, Equatable, Sendable {
        public let toolCallId: String
        public let toolName: String
        public let arguments: String?
        public init(toolCallId: String, toolName: String, arguments: String? = nil) {
            self.toolCallId = toolCallId
            self.toolName = toolName
            self.arguments = arguments
        }
    }

    public struct ToolResult: Codable, Equatable, Sendable {
        public let toolCallId: String
        public let toolName: String?
        public let result: String?
        /// One short line the tool wrote about the call, such as "3 controllers".
        public let toolNote: String?
        public let durationMS: Int?
        public init(toolCallId: String, toolName: String? = nil, result: String? = nil, toolNote: String? = nil, durationMS: Int? = nil) {
            self.toolCallId = toolCallId
            self.toolName = toolName
            self.result = result
            self.toolNote = toolNote
            self.durationMS = durationMS
        }
    }

    public struct PendingQuestion: Codable, Equatable, Sendable {
        public let questionId: String
        public let question: String
        public let choices: [String]?
        public let allowOther: Bool?
        public init(questionId: String, question: String, choices: [String]? = nil, allowOther: Bool? = nil) {
            self.questionId = questionId
            self.question = question
            self.choices = choices
            self.allowOther = allowOther
        }
    }

    public struct PendingApproval: Codable, Equatable, Sendable {
        public let approvalId: String
        public let toolCallId: String?
        public let toolName: String
        public let policyReason: String?
        public let risk: String?
        public let arguments: String?
        public init(approvalId: String, toolCallId: String? = nil, toolName: String, policyReason: String? = nil, risk: String? = nil, arguments: String? = nil) {
            self.approvalId = approvalId
            self.toolCallId = toolCallId
            self.toolName = toolName
            self.policyReason = policyReason
            self.risk = risk
            self.arguments = arguments
        }
    }

    public struct RunComplete: Codable, Equatable, Sendable {
        public let stopReason: String?
        /// The sentence to show when the runner ended the turn itself.
        public let turnEndReason: String?
        /// Why the turn ended, as a kind the app words itself: see `TurnEndReason`.
        public let reasonKind: String?
        public let reasonParameters: JSONValue?
        public init(stopReason: String? = nil, turnEndReason: String? = nil, reasonKind: String? = nil, reasonParameters: JSONValue? = nil) {
            self.stopReason = stopReason
            self.turnEndReason = turnEndReason
            self.reasonKind = reasonKind
            self.reasonParameters = reasonParameters
        }
    }

    public struct RunError: Codable, Equatable, Sendable {
        /// The operator's text. It is not shown to the person.
        public let error: String?
        /// The bounded sentence for a failed run.
        public let turnEndReason: String?
        public let reasonKind: String?
        public let reasonParameters: JSONValue?
        public init(error: String? = nil, turnEndReason: String? = nil, reasonKind: String? = nil, reasonParameters: JSONValue? = nil) {
            self.error = error
            self.turnEndReason = turnEndReason
            self.reasonKind = reasonKind
            self.reasonParameters = reasonParameters
        }
    }

    public struct RoundRetry: Codable, Equatable, Sendable {
        public let discardedMessageId: String
        public init(discardedMessageId: String) { self.discardedMessageId = discardedMessageId }
    }

    public struct Reacted: Codable, Equatable, Sendable {
        public let messageId: String
        /// Empty when that reactor took theirs back.
        public let emoji: String
        public let reactorKind: String
        public let reactorUserId: String?
        public init(messageId: String, emoji: String, reactorKind: String, reactorUserId: String? = nil) {
            self.messageId = messageId
            self.emoji = emoji
            self.reactorKind = reactorKind
            self.reactorUserId = reactorUserId
        }
    }

    public struct ModelSwitch: Codable, Equatable, Sendable {
        /// `tool` when the quick model asked for it, `judgment` when the effort judgment did.
        public let switchCause: String?
        public let switchReason: String?
        public init(switchCause: String? = nil, switchReason: String? = nil) {
            self.switchCause = switchCause
            self.switchReason = switchReason
        }
    }

    /// A chat event: a message said, edited or deleted in a room, a reaction,
    /// a change of members, someone typing, a read mark, a link preview ready.
    public struct Chat: Codable, Equatable, Sendable {
        public let type: String?
        public let chatId: String?
        public let messageId: String?
        public let messageCreatedAt: String?
        public let message: ConversationMessage?
        public let actorUserId: String?
        public let actorUserName: String?
        public let isActorAssistant: Bool?
        public let lastReadMessageId: String?
        /// joined, left, removed or updated.
        public let memberChangeKind: String?
        public let affectedUserIds: [String]?
        /// Empty when the reaction was taken away.
        public let reactionEmoji: String?
    }

    /// The event types Portal emits (backend/agents/agents.go).
    public enum Kind: String, Sendable {
        case textDelta = "text_delta"
        case toolCall = "tool_call"
        case toolResult = "tool_result"
        case pendingQuestion = "pending_question"
        case pendingApproval = "pending_approval"
        case runComplete = "run_complete"
        case runError = "run_error"
        case roundRetry = "round_retry"
        case reacted
        case modelSwitch = "model_switch"
        case chatSaid = "chat_said"
        case chatEdited = "chat_edited"
        case chatDeleted = "chat_deleted"
        case chatReacted = "chat_reacted"
        case chatMembers = "chat_members"
        case chatTyping = "chat_typing"
        case chatRead = "chat_read"
        case chatLinkPreview = "chat_link_preview"
    }

    public let type: String
    public let runId: String?
    public let textDelta: TextDelta?
    public let toolCall: ToolCall?
    public let toolResult: ToolResult?
    public let pendingQuestion: PendingQuestion?
    public let pendingApproval: PendingApproval?
    public let runComplete: RunComplete?
    public let runError: RunError?
    public let roundRetry: RoundRetry?
    public let reacted: Reacted?
    public let modelSwitch: ModelSwitch?
    public let chat: Chat?

    public init(
        type: String, runId: String? = nil, textDelta: TextDelta? = nil, toolCall: ToolCall? = nil, toolResult: ToolResult? = nil,
        pendingQuestion: PendingQuestion? = nil, pendingApproval: PendingApproval? = nil, runComplete: RunComplete? = nil, runError: RunError? = nil,
        roundRetry: RoundRetry? = nil, reacted: Reacted? = nil, modelSwitch: ModelSwitch? = nil, chat: Chat? = nil
    ) {
        self.chat = chat
        self.roundRetry = roundRetry
        self.reacted = reacted
        self.modelSwitch = modelSwitch
        self.type = type
        self.runId = runId
        self.textDelta = textDelta
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.pendingQuestion = pendingQuestion
        self.pendingApproval = pendingApproval
        self.runComplete = runComplete
        self.runError = runError
    }

    public var kind: Kind? { Kind(rawValue: type) }
}
