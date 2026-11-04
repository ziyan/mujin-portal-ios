import Foundation

/// LinkKind says where a link should open.
public enum LinkKind: Equatable, Sendable {
    /// Portal itself: the account's server.
    case portal
    /// A controller or virtual controller web UI, which Portal's proxy serves
    /// as `<id>-live`, `<id>-cloud` or `<id>-virtual` under the server's host.
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
        // Only the three proxy hosts are controllers: they take the session
        // cookie from the handoff. Any other subdomain is not Portal's to sign in.
        if ControllerLinks.isControllerHost(host, serverHost: base) { return .controller }
        return .external
    }

    /// The full address of a link. The assistant writes a Portal page as a path, such as `/controller/<id>`, which the web app
    /// reads as a page of its own server. A link with a scheme is left as it is.
    public static func absolute(_ url: URL, server: ServerAddress) -> URL {
        guard url.scheme == nil else { return url }
        return URL(string: url.relativeString, relativeTo: server.url)?.absoluteURL ?? url
    }

    /// Whether the account's session cookie is meant for this link.
    public static func opensInApp(_ kind: LinkKind) -> Bool {
        kind == .portal || kind == .controller
    }
}
