import Foundation

/// ServerCapabilities is the list of operations a Portal server offers. The
/// app builds some features against a contract that older servers do not have
/// yet; it asks here before it shows them.
public struct ServerCapabilities: Equatable, Sendable {
    public let queryNames: Set<String>
    public let mutationNames: Set<String>
    public let subscriptionNames: Set<String>
    /// The arguments the SendMessage mutation takes.
    public let sendMessageArgumentNames: Set<String>
    /// The arguments the ListConversationMessages query takes.
    public let listMessageArgumentNames: Set<String>
    /// The fields of the voice setting the GetAgentVoiceSetting query returns.
    public let voiceSettingFieldNames: Set<String>

    public init(
        queryNames: Set<String> = [], mutationNames: Set<String> = [], subscriptionNames: Set<String> = [], sendMessageArgumentNames: Set<String> = [],
        listMessageArgumentNames: Set<String> = [], voiceSettingFieldNames: Set<String> = []
    ) {
        self.voiceSettingFieldNames = voiceSettingFieldNames
        self.listMessageArgumentNames = listMessageArgumentNames
        self.sendMessageArgumentNames = sendMessageArgumentNames
        self.queryNames = Set(queryNames.map(Self.normalized))
        self.mutationNames = Set(mutationNames.map(Self.normalized))
        self.subscriptionNames = Set(subscriptionNames.map(Self.normalized))
    }

    /// Operation names are compared ignoring the case of the first letter,
    /// because Portal accepts both `ListTickets` and `listTickets`.
    static func normalized(_ name: String) -> String {
        name.prefix(1).lowercased() + name.dropFirst()
    }

    public func offersQuery(_ name: String) -> Bool { queryNames.contains(Self.normalized(name)) }
    public func offersMutation(_ name: String) -> Bool { mutationNames.contains(Self.normalized(name)) }
    public func offersSubscription(_ name: String) -> Bool { subscriptionNames.contains(Self.normalized(name)) }

    /// Chats between people.
    public var offersChats: Bool { offersQuery("ListChatCandidates") && offersMutation("StartDirectChat") }

    /// A chat for each site, for the people with access to it.
    public var offersSiteChats: Bool { offersMutation("OpenSiteChat") }

    /// Whether SendMessage takes structured mentions. Until it does, a
    /// message names an agent by its text and the server matches the name.
    public var offersStructuredMentions: Bool { sendMessageArgumentNames.contains("mentions") }

    public var offersPushRegistration: Bool { offersMutation("RegisterPushDevice") }
    public var offersWebSessionHandoff: Bool { offersMutation("CreateWebSessionHandoff") }
    /// Staff overview of every tenant's running work and ended turns.
    public var offersAgentOversight: Bool { offersQuery("GetAgentOversight") }
    /// The cross-tenant board of active monitoring. Not in the schema yet.
    public var offersMonitoringBoard: Bool { offersQuery("ListMonitoringBoard") || offersQuery("GetMonitoringBoard") }
    /// The server's notification subscription (for live inbox updates).
    public var offersNotificationFeed: Bool { offersSubscription("OnNotification") }

    /// What a schema introspection answer holds.
    struct Introspection: Decodable, Sendable {
        struct RootType: Decodable, Sendable {
            struct Field: Decodable, Sendable {
                struct Argument: Decodable, Sendable { let name: String }
                let name: String
                let args: [Argument]?
            }
            let fields: [Field]?
        }
        struct Schema: Decodable, Sendable {
            let queryType: RootType?
            let mutationType: RootType?
            let subscriptionType: RootType?
        }
        let __schema: Schema
        /// The voice setting type, asked for by name. Null on a server that has no such type.
        let voiceSetting: RootType?
    }

    init(_ introspection: Introspection) {
        func names(_ type: Introspection.RootType?) -> Set<String> { Set((type?.fields ?? []).map(\.name)) }
        let sendArguments = (introspection.__schema.mutationType?.fields ?? []).first { Self.normalized($0.name) == "sendMessage" }?.args ?? []
        let listArguments = (introspection.__schema.queryType?.fields ?? []).first { Self.normalized($0.name) == "listConversationMessages" }?.args ?? []
        self.init(
            queryNames: names(introspection.__schema.queryType), mutationNames: names(introspection.__schema.mutationType),
            subscriptionNames: names(introspection.__schema.subscriptionType), sendMessageArgumentNames: Set(sendArguments.map(\.name)),
            listMessageArgumentNames: Set(listArguments.map(\.name)), voiceSettingFieldNames: names(introspection.voiceSetting))
    }
}

extension Documents {
    /// Every operation name the server offers, by kind.
    public static let serverCapabilities = """
        query ServerCapabilities {
          __schema {
            queryType { fields { name args { name } } }
            mutationType { fields { name args { name } } }
            subscriptionType { fields { name } }
          }
          voiceSetting: __type(name: "AgentVoiceSetting") { fields { name } }
        }
        """
}

extension Connection {
    /// What the server offers. A server that refuses introspection offers
    /// nothing as far as the app can tell, so the answer is empty then.
    public func capabilities() async -> ServerCapabilities {
        guard let answer = try? await execute(Documents.serverCapabilities, as: ServerCapabilities.Introspection.self) else {
            return ServerCapabilities()
        }
        return ServerCapabilities(answer)
    }
}
