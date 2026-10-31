import Foundation
import Testing

@testable import PortalKit

@Suite struct ArtifactTests {
    let server = try! ServerAddress("https://portal.example.test")

    @Test func theThemeTravelsInTheFragmentOnly() {
        let dark = ArtifactSandbox.pageURL(server: server, artifactId: "artifact01", isDark: true)
        let light = ArtifactSandbox.pageURL(server: server, artifactId: "artifact01", isDark: false)
        #expect(dark.absoluteString == "https://portal.example.test/api/v1/artifact/artifact01#theme=dark")
        #expect(light.absoluteString == "https://portal.example.test/api/v1/artifact/artifact01#theme=light")
        #expect(dark.path == light.path)
    }

    @Test func inlineHeightIsClamped() {
        #expect(ArtifactSandbox.clampedHeight(40) == 120)
        #expect(ArtifactSandbox.clampedHeight(300) == 300)
        #expect(ArtifactSandbox.clampedHeight(5_000) == 640)
        #expect(ArtifactSandbox.clampedHeight(.nan) == 120)
    }

    @Test func theRuleListBlocksEverythingButTheServer() throws {
        let json = ArtifactSandbox.contentRuleListJSON(server: server)
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(rules.count == 2)
        #expect((rules[0]["action"] as? [String: String])?["type"] == "block")
        #expect((rules[0]["trigger"] as? [String: String])?["url-filter"] == ".*")
        #expect((rules[1]["action"] as? [String: String])?["type"] == "ignore-previous-rules")
        #expect((rules[1]["trigger"] as? [String: String])?["url-filter"] == "^https://portal\\.example\\.test/")
    }

    @Test func aServerWithAPortKeepsItInTheAllowRule() throws {
        let local = try ServerAddress("http://localhost:20080")
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(ArtifactSandbox.contentRuleListJSON(server: local).utf8)) as? [[String: Any]])
        #expect((rules[1]["trigger"] as? [String: String])?["url-filter"] == "^http://localhost:20080/")
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
