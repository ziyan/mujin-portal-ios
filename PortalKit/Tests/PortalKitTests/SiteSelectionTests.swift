import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Foundation
import Testing

@testable import PortalKit

@Suite struct SiteSelectionTests {
    @Test func reloadingKeepsTheCurrentSiteWhileItIsListed() {
        #expect(SiteSelection.resolve(current: "site02", remembered: "site03", availableIds: ["site01", "site02", "site03"]) == "site02")
    }

    @Test func aRememberedSiteIsRestoredWhenNothingIsSelected() {
        #expect(SiteSelection.resolve(current: nil, remembered: "site02", availableIds: ["site01", "site02"]) == "site02")
    }

    @Test func theFirstSiteIsPickedOnlyWhenNothingElseApplies() {
        #expect(SiteSelection.resolve(current: nil, remembered: nil, availableIds: ["site01", "site02"]) == "site01")
        #expect(SiteSelection.resolve(current: "gone", remembered: "also-gone", availableIds: ["site01"]) == "site01")
        #expect(SiteSelection.resolve(current: nil, remembered: nil, availableIds: []) == nil)
    }

    @Test func theChoiceIsRememberedPerAccountAndScope() throws {
        let suite = "site-selection-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SiteSelectionStore(defaults: defaults)
        store.save("site02", accountKey: "account01", organizationKey: "")
        store.save("site05", accountKey: "account01", organizationKey: "organization02")
        #expect(store.load(accountKey: "account01", organizationKey: "") == "site02")
        #expect(store.load(accountKey: "account01", organizationKey: "organization02") == "site05")
        #expect(store.load(accountKey: "account02", organizationKey: "") == nil)
    }
}

@Suite struct AvatarSubjectTests {
    @Test func aPictureIsKeyedByWhoAndByVersion() {
        let first = AvatarSubject(kind: .user, id: "user01", modifiedAt: "2026-01-01T00:00:00Z")
        let uploadedAgain = AvatarSubject(kind: .user, id: "user01", modifiedAt: "2026-02-01T00:00:00Z")
        #expect(first.cacheKey != uploadedAgain.cacheKey)
        #expect(first.path == "/api/v1/user/user01/avatar")
        #expect(AvatarSubject(kind: .organization, id: "organization01").path == "/api/v1/organization/organization01/logo")
    }

    @Test func aDirectChatShowsTheOtherPersonAndAGroupTheFirstTwoOthers() {
        func member(_ id: String) -> ChatMember { ChatMember(id: "m" + id, userId: id) }
        let direct = ChatRoom(id: "chat01", chatKind: "direct", members: [member("user01"), member("user02")])
        #expect(direct.avatarMembers(excluding: "user01").map(\.userId) == ["user02"])
        let group = ChatRoom(id: "chat02", chatKind: "group", members: [member("user01"), member("user02"), member("user03"), member("user04")])
        #expect(group.avatarMembers(excluding: "user01").map(\.userId) == ["user02", "user03"])
    }

    @Test func aStoreFetchesOnceAndKeepsThePictureForTheSameVersion() async throws {
        let transport = CountingPictureTransport()
        let account = Account(
            server: try ServerAddress("https://portal.example.test"), clientId: "client01", userId: "user01", displayName: "Alex", email: "alex@example.test",
            accessToken: "token", refreshToken: "refresh", accessTokenExpiresAt: Date().addingTimeInterval(3600), webDataStoreId: UUID())
        let store = AvatarStore(connection: Connection(account: account, transport: transport), directory: nil)
        let subject = AvatarSubject(kind: .user, id: "user02", modifiedAt: "v1")
        async let first = store.data(for: subject)
        async let second = store.data(for: subject)
        _ = await (first, second)
        #expect(await store.data(for: subject) == Data([1, 2, 3]))
        #expect(transport.count == 1)
        let missing = AvatarSubject(kind: .user, id: "user03")
        #expect(await store.data(for: missing) == nil)
        #expect(await store.data(for: missing) == nil)
        #expect(transport.count == 2)
    }
}

private final class CountingPictureTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    var count: Int { lock.withLock { requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests += 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        let found = request.url?.path.contains("user02") == true
        let response = HTTPURLResponse(url: request.url!, statusCode: found ? 200 : 404, httpVersion: nil, headerFields: nil)!
        return (found ? Data([1, 2, 3]) : Data(), response)
    }
}

@Suite struct MainChatTests {
    @Test func theMainChatIsPinnedFirstAndTheRestKeepTheirOrder() {
        let rows = [ConversationSummary(id: "c1"), ConversationSummary(id: "c2", isMain: true), ConversationSummary(id: "c3")]
        #expect(ConversationOrdering.pinningMain(rows).map(\.id) == ["c2", "c1", "c3"])
    }

    @Test func anEmptyMainChatIsStillListed() {
        #expect(ConversationSummary(id: "c1", isMain: true).isEmptyAssistantConversation == false)
        #expect(ConversationSummary(id: "c2").isEmptyAssistantConversation == true)
    }
}

@Suite struct ConversationOrderTests {
    private func stamp(_ secondsAgo: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo))
    }

    @Test func aRecentChatSortsAboveOlderAssistantConversationsWhateverTheirCreation() {
        let chat = ConversationSummary(
            id: "chatconv", lastMessageAt: nil, createdAt: stamp(90 * 86_400), conversationKind: "chat",
            chat: ChatRoom(id: "chat01", chatKind: "direct", lastMessageAt: stamp(7_200)))
        let yesterday = ConversationSummary(id: "yesterday", lastMessageAt: stamp(86_400), createdAt: stamp(10 * 86_400), conversationKind: "assistant")
        let old = ConversationSummary(id: "old", lastMessageAt: stamp(60 * 86_400), createdAt: stamp(61 * 86_400), conversationKind: "assistant")
        // The rows arrive the way the held copy stores them: assistant conversations first, chats after.
        #expect(ConversationOrdering.ordered([yesterday, old, chat]).map(\.id) == ["chatconv", "yesterday", "old"])
    }

    @Test func theLatestOfTheThreeMomentsIsTheActivity() {
        let row = ConversationSummary(
            id: "c1", lastMessageAt: stamp(5_000), createdAt: stamp(999_999), modifiedAt: stamp(100), conversationKind: "chat",
            chat: ChatRoom(id: "chat01", lastMessageAt: stamp(3_000)))
        let activity = ConversationOrdering.activity(row)
        #expect(abs(activity.timeIntervalSinceNow + 100) < 5)
    }

    @Test func theMainChatThenWhatWaitsThenTheRest() {
        let main = ConversationSummary(id: "main", lastMessageAt: stamp(900_000), isMain: true)
        let waiting = ConversationSummary(id: "waiting", lastMessageAt: stamp(800_000))
        let recent = ConversationSummary(id: "recent", lastMessageAt: stamp(10))
        #expect(ConversationOrdering.ordered([recent, waiting, main], waitingIds: ["waiting"]).map(\.id) == ["main", "waiting", "recent"])
    }
}
