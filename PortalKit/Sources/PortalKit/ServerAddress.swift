import Foundation

/// ServerAddress is a Portal instance: an https origin, with no path.
public struct ServerAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The production instance a first sign-in defaults to.
    public static let production = ServerAddress(validated: URL(string: "https://portal.mujin.cloud")!)

    /// The server a first sign-in offers. A build can name another one, as a
    /// bare host, in the Info.plist (`PortalDefaultServer`).
    public static var signInDefault: ServerAddress {
        signInDefault(configured: Bundle.main.object(forInfoDictionaryKey: "PortalDefaultServer") as? String)
    }

    /// A build that names no server, or one that does not parse, offers
    /// production.
    public static func signInDefault(configured: String?) -> ServerAddress {
        guard let configured, !configured.hasPrefix("$("), let address = try? ServerAddress(configured) else {
            return .production
        }
        return address
    }

    public let url: URL

    private init(validated url: URL) {
        self.url = url
    }

    /// Reads what a person typed. A bare host gets https. Only https is
    /// accepted, except for a loopback host used while developing.
    public init(_ text: String) throws {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PortalError.invalidServerAddress }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty else {
            throw PortalError.invalidServerAddress
        }
        let isLoopback = host == "localhost" || host == "127.0.0.1"
        guard components.scheme == "https" || (components.scheme == "http" && isLoopback) else {
            throw PortalError.invalidServerAddress
        }
        guard components.user == nil, components.password == nil else { throw PortalError.invalidServerAddress }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.host = host.lowercased()
        guard let url = components.url else { throw PortalError.invalidServerAddress }
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// The address of a path on this server, such as "/api/v1/graphql".
    public func endpoint(_ path: String) -> URL {
        URL(string: description + (path.hasPrefix("/") ? path : "/" + path))!
    }

    /// The address as text, without a trailing slash.
    public var description: String {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// The host (and port), for showing a person which server an account is on.
    public var displayHost: String {
        if let port = url.port { return "\(url.host ?? ""):\(port)" }
        return url.host ?? description
    }

    /// The WebSocket address of the GraphQL subscription endpoint.
    public var subscriptionEndpoint: URL {
        var components = URLComponents(url: endpoint("/api/v1/graphql/subscribe"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        return components.url!
    }
}
