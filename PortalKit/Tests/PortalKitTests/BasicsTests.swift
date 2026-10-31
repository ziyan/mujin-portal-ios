import Foundation
import Testing

@testable import PortalKit

@Suite struct ServerAddressTests {
    @Test func aBareHostGetsHttpsAndLosesItsPath() throws {
        #expect(try ServerAddress("Portal.Example.test/some/path?x=1").description == "https://portal.example.test")
    }

    @Test func httpIsRefusedExceptOnLoopback() throws {
        #expect(throws: PortalError.invalidServerAddress) { try ServerAddress("http://portal.example.test") }
        #expect(try ServerAddress("http://localhost:8080").description == "http://localhost:8080")
    }

    @Test func nonsenseIsRefused() {
        #expect(throws: PortalError.invalidServerAddress) { try ServerAddress("   ") }
        #expect(throws: PortalError.invalidServerAddress) { try ServerAddress("ftp://portal.example.test") }
        #expect(throws: PortalError.invalidServerAddress) { try ServerAddress("https://user:secret@portal.example.test") }
    }

    @Test func theDefaultIsProduction() {
        #expect(ServerAddress.production.description == "https://portal.mujin.cloud")
    }

    @Test func endpointsAreJoined() throws {
        let server = try ServerAddress("https://portal.example.test/")
        #expect(server.endpoint("/api/v1/graphql").absoluteString == "https://portal.example.test/api/v1/graphql")
        #expect(server.subscriptionEndpoint.absoluteString == "wss://portal.example.test/api/v1/graphql/subscribe")
    }
}

@Suite struct AccountRingTests {
    @Test func theFirstAccountIsActiveAndASecondDoesNotTakeOver() {
        var ring = AccountRing()
        ring.put(makeAccount(userId: "user01"))
        ring.put(makeAccount(userId: "user02"))
        #expect(ring.accounts.count == 2)
        #expect(ring.active?.userId == "user01")
    }

    @Test func theSamePersonOnTheSameServerReplacesTheSignIn() {
        var ring = AccountRing()
        ring.put(makeAccount(accessToken: "old"))
        ring.put(makeAccount(accessToken: "new"))
        #expect(ring.accounts.count == 1)
        #expect(ring.active?.accessToken == "new")
    }

    @Test func theSamePersonOnTwoServersIsTwoAccounts() {
        var ring = AccountRing()
        ring.put(makeAccount(server: "https://one.example.test"))
        ring.put(makeAccount(server: "https://two.example.test"))
        #expect(ring.accounts.count == 2)
        #expect(Set(ring.accounts.map(\.accountKey)).count == 2)
    }

    @Test func removingTheActiveAccountPutsTheNextToUse() {
        var ring = AccountRing()
        ring.put(makeAccount(userId: "user01"))
        ring.put(makeAccount(userId: "user02"))
        ring.remove(ring.active!.accountKey)
        #expect(ring.active?.userId == "user02")
        ring.remove(ring.active!.accountKey)
        #expect(ring.active == nil)
    }

    @Test func theStoreKeepsTheRing() throws {
        let store = MemoryAccountStore()
        try store.add(makeAccount(userId: "user01"))
        try store.add(makeAccount(userId: "user02"))
        #expect(try store.loadRing().active?.userId == "user02")
        try store.activate(makeAccount(userId: "user01").accountKey)
        #expect(try store.loadRing().active?.userId == "user01")
        try store.save(makeAccount(userId: "user02", accessToken: "renewed"))
        #expect(try store.loadRing().active?.userId == "user01")
        #expect(try store.load(accountKey: makeAccount(userId: "user02").accountKey)?.accessToken == "renewed")
    }
}

@Suite struct PKCETests {
    @Test func theChallengeMatchesTheRFCExample() {
        // RFC 7636 appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func eachVerifierIsNewAndUrlSafe() {
        let first = PKCE()
        let second = PKCE()
        #expect(first.verifier != second.verifier)
        #expect(first.verifier.count >= 43)
        #expect(first.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

@Suite struct SubscriptionMessageTests {
    @Test func frameRoundTrip() throws {
        let text = try SubscriptionMessage.subscribe(id: "1", query: "subscription { a }", variables: ["x": .string("y")]).encoded()
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(value["type"]?.stringValue == "subscribe")
        #expect(value["payload"]?["query"]?.stringValue == "subscription { a }")
        #expect(try SubscriptionMessage(decoding: #"{"type":"connection_ack"}"#) == .connectionAck)
        #expect(try SubscriptionMessage(decoding: #"{"type":"ping"}"#) == .ping)
        #expect(try SubscriptionMessage(decoding: #"{"type":"complete","id":"1"}"#) == .complete(id: "1"))
    }

    @Test func nextCarriesDataAndErrors() throws {
        let message = try SubscriptionMessage(decoding: #"{"type":"next","id":"1","payload":{"data":{"a":1},"errors":[{"message":"no"}]}}"#)
        guard case .next(_, let data, let errors) = message else { Issue.record("not next"); return }
        #expect(data?["a"] == .number(1))
        #expect(errors == [Connection.GraphQLError(message: "no")])
    }

    @Test func unknownFramesAreRefused() {
        #expect(throws: PortalError.unreadableAnswer) { try SubscriptionMessage(decoding: #"{"type":"bogus"}"#) }
        #expect(throws: PortalError.unreadableAnswer) { try SubscriptionMessage(decoding: "not json") }
    }
}

@Suite struct MarkdownBlocksTests {
    @Test func blocksAreSplit() {
        let blocks = MarkdownBlocks.parse(
            """
            # Title

            First line
            second line

            - one
            - two
              wrapped

            1. step
            2. next

            > quoted

            ```swift
            let value = 1
            ```
            ---
            """)
        #expect(
            blocks == [
                .heading(level: 1, text: "Title"),
                .paragraph("First line\nsecond line"),
                .bulletList(["one", "two wrapped"]),
                .numberedList(["step", "next"]),
                .quote("quoted"),
                .code(language: "swift", text: "let value = 1"),
                .rule,
            ])
    }

    @Test func anUnclosedFenceStillShowsItsCode() {
        #expect(MarkdownBlocks.parse("```\nabc") == [.code(language: "", text: "abc")])
    }
}
