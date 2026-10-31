import Foundation

/// LinkKind says where a link should open.
public enum LinkKind: Equatable, Sendable {
    /// Portal itself: the account's server.
    case portal
    /// A controller or virtual controller web UI, served under the server's
    /// base domain as `<name>.<base domain>`.
    case controller
    /// Any other web address.
    case external
    /// Not a web address (mail, phone, an app's own scheme); the system handles it.
    case other
}

/// LinkClassifier decides, for an account, which links open in the built-in
/// web view (Portal and its controllers) and which in the system's Safari view.
public enum LinkClassifier {
    public static func classify(_ url: URL, server: ServerAddress) -> LinkKind {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return .other }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return .other }
        let base = (server.url.host ?? "").lowercased()
        if host == base { return .portal }
        // The base domain is the server's own host: controllers are its subdomains.
        if !base.isEmpty, host.hasSuffix("." + base) { return .controller }
        return .external
    }

    /// Whether the account's session cookie is meant for this link.
    public static func opensInApp(_ kind: LinkKind) -> Bool {
        kind == .portal || kind == .controller
    }
}
