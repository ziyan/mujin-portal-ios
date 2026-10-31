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
        public init(toolCallId: String, toolName: String? = nil, result: String? = nil) {
            self.toolCallId = toolCallId
            self.toolName = toolName
            self.result = result
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
        public init(stopReason: String? = nil) { self.stopReason = stopReason }
    }

    public struct RunError: Codable, Equatable, Sendable {
        public let error: String?
        public init(error: String? = nil) { self.error = error }
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

    public init(
        type: String, runId: String? = nil, textDelta: TextDelta? = nil, toolCall: ToolCall? = nil, toolResult: ToolResult? = nil,
        pendingQuestion: PendingQuestion? = nil, pendingApproval: PendingApproval? = nil, runComplete: RunComplete? = nil, runError: RunError? = nil
    ) {
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
