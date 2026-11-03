import Foundation

/// ControllerLinkPayload reads what a controller shows to be linked: the address of Portal's link page, `https://<server>/link/<code>`,
/// the same address the web app opens. The code is a signed, URL-safe token that is case sensitive.
public enum ControllerLinkPayload {
    /// What a scanned or typed text turned out to be.
    public enum Reading: Equatable, Sendable {
        /// A link for the account's own server.
        case link(code: String)
        /// A link for another Portal server, which must not be sent this account's request.
        case otherServer(host: String)
        /// Anything else.
        case notControllerCode
    }

    /// The shortest code accepted. Real codes are far longer; this only keeps stray words out of the typed form.
    public static let minimumCodeLength = 16

    /// Reads the text of a QR code, or what a person typed or pasted: an address, or just the code.
    public static func read(_ text: String, server: ServerAddress) -> Reading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notControllerCode }
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed) else { return .notControllerCode }
            return read(url, server: server)
        }
        let typed = trimmed.filter { !$0.isWhitespace }
        return isCode(typed) ? .link(code: typed) : .notControllerCode
    }

    /// Reads an address, such as a universal link the app was opened with.
    public static func read(_ url: URL, server: ServerAddress) -> Reading {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host?.lowercased(), !host.isEmpty,
            components.user == nil, components.password == nil
        else { return .notControllerCode }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2, parts[0] == "link", isCode(parts[1]) else { return .notControllerCode }
        let own = server.displayHost.lowercased()
        let named = components.port.map { "\(host):\($0)" } ?? host
        guard named == own else { return .otherServer(host: named) }
        return .link(code: parts[1])
    }

    /// The address of the link page for a code on a server, as a controller shows it.
    public static func address(code: String, server: ServerAddress) -> String {
        server.description + "/link/" + code
    }

    private static func isCode(_ text: String) -> Bool {
        text.count >= minimumCodeLength
            && text.unicodeScalars.allSatisfy { scalar in
                (scalar.value < 128) && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
            }
    }
}
