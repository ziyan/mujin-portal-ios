import Foundation
import Testing

@testable import PortalKit

@Suite struct ResponseCacheTests {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var moment = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { lock.lock(); moment = moment.addingTimeInterval(seconds); lock.unlock() }
        var now: Date { lock.lock(); defer { lock.unlock() }; return moment }
    }

    func key(_ name: String, account: String = "a|1", variables: String = "") -> CacheKey { CacheKey(accountKey: account, name: name, variables: variables) }

    @Test func aStoredValueIsAHitAndFreshUntilItsWindowPasses() {
        let clock = Clock()
        let cache = ResponseCache(freshFor: 30, now: { clock.now })
        cache.store(["t1", "t2"], for: key("tickets"))
        #expect(cache.hit(key("tickets"), as: [String].self)?.value == ["t1", "t2"])
        #expect(cache.hit(key("tickets"), as: [String].self)?.isFresh == true)
        clock.advance(31)
        #expect(cache.hit(key("tickets"), as: [String].self)?.isFresh == false)
        #expect(cache.hit(key("other"), as: [String].self) == nil)
        #expect(cache.hit(key("tickets"), as: Int.self) == nil)
    }

    @Test func aFreshEntryIsNotReadAgainButAStaleOneIsShownFirstAndThenRefreshed() async throws {
        let clock = Clock()
        let cache = ResponseCache(freshFor: 30, now: { clock.now })
        let calls = Guarded(0)
        let shown = Guarded<[Int]>([])
        func read(force: Bool = false) async throws {
            try await cache.load(key("site"), force: force, show: { value in shown.withValue { $0.append(value) } }, fetch: { () async throws -> Int in
                calls.withValue { $0 += 1 }
                return calls.withValue { $0 } * 10
            })
        }
        try await read()
        #expect(calls.withValue { $0 } == 1 && shown.withValue { $0 } == [10])
        try await read()
        #expect(calls.withValue { $0 } == 1)
        // Stale: the held value shows at once, then the new one replaces it in place.
        clock.advance(60)
        try await read()
        #expect(calls.withValue { $0 } == 2)
        #expect(shown.withValue { $0 } == [10, 10, 10, 20])
        // Pull to refresh reads even a fresh entry.
        try await read(force: true)
        #expect(calls.withValue { $0 } == 3)
    }

    @Test func theLeastRecentlyUsedEntryIsEvictedBeyondTheCapacity() {
        let clock = Clock()
        let cache = ResponseCache(capacity: 3, now: { clock.now })
        for name in ["a", "b", "c"] {
            clock.advance(1)
            cache.store(name, for: key(name))
        }
        clock.advance(1)
        _ = cache.hit(key("a"), as: String.self)
        clock.advance(1)
        cache.store("d", for: key("d"))
        #expect(cache.count == 3)
        #expect(cache.hit(key("b"), as: String.self) == nil)
        #expect(cache.hit(key("a"), as: String.self) != nil)
        #expect(cache.hit(key("d"), as: String.self) != nil)
    }

    @Test func accountsNeverSeeEachOthersEntries() {
        let cache = ResponseCache()
        cache.store("first", for: key("tickets", account: "server|user01"))
        #expect(cache.hit(key("tickets", account: "server|user02"), as: String.self) == nil)
        cache.store("second", for: key("tickets", account: "server|user02"))
        cache.clear(accountKey: "server|user01")
        #expect(cache.hit(key("tickets", account: "server|user01"), as: String.self) == nil)
        #expect(cache.hit(key("tickets", account: "server|user02"), as: String.self)?.value == "second")
        cache.clear()
        #expect(cache.count == 0)
    }

    @Test func variablesMakeAnotherEntry() {
        let cache = ResponseCache()
        cache.store(1, for: key("site", variables: "site01"))
        cache.store(2, for: key("site", variables: "site02"))
        #expect(cache.hit(key("site", variables: "site01"), as: Int.self)?.value == 1)
        #expect(cache.hit(key("site", variables: "site02"), as: Int.self)?.value == 2)
    }

    @Test func aMutationsResultChangesTheEntryInPlaceWithoutMakingItFresherOrReadingIt() {
        let clock = Clock()
        let cache = ResponseCache(freshFor: 30, now: { clock.now })
        cache.store(["a", "b"], for: key("tickets"))
        clock.advance(20)
        #expect(cache.update(key("tickets"), as: [String].self) { $0.insert("new", at: 0) })
        #expect(cache.hit(key("tickets"), as: [String].self)?.value == ["new", "a", "b"])
        clock.advance(15)
        // It keeps its age: the update did not make it fresh again.
        #expect(cache.hit(key("tickets"), as: [String].self)?.isFresh == false)
        #expect(!cache.update(key("missing"), as: [String].self) { $0.removeAll() })
    }
}


@Suite struct CachedMutationTests {
    @Test func markingANotificationReadChangesItsCachedRowInPlace() {
        let cache = ResponseCache()
        let key = CacheKey(accountKey: "a|1", name: "notifications")
        cache.store([PortalNotification(id: "n1", kind: "alarm"), PortalNotification(id: "n2", kind: "incident")], for: key)
        cache.update(key, as: [PortalNotification].self) { rows in
            rows = rows.map { $0.id == "n1" ? $0.markedRead(at: "2026-10-31T12:00:00Z") : $0 }
        }
        let rows = cache.hit(key, as: [PortalNotification].self)?.value
        #expect(rows?.first?.isUnread == false)
        #expect(rows?.last?.isUnread == true)
        #expect(rows?.first?.kind == "alarm")
    }

    @Test func archivingAConversationRemovesItFromTheCachedListWithoutReadingIt() {
        let cache = ResponseCache()
        let key = CacheKey(accountKey: "a|1", name: "conversations")
        cache.store([ConversationSummary(id: "c1"), ConversationSummary(id: "c2")], for: key)
        cache.update(key, as: [ConversationSummary].self) { $0.removeAll { $0.id == "c1" } }
        #expect(cache.hit(key, as: [ConversationSummary].self)?.value.map(\.id) == ["c2"])
    }
}
