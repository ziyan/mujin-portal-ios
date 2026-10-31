import Foundation

/// The things the app asks of Portal, one function each.
extension Connection {
    public func me() async throws -> Me {
        struct Answer: Decodable, Sendable { let Me: Me }
        return try await execute(Documents.me, as: Answer.self).Me
    }

    public func mainAgent() async throws -> Agent {
        struct Answer: Decodable, Sendable { let GetMainAgent: Agent }
        return try await execute(Documents.mainAgent, as: Answer.self).GetMainAgent
    }

    /// The person's own conversations, newest first.
    public func conversations(userId: String) async throws -> [ConversationSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let conversations: [ConversationSummary]? }
            let ListConversations: List
        }
        let answer = try await execute(Documents.listConversations, variables: ["userId": .string(userId)], as: Answer.self)
        return (answer.ListConversations.conversations ?? []).sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    public func conversation(id: String) async throws -> ConversationSummary {
        struct Answer: Decodable, Sendable { let GetConversation: ConversationSummary }
        return try await execute(Documents.getConversation, variables: ["conversationId": .string(id)], as: Answer.self).GetConversation
    }

    public func messages(conversationId: String) async throws -> [ConversationMessage] {
        struct Answer: Decodable, Sendable { let ListConversationMessages: [ConversationMessage]? }
        return try await execute(Documents.listMessages, variables: ["conversationId": .string(conversationId)], as: Answer.self)
            .ListConversationMessages ?? []
    }

    /// The questions and approvals still waiting for the person.
    public func waitingCards(conversationId: String) async throws -> (questions: [QuestionCard], approvals: [ApprovalCard]) {
        struct Questions: Decodable, Sendable {
            struct Row: Decodable, Sendable {
                let id: String
                let question: String?
                let choices: [String]?
                let allowOther: Bool?
                let answeredAt: String?
                let cancelledAt: String?
            }
            let ListConversationQuestions: [Row]?
        }
        struct Approvals: Decodable, Sendable {
            struct Row: Decodable, Sendable {
                let id: String
                let toolCallId: String?
                let toolName: String?
                let policyReason: String?
                let risk: String?
                let arguments: String?
                let decidedAt: String?
                let cancelledAt: String?
            }
            let ListConversationApprovals: [Row]?
        }
        let variables: [String: JSONValue] = ["conversationId": .string(conversationId)]
        async let questionRows = execute(Documents.listQuestions, variables: variables, as: Questions.self)
        async let approvalRows = execute(Documents.listApprovals, variables: variables, as: Approvals.self)
        let questions = try await questionRows.ListConversationQuestions ?? []
        let approvals = try await approvalRows.ListConversationApprovals ?? []
        return (
            questions.filter { ($0.answeredAt ?? "").isEmpty && ($0.cancelledAt ?? "").isEmpty }.map {
                QuestionCard(id: $0.id, question: $0.question ?? "", choices: $0.choices ?? [], allowOther: $0.allowOther ?? true)
            },
            approvals.filter { ($0.decidedAt ?? "").isEmpty && ($0.cancelledAt ?? "").isEmpty }.map {
                ApprovalCard(
                    id: $0.id, toolCallId: $0.toolCallId ?? "", toolName: $0.toolName ?? "", policyReason: $0.policyReason ?? "",
                    risk: $0.risk ?? "", arguments: $0.arguments ?? "")
            }
        )
    }

    public func createConversation(agentId: String) async throws -> ConversationSummary {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable { let conversation: ConversationSummary }
            let CreateConversation: Created
        }
        return try await execute(Documents.createConversation, variables: ["agentId": .string(agentId)], as: Answer.self)
            .CreateConversation.conversation
    }

    /// Starts a turn and returns its run id.
    @discardableResult
    public func sendMessage(conversationId: String, text: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Sent: Decodable, Sendable { let runId: String? }
            let SendMessage: Sent
        }
        let answer = try await execute(
            Documents.sendMessage, variables: ["conversationId": .string(conversationId), "message": .string(text)], as: Answer.self)
        return answer.SendMessage.runId ?? ""
    }

    public func cancelRun(conversationId: String) async throws {
        _ = try await execute(Documents.cancelRun, variables: ["conversationId": .string(conversationId)], as: JSONValue.self)
    }

    public func answerQuestion(id: String, answer: String) async throws {
        _ = try await execute(
            Documents.answerQuestion, variables: ["questionId": .string(id), "answer": .string(answer)], as: JSONValue.self)
    }

    /// Approves or rejects a tool call. The verdict words are the server's.
    public func resolveToolApproval(id: String, isApproved: Bool, reason: String? = nil) async throws {
        var variables: [String: JSONValue] = ["approvalId": .string(id), "verdict": .string(isApproved ? "approved" : "rejected")]
        if let reason, !reason.isEmpty { variables["reason"] = .string(reason) }
        _ = try await execute(Documents.resolveToolApproval, variables: variables, as: JSONValue.self)
    }

    public func archiveConversation(id: String) async throws {
        _ = try await execute(
            Documents.archiveConversation, variables: ["conversationId": .string(id), "archived": .bool(true)], as: JSONValue.self)
    }
}
