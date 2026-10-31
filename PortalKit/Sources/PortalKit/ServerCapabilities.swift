import Foundation

/// ServerCapabilities is the list of operations a Portal server offers. The
/// app builds some features against a contract that older servers do not have
/// yet; it asks here before it shows them.
public struct ServerCapabilities: Equatable, Sendable {
    public let queryNames: Set<String>
    public let mutationNames: Set<String>
    public let subscriptionNames: Set<String>

    public init(queryNames: Set<String> = [], mutationNames: Set<String> = [], subscriptionNames: Set<String> = []) {
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

    /// Chats between people. The operations are not in the schema yet, so
    /// this is false until one of the names the backend plan uses appears.
    public var offersChats: Bool { offersQuery("ListChats") || offersQuery("ListChatRooms") }

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
            struct Field: Decodable, Sendable { let name: String }
            let fields: [Field]?
        }
        struct Schema: Decodable, Sendable {
            let queryType: RootType?
            let mutationType: RootType?
            let subscriptionType: RootType?
        }
        let __schema: Schema
    }

    init(_ introspection: Introspection) {
        func names(_ type: Introspection.RootType?) -> Set<String> { Set((type?.fields ?? []).map(\.name)) }
        self.init(
            queryNames: names(introspection.__schema.queryType), mutationNames: names(introspection.__schema.mutationType),
            subscriptionNames: names(introspection.__schema.subscriptionType))
    }
}

extension Documents {
    /// Every operation name the server offers, by kind.
    public static let serverCapabilities = """
        query ServerCapabilities {
          __schema {
            queryType { fields { name } }
            mutationType { fields { name } }
            subscriptionType { fields { name } }
          }
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
