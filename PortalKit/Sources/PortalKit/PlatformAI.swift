import Foundation

/// AIProvider is a model the assistant can be run on: a vendor's API, one model name and the key that pays for it.
public struct AIProvider: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// `anthropic`, `openai` or `gemini`.
    public let providerType: String?
    public let modelName: String?
    public let baseUrl: String?
    public let isEnabled: Bool?
    public let capabilities: [String]?
    public let contextWindow: Int?
    public let maxOutputTokens: Int?
    /// The end of the stored key, enough to tell which one is in use. The key itself is never sent back.
    public let apiKeyFingerprint: String?
    public let modifiedAt: String?

    public var shownName: String { (name ?? "").isEmpty ? id : name! }
    public var hasAPIKey: Bool { !(apiKeyFingerprint ?? "").isEmpty }

    public var typeName: String { AIProviderType(rawValue: providerType ?? "")?.title ?? (providerType ?? "") }
}

public enum AIProviderType: String, CaseIterable, Equatable, Sendable {
    case anthropic
    case openai
    case gemini

    public var title: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }
}

/// AIAgent is an assistant persona: its instructions and the providers it runs on.
public struct AIAgent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let description: String?
    public let systemPrompt: String?
    public let isEnabled: Bool?
    public let isMain: Bool?
    public let defaultProviderId: String?
    public let quickProviderId: String?
    public let tools: [String]?
    public let modifiedAt: String?

    public var shownName: String { (name ?? "").isEmpty ? id : name! }
}

/// AIGrants are the providers and agents an organization may use.
public struct AIGrants: Equatable, Sendable {
    public var providerIds: Set<String>
    public var agentIds: Set<String>

    public init(providerIds: Set<String> = [], agentIds: Set<String> = []) {
        self.providerIds = providerIds
        self.agentIds = agentIds
    }
}

public enum AICatalog {
    /// Providers by name; the main agent first among agents, then by name.
    public static func orderedProviders(_ providers: [AIProvider]) -> [AIProvider] {
        providers.sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
    }

    public static func orderedAgents(_ agents: [AIAgent]) -> [AIAgent] {
        agents.sorted {
            if ($0.isMain == true) != ($1.isMain == true) { return $0.isMain == true }
            return $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending
        }
    }

    /// The name of the provider with the id, or a stand-in when it is gone.
    public static func providerName(_ id: String?, in providers: [AIProvider]) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return providers.first { $0.id == id }?.shownName ?? "Removed provider"
    }
}

extension Documents {
    static let aiProviderFields = "id name providerType modelName baseUrl isEnabled capabilities contextWindow maxOutputTokens apiKeyFingerprint modifiedAt"
    static let aiAgentFields = "id name description systemPrompt isEnabled isMain defaultProviderId quickProviderId tools modifiedAt"

    public static let listAIProviders = """
        query ListAIProviders($options: ListOptionsInput) {
          ListProviders(options: $options) { providers { \(aiProviderFields) } meta { totalCount } }
        }
        """

    public static let listAIAgents = """
        query ListAIAgents($options: ListOptionsInput) {
          ListAgents(options: $options) { agents { \(aiAgentFields) } meta { totalCount } }
        }
        """

    public static let createAIProvider = """
        mutation CreateAIProvider($provider: ProviderInput!) { CreateProvider(provider: $provider) { provider { \(aiProviderFields) } } }
        """

    public static let modifyAIProvider = """
        mutation ModifyAIProvider($providerId: String!, $provider: ProviderInput!) {
          ModifyProvider(providerId: $providerId, provider: $provider) { provider { \(aiProviderFields) } }
        }
        """

    public static let setAIProviderKey = """
        mutation SetAIProviderKey($providerId: String!, $apiKey: String!) {
          SetProviderAPIKey(providerId: $providerId, apiKey: $apiKey) { provider { \(aiProviderFields) } }
        }
        """

    public static let deleteAIProvider = """
        mutation DeleteAIProvider($providerId: String!) { DeleteProvider(providerId: $providerId) }
        """

    public static let createAIAgent = """
        mutation CreateAIAgent($agent: AgentInput!) { CreateAgent(agent: $agent) { agent { \(aiAgentFields) } } }
        """

