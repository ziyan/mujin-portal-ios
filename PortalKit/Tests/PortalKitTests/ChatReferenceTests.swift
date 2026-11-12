import Foundation
import Testing

@testable import PortalKit

/// References in chat messages: kept once each, found in one pass over the words, and what the # picker puts in.
@Suite struct ChatReferenceTests {
    let ticket = ChatReference(
        referenceKind: "ticket", writtenText: "#123", isAccessible: true, targetId: "t1", path: "/ticket/123", label: "#123 Gripper drops boxes",
        ticketSequence: 123, ticketTitle: "Gripper drops boxes", ticketStatus: "open")

    @Test func aThingNamedManyTimesIsOneReference() {
        #expect(ChatReferences.unique(Array(repeating: ticket, count: 10)).count == 1)
    }

    @Test func referencesAreFoundAtWordBoundariesOnly() {
        let pieces = ChatReferences.pieces(of: "See #123, not #1234 or a#123.", references: [ticket])
        #expect(pieces == [.text("See "), .reference(ticket), .text(", not #1234 or a#123.")])
    }

    /// A label that repeats what was written must not be matched again: the words are scanned once, and never the chips made.
    @Test func aTicketNamedFortyTimesMakesFortyChipsQuickly() {
        let words = Array(repeating: "#123", count: 40).joined(separator: " ")
        let start = Date()
        let pieces = ChatReferences.pieces(of: words, references: Array(repeating: ticket, count: 40))
        #expect(pieces.filter { if case .reference = $0 { return true } else { return false } }.count == 40)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func aReferenceTheReaderCannotSeeOpensNothing() {
        let hidden = ChatReference(referenceKind: "controller", writtenText: "[controller9](/controller/c9)", isAccessible: false)
        #expect(!hidden.canOpen)
        #expect(ticket.canOpen)
        #expect(ticket.chipText == "#123 Gripper drops boxes")
    }

    @Test func thePickerPutsATicketAsItsNumberAndTheRestAsLinks() {
        #expect(ChatReferenceCandidate(referenceKind: "ticket", targetId: "t1", path: "/ticket/123", label: "Gripper drops boxes").insertedText == "#123")
        #expect(
            ChatReferenceCandidate(referenceKind: "cell", targetId: "cell1", path: "/site/site1/cell/cell1", label: "Cell 1").insertedText
                == "[Cell 1](/site/site1/cell/cell1)")
    }

    @Test func anEmptyQueryAsksForTheChatsSuggestions() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SearchChatReferences": []] }
        _ = try await connection.searchChatReferences(query: "", chatId: "chat1")
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["query"] as? String == "")
        #expect(variables["chatId"] as? String == "chat1")
    }
}
