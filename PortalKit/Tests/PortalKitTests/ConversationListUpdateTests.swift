import Foundation
import Testing

@testable import PortalKit

@Suite struct ConversationListUpdateTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func row(_ id: String, title: String? = nil, lastMessageAt: String? = nil) -> ConversationSummary {
        ConversationSummary(id: id, title: title, lastMessageAt: lastMessageAt, conversationKind: "assistant")
    }

    @Test func aPlaceholderTitleIsTheFirstWordsOfTheMessage() {
        #expect(ConversationListUpdate.placeholderTitle(for: "  Why is\n line two  slow?  ") == "Why is line two slow?")
        #expect(ConversationListUpdate.placeholderTitle(for: "one two three four five six seven eight nine") == "one two three four five six seven eight…")
        #expect(ConversationListUpdate.placeholderTitle(for: "   \n") == nil)
        let long = String(repeating: "abcdefghij ", count: 7) + "x"
        let title = ConversationListUpdate.placeholderTitle(for: long) ?? ""
        #expect(title.count <= 60 && title.hasSuffix("…"))
    }

    @Test func aStartedConversationIsListedWithATitleAndAMoment() {
        let started = ConversationListUpdate.startedRow(id: "c1", text: "Check dock door 4", now: now)
        #expect(started.title == "Check dock door 4")
        #expect(!started.isEmptyAssistantConversation)
        #expect(started.lastActivity == now)
    }

    @Test func insertingPutsTheRowFirstAndNeverTwice() {
        let rows = [row("a"), row("b", title: "Old")]
        let inserted = ConversationListUpdate.inserting(row("b", title: "New"), into: rows)
        #expect(inserted.map(\.id) == ["b", "a"])
        #expect(inserted.first?.title == "New")
    }

    @Test func readingAChatClearsOnlyItsOwnRow() {
        func chat(_ id: String, unread: Int64) -> ConversationSummary {
            ConversationSummary(id: id, conversationKind: "chat", chat: ChatRoom(id: "room-\(id)", readerUnreadMessageCount: unread))
        }
        let rows = [chat("a", unread: 3), chat("b", unread: 2), row("c", title: "Assistant")]
        let marked = ConversationListUpdate.markedRead(rows, id: "a")
        #expect(marked.map { $0.chat?.unreadCount } == [0, 2, nil])
        #expect(ConversationListUpdate.markedRead(rows, id: "c") == rows)
    }

    @Test func aTitleFromTheServerReplacesThePlaceholderAndAnEmptyOneChangesNothing() {
        let rows = [row("a", title: "Check dock door 4"), row("b", title: "Other")]
        let retitled = ConversationListUpdate.retitled(rows, id: "a", title: "Dock door 4 check")
        #expect(retitled.map { $0.title } == ["Dock door 4 check", "Other"])
        #expect(ConversationListUpdate.retitled(rows, id: "a", title: "") == rows)
        #expect(ConversationListUpdate.retitled(rows, id: "a", title: nil) == rows)
    }

    @Test func aStartedConversationTheServerDoesNotListYetStaysInTheList() {
        let started = ConversationListUpdate.startedRow(id: "new", text: "Hello there", now: now)
        let merged = ConversationListUpdate.merging(read: [row("a", title: "A", lastMessageAt: "2026-01-01T00:00:00Z")], started: [started])
        #expect(merged.map(\.id) == ["a", "new"])
    }

    @Test func aListedRowThatIsStillBlankTakesTheStartedTitleAndMoment() {
        let started = ConversationListUpdate.startedRow(id: "new", text: "Hello there", now: now)
        let merged = ConversationListUpdate.merging(read: [row("new")], started: [started])
        #expect(merged.count == 1)
        #expect(merged[0].title == "Hello there")
        #expect(!merged[0].isEmptyAssistantConversation)
    }

    @Test func aListedRowWithItsOwnTitleIsLeftAlone() {
        let started = ConversationListUpdate.startedRow(id: "new", text: "Hello there", now: now)
        let listed = row("new", title: "Greeting", lastMessageAt: "2026-01-01T00:00:00Z")
        #expect(ConversationListUpdate.merging(read: [listed], started: [started]) == [listed])
    }
}