    public static let modifyAIAgent = """
        mutation ModifyAIAgent($agentId: String!, $agent: AgentInput!) {
          ModifyAgent(agentId: $agentId, agent: $agent) { agent { \(aiAgentFields) } }
        }
        """

    public static let deleteAIAgent = """
        mutation DeleteAIAgent($agentId: String!) { DeleteAgent(agentId: $agentId) }
        """

    public static let listOrganizationProviders = """
        query ListOrganizationProviders($organizationId: String) {
          ListOrganizationProviders(organizationId: $organizationId) { organizationId providerId grantedAt }
        }
        """

    public static let listOrganizationAgents = """
        query ListOrganizationAgents($organizationId: String) {
          ListOrganizationAgents(organizationId: $organizationId) { organizationId agentId grantedAt }
        }
        """

    public static let grantOrganizationProvider = """
        mutation GrantOrganizationProvider($organizationId: String!, $providerId: String!) {
          GrantOrganizationProvider(organizationId: $organizationId, providerId: $providerId) { grant { organizationId providerId grantedAt } }
        }
        """

    public static let revokeOrganizationProvider = """
        mutation RevokeOrganizationProvider($organizationId: String!, $providerId: String!) {
          RevokeOrganizationProvider(organizationId: $organizationId, providerId: $providerId)
        }
        """

    public static let grantOrganizationAgent = """
        mutation GrantOrganizationAgent($organizationId: String!, $agentId: String!) {
          GrantOrganizationAgent(organizationId: $organizationId, agentId: $agentId) { grant { organizationId agentId grantedAt } }
        }
        """

    public static let revokeOrganizationAgent = """
        mutation RevokeOrganizationAgent($organizationId: String!, $agentId: String!) {
          RevokeOrganizationAgent(organizationId: $organizationId, agentId: $agentId)
        }
        """

    static var aiDocuments: [String] {
        [
            listAIProviders, listAIAgents, createAIProvider, modifyAIProvider, setAIProviderKey, deleteAIProvider, createAIAgent, modifyAIAgent,
            deleteAIAgent, listOrganizationProviders, listOrganizationAgents, grantOrganizationProvider, revokeOrganizationProvider,
            grantOrganizationAgent, revokeOrganizationAgent,
        ]
    }
}

