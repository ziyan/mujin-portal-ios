import Foundation

/// Documents are every GraphQL document the app sends. The test suite checks
/// each of them against Schema/schema.json, so a field Portal renames or
/// removes fails a test here before it fails on a phone.
public enum Documents {
    static let conversationFields = """
        id agentId title summary lastMessageAt activeRunId archivedAt createdAt modifiedAt
        """

    public static let me = """
        query Me { Me { id email name organizationId } }
        """

    public static let mainAgent = """
        query GetMainAgent { GetMainAgent { id name isMain } }
        """

    public static let listConversations = """
        query ListConversations($userId: String) {
          ListConversations(userId: $userId) {
            conversations { \(conversationFields) }
            meta { totalCount }
          }
        }
        """

    public static let getConversation = """
        query GetConversation($conversationId: String!) {
          GetConversation(conversationId: $conversationId) { \(conversationFields) }
        }
        """

    public static let listMessages = """
        query ListConversationMessages($conversationId: String!) {
          ListConversationMessages(conversationId: $conversationId) {
            id role content toolCalls toolCallId toolName stopReason createdAt
          }
        }
        """

    public static let listQuestions = """
        query ListConversationQuestions($conversationId: String!) {
          ListConversationQuestions(conversationId: $conversationId) {
            id question choices allowOther askedAt answeredAt cancelledAt
          }
        }
        """

    public static let listApprovals = """
        query ListConversationApprovals($conversationId: String!) {
          ListConversationApprovals(conversationId: $conversationId) {
            id toolCallId toolName policyReason risk arguments requestedAt decidedAt cancelledAt
          }
        }
        """

    public static let createConversation = """
        mutation CreateConversation($agentId: String!) {
          CreateConversation(agentId: $agentId) { conversation { \(conversationFields) } }
        }
        """

    public static let sendMessage = """
        mutation SendMessage($conversationId: String!, $message: String!) {
          SendMessage(conversationId: $conversationId, message: $message) { runId }
        }
        """

    public static let cancelRun = """
        mutation CancelRun($conversationId: String!) { CancelRun(conversationId: $conversationId) }
        """

    public static let answerQuestion = """
        mutation AnswerQuestion($questionId: String!, $answer: String!) {
          AnswerQuestion(questionId: $questionId, answer: $answer)
        }
        """

    public static let resolveToolApproval = """
        mutation ResolveToolApproval($approvalId: String!, $verdict: String!, $reason: String) {
          ResolveToolApproval(approvalId: $approvalId, verdict: $verdict, reason: $reason)
        }
        """

    public static let archiveConversation = """
        mutation ArchiveConversation($conversationId: String!, $archived: Boolean) {
          ArchiveConversation(conversationId: $conversationId, archived: $archived) { conversation { id archivedAt } }
        }
        """

    public static let listSites = """
        query ListSites { ListSites { sites { id name organizationId isArchived } } }
        """

    public static let createTicket = """
        mutation CreateTicket($ticket: TicketInput!) {
          CreateTicket(ticket: $ticket) { ticket { id sequence title } }
        }
        """

    /// Which mutations the server offers, for features that depend on a newer Portal.
    public static let mutationNames = """
        query MutationNames { __type(name: "RootMutation") { fields { name } } }
        """

    public static let onConversationEvent = """
        subscription OnConversationEvent($conversationId: String!) {
          OnConversationEvent(conversationId: $conversationId) {
            type
            runId
            textDelta { messageId text }
            toolCall { toolCallId toolName arguments }
            toolResult { toolCallId toolName result }
            pendingQuestion { questionId question choices allowOther }
            pendingApproval { approvalId toolCallId toolName policyReason risk arguments }
            runComplete { stopReason promptTokens completionTokens }
            runError { error }
          }
        }
        """

    /// Every document, for the schema check.
    public static let all: [String] = [
        me, mainAgent, listConversations, getConversation, listMessages, listQuestions, listApprovals,
        createConversation, sendMessage, cancelRun, answerQuestion, resolveToolApproval, archiveConversation,
        listSites, createTicket, onConversationEvent,
    ]
}
