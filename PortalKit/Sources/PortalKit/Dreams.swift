import Foundation

/// AgentDreamSetting is an organization's choice about the assistant tidying its memory in the background.
public struct AgentDreamSetting: Codable, Equatable, Sendable {
    public let organizationId: String?
    public let isDreamEnabled: Bool?
    public let dreamBudgetSharePercent: Int?
    public let dreamTokenCap: Int?
    public let dailyTokenAllowance: Int?
    public let todayBudgetTokenCount: Int?
    public let todaySpentTokenCount: Int?
    public let lastDreamEndedAt: String?
    public let hasBacklog: Bool?
    public let isDreaming: Bool?
    public let canManageOrganization: Bool?

    public var lastDreamEnd: Date? { PortalDate.parse(lastDreamEndedAt) }
}

/// MemoryDream is one run of that tidying.
public struct MemoryDream: Codable, Equatable, Identifiable, Sendable {
    public struct PhaseReport: Codable, Equatable, Identifiable, Sendable {
        public let dreamPhase: String?
        public let phaseOutcome: String?
        public let doneItemCount: Int?
        public let backlogItemCount: Int?
        public let phaseNote: String?
        public var id: String { dreamPhase ?? "" }
    }

    public let id: String
    public let organizationId: String?
    public let organizationName: String?
    /// `automatic` or `requested`.
    public let dreamTrigger: String?
    /// `running`, `completed`, `stopped_by_budget`, `stopped_by_deadline` or `failed`.
    public let dreamStatus: String?
    public let errorMessage: String?
    public let startedAt: String?
    public let endedAt: String?
    public let budgetTokenCount: Int?
    public let spentTokenCount: Int?
    public let mergedFactCount: Int?
    public let dormantFactCount: Int?
    public let proposedLinkCount: Int?
    public let rewrittenSummaryCount: Int?
    public let splitPageCount: Int?
    public let gapQuestions: [String]?
    public let phaseReports: [PhaseReport]?

    public var isRunning: Bool { dreamStatus == "running" }
    public var start: Date? { PortalDate.parse(startedAt) }
}

extension Documents {
    static let dreamSettingFields = """
        organizationId isDreamEnabled dreamBudgetSharePercent dreamTokenCap dailyTokenAllowance todayBudgetTokenCount todaySpentTokenCount
        lastDreamEndedAt hasBacklog isDreaming canManageOrganization
        """

    static let dreamFields = """
        id organizationId organizationName dreamTrigger dreamStatus errorMessage startedAt endedAt budgetTokenCount spentTokenCount mergedFactCount
        dormantFactCount proposedLinkCount rewrittenSummaryCount splitPageCount gapQuestions
        phaseReports { dreamPhase phaseOutcome doneItemCount backlogItemCount phaseNote }
        """

    public static let getAgentDreamSetting = """
        query GetAgentDreamSetting($organizationId: String) { GetAgentDreamSetting(organizationId: $organizationId) { \(dreamSettingFields) } }
        """

    public static let setAgentDreamSetting = """
        mutation SetAgentDreamSetting($isDreamEnabled: Boolean, $dreamBudgetSharePercent: Int64, $dreamTokenCap: Int64) {
          SetAgentDreamSetting(isDreamEnabled: $isDreamEnabled, dreamBudgetSharePercent: $dreamBudgetSharePercent, dreamTokenCap: $dreamTokenCap) {
            \(dreamSettingFields)
          }
        }
        """

    public static let startMemoryDream = """
        mutation StartMemoryDream($organizationId: String) { StartMemoryDream(organizationId: $organizationId) { isStarted } }
        """

    public static let listMemoryDreams = """
        query ListMemoryDreams($options: ListOptionsInput) {
          ListMemoryDreams(options: $options) { memoryDreams { \(dreamFields) } meta { totalCount } }
        }
        """

    static var dreamDocuments: [String] {
        [
            getAgentDreamSetting, setAgentDreamSetting, startMemoryDream, listMemoryDreams,
        ]
    }
}

extension Connection {
    public func dreamSetting() async throws -> AgentDreamSetting {
        struct Answer: Decodable, Sendable { let GetAgentDreamSetting: AgentDreamSetting }
        return try await execute(Documents.getAgentDreamSetting, as: Answer.self).GetAgentDreamSetting
    }

    @discardableResult
    public func setDreamSetting(isEnabled: Bool, budgetSharePercent: Int, tokenCap: Int) async throws -> AgentDreamSetting {
        struct Answer: Decodable, Sendable { let SetAgentDreamSetting: AgentDreamSetting }
        return try await execute(
            Documents.setAgentDreamSetting,
            variables: [
                "isDreamEnabled": .bool(isEnabled), "dreamBudgetSharePercent": .number(Double(min(max(budgetSharePercent, 1), 100))),
                "dreamTokenCap": .number(Double(max(tokenCap, 0))),
            ], as: Answer.self
        ).SetAgentDreamSetting
    }

    /// Starts a dream in the background. The server says why when it cannot: dreaming is off, or one is running.
    public func startMemoryDream() async throws {
        _ = try await execute(Documents.startMemoryDream, as: JSONValue.self)
    }

    /// The runs, newest first. Only an organization's administrators may read them.
    public func memoryDreams(first: Int = 20) async throws -> [MemoryDream] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let memoryDreams: [MemoryDream]? }
            let ListMemoryDreams: List?
        }
        return try await execute(Documents.listMemoryDreams, variables: ["options": .object(["first": .number(Double(first))])], as: Answer.self)
            .ListMemoryDreams?.memoryDreams ?? []
    }
}

extension Documents {
    public static let listConversationArtifacts = """
        query ListConversationArtifacts($conversationId: String) {
          ListConversationArtifacts(conversationId: $conversationId) { id conversationId attachmentId title artifactKind sizeBytes createdAt }
        }
        """

    static var artifactDocuments: [String] { [listConversationArtifacts] }
}

extension Connection {
    /// The pages, drawings and documents the assistant made in a conversation, oldest first.
    public func conversationArtifacts(conversationId: String) async throws -> [ArtifactReference] {
        struct Row: Decodable, Sendable {
            let id: String
            let title: String?
            let artifactKind: String?
            let sizeBytes: Int64?
            let threadRootMessageId: String?
            let createdAt: String?
        }
        struct Answer: Decodable, Sendable { let ListConversationArtifacts: [Row]? }
        let rows = try await execute(Documents.listConversationArtifacts, variables: ["conversationId": .string(conversationId)], as: Answer.self)
            .ListConversationArtifacts ?? []
        return rows.compactMap { row in
            guard let kind = row.artifactKind.flatMap(ArtifactReference.Kind.init(rawValue:)) else { return nil }
            return ArtifactReference(
                id: row.id, title: row.title ?? "", kind: kind, sizeBytes: row.sizeBytes, threadRootMessageId: row.threadRootMessageId,
                createdAt: row.createdAt)
        }
    }
}
