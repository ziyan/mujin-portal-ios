import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// ArtifactSandbox holds the rules for showing a page the assistant made.
/// The page runs with an opaque origin and may load only the artifact kit
/// from the server it came from; the app adds a script bridge for nothing,
/// and blocks every other address before the page can ask for it.
public enum ArtifactSandbox {
    /// The inline card is clamped between these heights, in points. The full-size view is not.
    public static let inlineHeightRange: ClosedRange<Double> = 120...640

    public static func clampedHeight(_ measured: Double) -> Double {
        guard measured.isFinite else { return inlineHeightRange.lowerBound }
        return min(max(measured, inlineHeightRange.lowerBound), inlineHeightRange.upperBound)
    }

    /// Where a page is loaded from. Only the fragment carries the theme, so
    /// changing the theme later does not reload the page.
    public static func pageURL(server: ServerAddress, artifactId: String, isDark: Bool) -> URL {
        URL(string: server.endpoint("/api/v1/artifact/\(artifactId)").absoluteString + "#" + themeFragment(isDark: isDark))!
    }

    public static func themeFragment(isDark: Bool) -> String { "theme=\(isDark ? "dark" : "light")" }

    /// A WebKit content rule list that blocks every address except the
    /// artifact's own server. Returned as JSON text.
    public static func contentRuleListJSON(server: ServerAddress) -> String {
        let scheme = server.url.scheme ?? "https"
        let escapedHost = (server.url.host ?? "").replacingOccurrences(of: ".", with: "\\.")
        let port = server.url.port.map { ":\($0)" } ?? ""
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "^\(scheme)://\(escapedHost)\(port)/"], "action": ["type": "ignore-previous-rules"]],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The file name a downloaded artifact gets.
    public static func downloadFileName(title: String, kind: ArtifactReference.Kind) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var base = title.components(separatedBy: invalid).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "Artifact" }
        if base.count > 60 { base = String(base.prefix(60)).trimmingCharacters(in: .whitespaces) }
        switch kind {
        case .html: return base + ".html"
        case .svg: return base + ".svg"
        case .markdown: return base + ".md"
        }
    }
}

extension Connection {
    /// The page address of an artifact on this account's server.
    public func artifactPageURL(id: String, isDark: Bool) -> URL {
        ArtifactSandbox.pageURL(server: account.server, artifactId: id, isDark: isDark)
    }

    /// A file from the server with the account's token: an artifact's bytes
    /// (a download when `isDownload`), or an attachment by its path.
    public func artifactData(id: String, isDownload: Bool) async throws -> Data {
        try await fetch(path: "/api/v1/artifact/\(id)" + (isDownload ? "?download=1" : ""))
    }

    public func fetch(path: String) async throws -> Data {
        guard path.hasPrefix("/api/") else { throw PortalError.unreadableAnswer }
        var request = URLRequest(url: account.server.endpoint(path))
        request.timeoutInterval = 60
        let (data, response) = try await send(authorizing: request)
        guard (200..<300).contains(response.statusCode) else {
            throw PortalError.refused("HTTP \(response.statusCode)")
        }
        return data
    }

    /// The text of a markdown artifact.
    public func artifactText(id: String) async throws -> String {
        String(decoding: try await artifactData(id: id, isDownload: false), as: UTF8.self)
    }
}