extension Connection {
    public func aiProviders() async throws -> [AIProvider] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let providers: [AIProvider?]? }
            let ListProviders: List?
        }
        let rows = try await execute(Documents.listAIProviders, variables: ["options": .object(["first": .number(200)])], as: Answer.self)
            .ListProviders?.providers?.compactMap { $0 } ?? []
        return AICatalog.orderedProviders(rows)
    }

    public func aiAgents() async throws -> [AIAgent] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let agents: [AIAgent?]? }
            let ListAgents: List?
        }
        let rows = try await execute(Documents.listAIAgents, variables: ["options": .object(["first": .number(200)])], as: Answer.self)
            .ListAgents?.agents?.compactMap { $0 } ?? []
        return AICatalog.orderedAgents(rows)
    }

    /// Adds a provider. Its key is set afterwards, because the server never takes one with the rest.
    public func createAIProvider(name: String, type: AIProviderType, modelName: String, baseUrl: String) async throws {
        var provider: [String: JSONValue] = ["name": .string(name), "providerType": .string(type.rawValue), "modelName": .string(modelName), "isEnabled": .bool(true)]
        if !baseUrl.isEmpty { provider["baseUrl"] = .string(baseUrl) }
        _ = try await execute(Documents.createAIProvider, variables: ["provider": .object(provider)], as: JSONValue.self)
    }

    /// Changes only the fields given.
    public func modifyAIProvider(id: String, name: String? = nil, modelName: String? = nil, baseUrl: String? = nil, isEnabled: Bool? = nil) async throws {
        var provider: [String: JSONValue] = [:]
        if let name { provider["name"] = .string(name) }
        if let modelName { provider["modelName"] = .string(modelName) }
        if let baseUrl { provider["baseUrl"] = .string(baseUrl) }
        if let isEnabled { provider["isEnabled"] = .bool(isEnabled) }
        _ = try await execute(Documents.modifyAIProvider, variables: ["providerId": .string(id), "provider": .object(provider)], as: JSONValue.self)
    }

    public func setAIProviderKey(id: String, apiKey: String) async throws {
        _ = try await execute(Documents.setAIProviderKey, variables: ["providerId": .string(id), "apiKey": .string(apiKey)], as: JSONValue.self)
    }

    public func deleteAIProvider(id: String) async throws {
        _ = try await execute(Documents.deleteAIProvider, variables: ["providerId": .string(id)], as: JSONValue.self)
    }

    public func createAIAgent(name: String, description: String, systemPrompt: String, defaultProviderId: String?) async throws {
        var agent: [String: JSONValue] = ["name": .string(name), "description": .string(description), "systemPrompt": .string(systemPrompt), "isEnabled": .bool(true)]
        if let defaultProviderId, !defaultProviderId.isEmpty { agent["defaultProviderId"] = .string(defaultProviderId) }
        _ = try await execute(Documents.createAIAgent, variables: ["agent": .object(agent)], as: JSONValue.self)
    }

    /// Changes only the fields given. A provider id of "" takes the provider away.
    public func modifyAIAgent(
        id: String, name: String? = nil, description: String? = nil, systemPrompt: String? = nil, isEnabled: Bool? = nil, defaultProviderId: String? = nil,
        quickProviderId: String? = nil
    ) async throws {
        var agent: [String: JSONValue] = [:]
        if let name { agent["name"] = .string(name) }
        if let description { agent["description"] = .string(description) }
        if let systemPrompt { agent["systemPrompt"] = .string(systemPrompt) }
        if let isEnabled { agent["isEnabled"] = .bool(isEnabled) }
        if let defaultProviderId { agent["defaultProviderId"] = .string(defaultProviderId) }
        if let quickProviderId { agent["quickProviderId"] = .string(quickProviderId) }
        _ = try await execute(Documents.modifyAIAgent, variables: ["agentId": .string(id), "agent": .object(agent)], as: JSONValue.self)
    }

    public func deleteAIAgent(id: String) async throws {
        _ = try await execute(Documents.deleteAIAgent, variables: ["agentId": .string(id)], as: JSONValue.self)
    }

    /// The providers and agents an organization may use.
    public func aiGrants(organizationId: String) async throws -> AIGrants {
        let variables: [String: JSONValue] = ["organizationId": .string(organizationId)]
        async let providers = execute(Documents.listOrganizationProviders, variables: variables, as: ProviderAnswer.self)
        async let agents = execute(Documents.listOrganizationAgents, variables: variables, as: AgentAnswer.self)
        let providerIds = try await providers.ListOrganizationProviders?.compactMap { $0?.providerId } ?? []
        let agentIds = try await agents.ListOrganizationAgents?.compactMap { $0?.agentId } ?? []
        return AIGrants(providerIds: Set(providerIds), agentIds: Set(agentIds))
    }

    public func setProviderGrant(organizationId: String, providerId: String, isGranted: Bool) async throws {
        let variables: [String: JSONValue] = ["organizationId": .string(organizationId), "providerId": .string(providerId)]
        _ = try await execute(isGranted ? Documents.grantOrganizationProvider : Documents.revokeOrganizationProvider, variables: variables, as: JSONValue.self)
    }

    public func setAgentGrant(organizationId: String, agentId: String, isGranted: Bool) async throws {
        let variables: [String: JSONValue] = ["organizationId": .string(organizationId), "agentId": .string(agentId)]
        _ = try await execute(isGranted ? Documents.grantOrganizationAgent : Documents.revokeOrganizationAgent, variables: variables, as: JSONValue.self)
    }
}

private struct ProviderGrantRow: Decodable, Sendable { let providerId: String? }
private struct AgentGrantRow: Decodable, Sendable { let agentId: String? }
private struct ProviderAnswer: Decodable, Sendable { let ListOrganizationProviders: [ProviderGrantRow?]? }
private struct AgentAnswer: Decodable, Sendable { let ListOrganizationAgents: [AgentGrantRow?]? }
