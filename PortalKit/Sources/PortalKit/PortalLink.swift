import Foundation

/// PortalLink is a page of the Portal web app that the app has a screen for:
/// the same pages Portal's server turns into a native card when a link to one
/// is sent in a chat. It is read from a web address and written back to one,
/// so a link copied in the app opens the same page in a browser.
public enum PortalLink: Equatable, Hashable, Sendable {
    /// `/ticket/<sequence>`: the number shown as "#12", not the ticket's id.
    case ticket(sequence: Int64)
    /// `/controller/<id>`
    case controller(id: String)
    /// `/virtualcontroller/<id>`
    case virtualController(id: String)
    /// `/release/<id>`
    case release(id: String)

    /// Reads a web address on the account's own server. Nil for another
    /// server, a lookalike host, a path the app has no screen for, or an id
    /// with characters Portal's ids never have. A trailing slash, a query,
    /// a fragment and any page below the one (such as `/controller/<id>/backups`)
    /// are ignored, and percent-encoding is undone, as Portal's own parser does.
    public init?(url: URL, server: ServerAddress) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        guard let host = url.host?.lowercased(), host == (server.url.host ?? "").lowercased() else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? "" }
        guard segments.count >= 2 else { return nil }
        let identifier = segments[1]
        switch segments[0].lowercased() {
        case "ticket":
            // A ticket page has nothing below it.
            guard segments.count == 2, Self.isDigits(identifier), let sequence = Int64(identifier), sequence > 0 else { return nil }
            self = .ticket(sequence: sequence)
        case "controller":
            guard Self.isIdentifier(identifier) else { return nil }
            self = .controller(id: identifier)
        case "virtualcontroller":
            guard Self.isIdentifier(identifier) else { return nil }
            self = .virtualController(id: identifier)
        case "release":
            guard Self.isIdentifier(identifier) else { return nil }
            self = .release(id: identifier)
        default:
            return nil
        }
    }

    /// The path of the page on the server, which is also what the web app's address bar shows.
    public var path: String {
        switch self {
        case .ticket(let sequence): "/ticket/\(sequence)"
        case .controller(let id): "/controller/\(id)"
        case .virtualController(let id): "/virtualcontroller/\(id)"
        case .release(let id): "/release/\(id)"
        }
    }

    /// The address to copy or share: the page on the account's server.
    public func url(server: ServerAddress) -> URL {
        server.endpoint(path)
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    /// Portal's ids are letters, digits, `_` and `-`.
    private static func isIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D }
    }
}
