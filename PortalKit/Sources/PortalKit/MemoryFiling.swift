import Foundation

/// MemoryFiling is one pass that filed a quiet conversation into memory.
public struct MemoryFiling: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// `conversation` or `chat`.
    public let sourceKind: String?
    public let conversationId: String?
    public let chatId: String?
    /// `automatic` or `requested`.
    public let filingTrigger: String?
    public let writtenFactCount: Int?
    public let createdAt: String?
    /// The facts the pass wrote that still exist and that the caller can read.
    public let facts: [MemoryFact]?

    public init(id: String, filingTrigger: String? = "automatic", writtenFactCount: Int? = nil, createdAt: String? = nil, facts: [MemoryFact]? = nil) {
        self.id = id
        self.filingTrigger = filingTrigger
        self.writtenFactCount = writtenFactCount
        self.createdAt = createdAt
        self.facts = facts
        self.sourceKind = nil
        self.conversationId = nil
        self.chatId = nil
    }

    public var date: Date? { PortalDate.parse(createdAt) }
}

public enum MemoryFilingNote {
    /// The note under a conversation comes from the latest filing that still has facts.
    public static func latestWithFacts(_ filings: [MemoryFiling]) -> MemoryFiling? {
        filings.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.first { !($0.facts ?? []).isEmpty }
    }
}

/// AgentMemorySetting is whether conversations are filed into memory.
public struct AgentMemorySetting: Codable, Equatable, Sendable {
    public let organizationId: String?
    public let isFilingEnabledForUser: Bool?
    public let isFilingEnabledForOrganization: Bool?
    public let filingProviderId: String?
    public let canManageOrganization: Bool?

    /// Filing happens only when both the person's switch and the organization's are on.
    public var isFilingActive: Bool { isFilingEnabledForUser == true && isFilingEnabledForOrganization == true }
}

extension Documents {
    static let memorySettingFields = "organizationId isFilingEnabledForUser isFilingEnabledForOrganization filingProviderId canManageOrganization"

    public static let listMemoryFilings = """
        query ListMemoryFilings($conversationId: String, $limit: Int64) {
          ListMemoryFilings(conversationId: $conversationId, limit: $limit) {
            id sourceKind conversationId chatId filingTrigger writtenFactCount createdAt
            facts { id number pagePath sentence isInferred memoryScope siteId }
          }
        }
        """

    public static let forgetFiledMemoryFact = """
        mutation ForgetFiledMemoryFact($memoryFilingId: String, $memoryFactId: String) {
          ForgetFiledMemoryFact(memoryFilingId: $memoryFilingId, memoryFactId: $memoryFactId) { memoryFactId memoryPageId }
        }
        """

    public static let getAgentMemorySetting = """
        query GetAgentMemorySetting { GetAgentMemorySetting { \(memorySettingFields) } }
        """

    public static let setAgentMemoryFiling = """
        mutation SetAgentMemoryFiling($isEnabled: Boolean) { SetAgentMemoryFiling(isEnabled: $isEnabled) { \(memorySettingFields) } }
        """

    static var memoryFilingDocuments: [String] {
        [listMemoryFilings, forgetFiledMemoryFact, getAgentMemorySetting, setAgentMemoryFiling]
    }
}

extension Connection {
    /// The passes that filed this conversation, newest first.
    public func memoryFilings(conversationId: String, limit: Int = 20) async throws -> [MemoryFiling] {
        struct Answer: Decodable, Sendable { let ListMemoryFilings: [MemoryFiling]? }
        return try await execute(
            Documents.listMemoryFilings, variables: ["conversationId": .string(conversationId), "limit": .number(Double(min(limit, 50)))], as: Answer.self
        ).ListMemoryFilings ?? []
    }

    public func forgetFiledFact(filingId: String, factId: String) async throws {
        _ = try await execute(Documents.forgetFiledMemoryFact, variables: ["memoryFilingId": .string(filingId), "memoryFactId": .string(factId)], as: JSONValue.self)
    }

    public func memorySetting() async throws -> AgentMemorySetting {
        struct Answer: Decodable, Sendable { let GetAgentMemorySetting: AgentMemorySetting }
        return try await execute(Documents.getAgentMemorySetting, as: Answer.self).GetAgentMemorySetting
    }

    @discardableResult
    public func setMemoryFiling(isEnabled: Bool) async throws -> AgentMemorySetting {
        struct Answer: Decodable, Sendable { let SetAgentMemoryFiling: AgentMemorySetting }
        return try await execute(Documents.setAgentMemoryFiling, variables: ["isEnabled": .bool(isEnabled)], as: Answer.self).SetAgentMemoryFiling
    }
}
