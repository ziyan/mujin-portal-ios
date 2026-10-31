import Foundation

/// SubscriptionMessage is one frame of the graphql-transport-ws protocol,
/// which Portal's /api/v1/graphql/subscribe endpoint speaks.
public enum SubscriptionMessage: Equatable, Sendable {
    public static let subprotocol = "graphql-transport-ws"

    /// Portal closes the socket with this code when the token behind it has
    /// expired or been revoked.
    public static let unauthorizedCloseCode = 4401

    case connectionInit
    case connectionAck
    case ping
    case pong
    case subscribe(id: String, query: String, variables: [String: JSONValue])
    case next(id: String, data: JSONValue?, errors: [Connection.GraphQLError])
    case error(id: String, errors: [Connection.GraphQLError])
    case complete(id: String)

    /// The frame as the text sent over the socket.
    public func encoded() throws -> String {
        var object: [String: JSONValue]
        switch self {
        case .connectionInit: object = ["type": .string("connection_init")]
        case .connectionAck: object = ["type": .string("connection_ack")]
        case .ping: object = ["type": .string("ping")]
        case .pong: object = ["type": .string("pong")]
        case .subscribe(let id, let query, let variables):
            object = ["type": .string("subscribe"), "id": .string(id), "payload": .object(["query": .string(query), "variables": .object(variables)])]
        case .complete(let id): object = ["type": .string("complete"), "id": .string(id)]
        case .next, .error: throw PortalError.unreadableAnswer
        }
        return String(decoding: try JSONEncoder().encode(JSONValue.object(object)), as: UTF8.self)
    }

    /// Reads a frame the server sent.
    public init(decoding text: String) throws {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), let type = value["type"]?.stringValue else {
            throw PortalError.unreadableAnswer
        }
        let id = value["id"]?.stringValue ?? ""
        func errors(from payload: JSONValue?) -> [Connection.GraphQLError] {
            guard case .array(let items)? = payload else { return [] }
            return items.compactMap { $0["message"]?.stringValue.map { Connection.GraphQLError(message: $0) } }
        }
        switch type {
        case "connection_init": self = .connectionInit
        case "connection_ack": self = .connectionAck
        case "ping": self = .ping
        case "pong": self = .pong
        case "complete": self = .complete(id: id)
        case "next":
            self = .next(id: id, data: value["payload"]?["data"], errors: errors(from: value["payload"]?["errors"]))
        case "error":
            self = .error(id: id, errors: errors(from: value["payload"]))
        default:
            throw PortalError.unreadableAnswer
        }
    }
}
