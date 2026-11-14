import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// ArtifactSandbox holds the rules for showing a page the assistant made, the same ones the web's frame follows. The page runs in
/// a frame sandboxed to its own scripts, so its origin is opaque and it cannot reach the app or the person's session. Only the
/// address goes in, with the theme and title in its fragment, and only a height message comes out. The app serves the frame,
/// the page and the artifact kit from a scheme of its own, so the web view never reaches the network itself.
public enum ArtifactSandbox {
    /// The scheme the app serves an artifact's frame, page and kit from.
    public static let scheme = "portal-artifact"
    /// The address of the frame that holds the page.
    public static let frameURL = URL(string: "\(scheme)://artifact/frame")!
    /// Where the page loads the chart library and style sheet from, as on the server.
    public static let kitPath = "/artifact-kit/"

    /// The inline card is clamped between these heights, in points, as the web's frame is.
    public static let inlineHeightRange: ClosedRange<Double> = 120...640
    /// How tall the card is until the page says.
    public static let defaultHeight: Double = 320

    /// A hash of a text that is the same in every launch, unlike `hashValue`: FNV-1a over its bytes.
    public static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    public static func clampedHeight(_ measured: Double) -> Double {
        guard measured.isFinite else { return defaultHeight }
        return min(max(measured.rounded(.up), inlineHeightRange.lowerBound), inlineHeightRange.upperBound)
    }

    /// The page's address inside the frame. The fragment says the theme and the title the app already shows above the page; the
    /// page reads it on load and on every change, and a change of the fragment alone does not reload it.
    public static func pageURL(artifactId: String, isDark: Bool, title: String?) -> URL {
        let path = "/api/v1/artifact/" + (artifactId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? artifactId)
        return URL(string: "\(scheme)://artifact\(path)#" + fragment(isDark: isDark, title: title))!
    }

    public static func fragment(isDark: Bool, title: String?) -> String {
        let theme = "theme=\(isDark ? "dark" : "light")"
        guard let title, !title.isEmpty, let encoded = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return theme }
        return theme + "&title=" + encoded
    }

    /// The policy the page is served with: its own inline script and style and the kit, and nothing else, as the server serves it
    /// to the web's frame.
    public static let pageContentSecurityPolicy =
        "default-src 'none'; script-src 'unsafe-inline' \(scheme)://artifact\(kitPath); style-src 'unsafe-inline' \(scheme)://artifact\(kitPath); "
        + "img-src data: blob:; font-src data: \(scheme)://artifact\(kitPath); media-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'"

    /// A WebKit content rule list that blocks every address but the app's own scheme. Returned as JSON text.
    public static func contentRuleListJSON() -> String {
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "^\(scheme)://artifact/"], "action": ["type": "ignore-previous-rules"]],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The page as the frame shows it: the policy first, so it holds for everything the page says after it.
    public static func framedPage(_ html: Data) -> Data {
        Data("<meta http-equiv=\"Content-Security-Policy\" content=\"\(pageContentSecurityPolicy)\">".utf8) + html
    }

    /// The frame: a page of the app's own holding the artifact in a frame sandboxed to its scripts. It passes the height the
    /// artifact reports, from that frame only, to the app, and takes a new address when the theme changes.
    public static func frameHTML(pageURL: URL, frameTitle: String) -> String {
        let escapedTitle = frameTitle.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
            <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-src \(scheme)://artifact/">
            <style>html, body { margin: 0; height: 100%; background: transparent; } iframe { display: block; border: 0; width: 100%; height: 100%; }</style>
            </head><body><iframe id="page" sandbox="allow-scripts" referrerpolicy="no-referrer" title="\(escapedTitle)"></iframe>
            <script>
            (function () {
              var frame = document.getElementById("page");
              window.addEventListener("message", function (event) {
                if (event.source !== frame.contentWindow || event.origin !== "null") { return; }
                var asked = event.data && event.data.portalArtifact && event.data.portalArtifact.height;
                if (typeof asked === "number") { window.webkit.messageHandlers.artifactHeight.postMessage(asked); }
              });
              window.portalShowPage = function (address) { frame.src = address; };
              frame.src = "\(pageURL.absoluteString)";
            })();
            </script></body></html>
            """
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
    /// A file of the artifact kit, the chart library and style sheet a page may load. It is public, so it is fetched without the
    /// account's token.
    public func artifactKitData(name: String) async throws -> (data: Data, contentType: String) {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { throw PortalError.unreadableAnswer }
        var request = URLRequest(url: account.server.endpoint(ArtifactSandbox.kitPath + name))
        request.timeoutInterval = 60
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw PortalError.refused("HTTP \(response.statusCode)") }
        return (data, response.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream")
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
