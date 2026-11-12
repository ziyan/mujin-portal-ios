import Foundation
import Testing

@testable import PortalKit

@Suite struct ArtifactTests {
    @Test func theThemeAndTitleTravelInTheFragmentOnly() {
        let dark = ArtifactSandbox.pageURL(artifactId: "artifact01", isDark: true, title: "Weekly throughput")
        let light = ArtifactSandbox.pageURL(artifactId: "artifact01", isDark: false, title: nil)
        #expect(dark.absoluteString == "portal-artifact://artifact/api/v1/artifact/artifact01#theme=dark&title=Weekly%20throughput")
        #expect(light.absoluteString == "portal-artifact://artifact/api/v1/artifact/artifact01#theme=light")
        #expect(dark.path == light.path)
    }

    @Test func heightIsClampedAsOnTheWeb() {
        #expect(ArtifactSandbox.clampedHeight(40) == 120)
        #expect(ArtifactSandbox.clampedHeight(300.2) == 301)
        #expect(ArtifactSandbox.clampedHeight(5_000) == 640)
        #expect(ArtifactSandbox.clampedHeight(.nan) == 320)
    }

    @Test func theRuleListBlocksEverythingButTheAppsOwnScheme() throws {
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(ArtifactSandbox.contentRuleListJSON().utf8)) as? [[String: Any]])
        #expect(rules.count == 2)
        #expect((rules[0]["action"] as? [String: String])?["type"] == "block")
        #expect((rules[0]["trigger"] as? [String: String])?["url-filter"] == ".*")
        #expect((rules[1]["action"] as? [String: String])?["type"] == "ignore-previous-rules")
        #expect((rules[1]["trigger"] as? [String: String])?["url-filter"] == "^portal-artifact://artifact/")
    }

    @Test func theFrameSandboxesThePageToItsScriptsAndListensToItAlone() {
        let frame = ArtifactSandbox.frameHTML(
            pageURL: ArtifactSandbox.pageURL(artifactId: "artifact01", isDark: true, title: nil), frameTitle: "A \"chart\" <here>")
        #expect(frame.contains(#"sandbox="allow-scripts""#))
        #expect(!frame.contains("allow-same-origin"))
        #expect(frame.contains("event.source !== frame.contentWindow"))
        #expect(frame.contains(#"title="A &quot;chart&quot; &lt;here>""#))
    }

    @Test func thePageCarriesItsPolicyFirst() {
        let page = String(decoding: ArtifactSandbox.framedPage(Data("<h1>Chart</h1>".utf8)), as: UTF8.self)
        #expect(page.hasPrefix(#"<meta http-equiv="Content-Security-Policy""#))
        #expect(page.contains("connect-src 'none'"))
        #expect(page.hasSuffix("<h1>Chart</h1>"))
    }

    @Test func kitFilesAreFetchedWithoutTheToken() async throws {
        let (connection, transport) = scriptedConnection { _, _ in [:] }
        _ = try? await connection.artifactKitData(name: "kit.js")
        #expect(transport.requests.first?.url?.absoluteString == "https://portal.example.test/artifact-kit/kit.js")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        await #expect(throws: PortalError.self) { try await connection.artifactKitData(name: "../api/v1/me") }
    }

    @Test func downloadNamesAreSafeFileNames() {
        #expect(ArtifactSandbox.downloadFileName(title: "Weekly throughput", kind: .html) == "Weekly throughput.html")
        #expect(ArtifactSandbox.downloadFileName(title: "a/b:c", kind: .svg) == "a b c.svg")
        #expect(ArtifactSandbox.downloadFileName(title: "  ", kind: .markdown) == "Artifact.md")
    }

    @Test func downloadsAskForTheAttachmentForm() async throws {
        let (connection, transport) = scriptedConnection { _, _ in [:] }
        _ = try? await connection.artifactData(id: "artifact01", isDownload: true)
        #expect(transport.requests.first?.url?.absoluteString == "https://portal.example.test/api/v1/artifact/artifact01?download=1")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
    }

    @Test func onlyApiPathsAreFetched() async {
        let (connection, transport) = scriptedConnection { _, _ in [:] }
        await #expect(throws: PortalError.self) { try await connection.fetch(path: "https://elsewhere.example.test/x") }
        #expect(transport.requests.isEmpty)
    }
}
