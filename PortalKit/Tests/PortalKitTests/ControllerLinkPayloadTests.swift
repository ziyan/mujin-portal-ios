import Foundation
import Testing

@testable import PortalKit

@Suite struct ControllerLinkPayloadTests {
    let server = try! ServerAddress("https://portal.example.test")
    let code = "aGVsbG8tV29ybGRfMDEyMzQ1Njc4OWFiY2RlZg"

    @Test func anAddressOnTheAccountsServerGivesItsCode() {
        #expect(ControllerLinkPayload.read("https://portal.example.test/link/\(code)", server: server) == .link(code: code))
        #expect(ControllerLinkPayload.read("  https://PORTAL.example.test/link/\(code)/\n", server: server) == .link(code: code))
    }

    @Test func theCodeKeepsItsCase() {
        let mixed = "AbCdEfGhIjKlMnOpQrSt"
        #expect(ControllerLinkPayload.read("https://portal.example.test/link/\(mixed)", server: server) == .link(code: mixed))
    }

    @Test func anotherServerIsNamedAndNotAccepted() {
        #expect(ControllerLinkPayload.read("https://portal.other.test/link/\(code)", server: server) == .otherServer(host: "portal.other.test"))
        #expect(ControllerLinkPayload.read("https://portal.example.test.other.test/link/\(code)", server: server) == .otherServer(host: "portal.example.test.other.test"))
        #expect(ControllerLinkPayload.read("https://portal.example.test:8443/link/\(code)", server: server) == .otherServer(host: "portal.example.test:8443"))
    }

    @Test func aServerWithAPortMatchesOnlyThatPort() throws {
        let local = try ServerAddress("http://localhost:20080")
        #expect(ControllerLinkPayload.read("http://localhost:20080/link/\(code)", server: local) == .link(code: code))
        #expect(ControllerLinkPayload.read("http://localhost:3000/link/\(code)", server: local) == .otherServer(host: "localhost:3000"))
    }

    @Test func otherTextIsNotAControllerCode() {
        for text in [
            "", "   ", "hello", "https://portal.example.test/", "https://portal.example.test/ticket/\(code)",
            "https://portal.example.test/link/", "https://portal.example.test/link/\(code)/extra", "https://portal.example.test/link/short",
            "ftp://portal.example.test/link/\(code)", "https://user:secret@portal.example.test/link/\(code)", "mailto:someone@example.test",
            "WIFI:S:network;T:WPA;P:password;;", "https://other.test/page", "12345", "link/\(code)",
        ] {
            #expect(ControllerLinkPayload.read(text, server: server) == .notControllerCode, "\(text)")
        }
    }

    @Test func aTypedCodeIsAccepted() {
        #expect(ControllerLinkPayload.read(code, server: server) == .link(code: code))
        #expect(ControllerLinkPayload.read(" \(code.prefix(10)) \(code.dropFirst(10))\n", server: server) == .link(code: code))
        #expect(ControllerLinkPayload.read("not a code at all, really", server: server) == .notControllerCode)
    }

    @Test func aPastedAddressWorksInTheTypedForm() {
        #expect(ControllerLinkPayload.read("https://portal.example.test/link/\(code)", server: server) == .link(code: code))
    }

    @Test func anAddressReadsBackToTheSameCode() {
        let address = ControllerLinkPayload.address(code: code, server: server)
        #expect(address == "https://portal.example.test/link/\(code)")
        #expect(ControllerLinkPayload.read(address, server: server) == .link(code: code))
    }
}
