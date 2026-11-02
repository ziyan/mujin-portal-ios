import Foundation
import Testing

@testable import PortalKit

@Suite struct FeedTests {
    static let discovery: Data = ConnectionTests.discovery

    static func fastTiming() -> FeedTiming {
        var timing = FeedTiming()
        timing.sleep = { _ in try await Task.sleep(nanoseconds: 1_000_000) }
        return timing
    }

    func connection(accessToken: String = "access-1") -> Connection {
        let transport = ScriptedTransport { request in
            if request.url?.path == "/.well-known/openid-configuration" { return (200, Self.discovery) }
            return (200, ScriptedTransport.json(["access_token": "access-renewed", "refresh_token": "refresh-2", "expires_in": 300]))
        }
        return Connection(account: makeAccount(accessToken: accessToken), transport: transport)
    }

    /// A socket that answers connection_init with an ack, as Portal does.
    static func portalLikeSocket(extraFrames: [FeedFrame] = []) -> ScriptedSocket {
        ScriptedSocket(frames: []) { text, socket in
            if text.contains("connection_init") { socket.push(ackFrame()) }
            if text.contains("\"subscribe\"") { for frame in extraFrames { socket.push(frame) } }
            if text.contains("\"ping\"") { socket.push(.text(#"{"type":"pong"}"#)) }
        }
    }

    func collect(_ updates: AsyncStream<FeedUpdate>, until stop: (FeedUpdate, [FeedUpdate]) -> Bool) async -> [FeedUpdate] {
        var collected: [FeedUpdate] = []
        for await update in updates {
            collected.append(update)
            if stop(update, collected) { break }
        }
        return collected
    }

    @Test func itInitializesSubscribesAndDeliversEvents() async {
        let socket = Self.portalLikeSocket(extraFrames: [
            eventFrame(#"{"type":"text_delta","runId":"run01","textDelta":{"messageId":"message01","text":"Hi"}}"#),
            eventFrame(#"{"type":"run_complete","runComplete":{"stopReason":"end_turn"}}"#),
        ])
        let tokens = Guarded<[String]>([])
        let updates = ConversationFeed.updates(
            connection: connection(), conversationId: "conversation01",
            socketFactory: { _, token in
                tokens.withValue { $0.append(token) }
                return socket
            }, timing: Self.fastTiming())
        let collected = await collect(updates) { update, _ in
            if case .event(let event) = update { return event.type == "run_complete" }
            return false
        }
        #expect(collected.first == .connected)
        #expect(collected.contains(.event(ConversationEvent(type: "text_delta", runId: "run01", textDelta: .init(messageId: "message01", text: "Hi")))))
        #expect(tokens.withValue { $0 } == ["access-1"])
        let sent = socket.sent
        #expect(sent.first?.contains("connection_init") == true)
        #expect(sent.contains { $0.contains("OnConversationEvent") && $0.contains("conversation01") })
    }

    @Test func aTitleEventReachesTheScreenThroughTheFeed() async {
        let socket = Self.portalLikeSocket(extraFrames: [
            eventFrame(#"{"type":"conversation_updated","conversationUpdated":{"conversationId":"conversation01","conversationTitle":"Dock door check","isTitleCustom":false}}"#)
        ])
        let updates = ConversationFeed.updates(connection: connection(), conversationId: "conversation01", socketFactory: { _, _ in socket }, timing: Self.fastTiming())
        let collected = await collect(updates) { update, _ in
            if case .event(let event) = update { return event.kind == .conversationUpdated }
            return false
        }
        guard case .event(let event)? = collected.last else {
            Issue.record("no event arrived")
            return
        }
        #expect(event.announcedTitle(for: "conversation01")?.title == "Dock door check")
        #expect(socket.sent.contains { $0.contains("conversationUpdated") })
    }

    @Test func closeCode4401RenewsTheTokenAndReconnectsAtOnce() async {
        let sockets = Guarded<[ScriptedSocket]>([
            ScriptedSocket(frames: [ackFrame(), .closed(code: 4401)]),
            Self.portalLikeSocket(extraFrames: [eventFrame(#"{"type":"run_complete"}"#)]),
        ])
        let tokens = Guarded<[String]>([])
        let pauses = Guarded<[TimeInterval]>([])
        var timing = Self.fastTiming()
        timing.sleep = { seconds in
            pauses.withValue { $0.append(seconds) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let connection = self.connection()
        let updates = ConversationFeed.updates(
            connection: connection, conversationId: "conversation01",
            socketFactory: { _, token in
                tokens.withValue { $0.append(token) }
                return sockets.withValue { $0.removeFirst() }
            }, timing: timing)
        let collected = await collect(updates) { update, _ in
            if case .event = update { return true }
            return false
        }
        #expect(tokens.withValue { $0 } == ["access-1", "access-renewed"])
        #expect(collected.filter { $0 == .connected }.count == 2)
        #expect(collected.contains(.reconnecting))
        // Renewal is not a failure, so no backoff pause was taken.
        #expect(pauses.withValue { $0 }.filter { [1, 2, 4, 8, 10].contains($0) }.isEmpty)
    }

    @Test func aSilentSocketIsClosedByTheWatchdogAndReplaced() async {
        let silent = ScriptedSocket(frames: [])
        let live = Self.portalLikeSocket(extraFrames: [eventFrame(#"{"type":"run_complete"}"#)])
        let sockets = Guarded<[ScriptedSocket]>([silent, live])
        let clock = Guarded<Date>(Date())
        var timing = FeedTiming()
        timing.silenceLimit = 15
        timing.pingInterval = 5
        // Each sleep advances a fake clock by that long, so 15 s pass in milliseconds.
        timing.now = { clock.withValue { $0 } }
        timing.sleep = { seconds in
            clock.withValue { $0 = $0.addingTimeInterval(seconds) }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let updates = ConversationFeed.updates(
            connection: connection(), conversationId: "conversation01", socketFactory: { _, _ in sockets.withValue { $0.removeFirst() } }, timing: timing)
        let collected = await collect(updates) { update, _ in
            if case .event = update { return true }
            return false
        }
        #expect(silent.wasClosed)
        #expect(collected.contains(.reconnecting))
        #expect(collected.contains(.connected))
    }

    @Test func theClientPingsSoAnIdleConversationIsNotSilent() async {
        let socket = Self.portalLikeSocket()
        let sockets = Guarded<[ScriptedSocket]>([socket])
        var timing = FeedTiming()
        timing.pingInterval = 0.001
        timing.sleep = { _ in try await Task.sleep(nanoseconds: 3_000_000) }
        let updates = ConversationFeed.updates(
            connection: connection(), conversationId: "conversation01", socketFactory: { _, _ in sockets.withValue { $0.removeFirst() } }, timing: timing)
        let task = Task { for await _ in updates {} }
        try? await Task.sleep(nanoseconds: 600_000_000)
        task.cancel()
        #expect(socket.sent.filter { $0.contains("\"ping\"") }.count >= 2)
        #expect(!socket.sent.contains { $0.contains("connection_init") && $0.count > 100 })
    }

    @Test func failuresBackOffFromOneToTenSeconds() {
        let timing = FeedTiming()
        #expect((1...7).map { timing.pause(afterFailures: $0) } == [1, 2, 4, 8, 10, 10, 10])
    }

    @Test func aSocketThatCannotBeOpenedIsRetriedWithBackoff() async {
        let attempts = Guarded<Int>(0)
        let pauses = Guarded<[TimeInterval]>([])
        var timing = Self.fastTiming()
        timing.sleep = { seconds in
            pauses.withValue { $0.append(seconds) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let live = Self.portalLikeSocket(extraFrames: [eventFrame(#"{"type":"run_complete"}"#)])
        let updates = ConversationFeed.updates(
            connection: connection(), conversationId: "conversation01",
            socketFactory: { _, _ in
                let attempt = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if attempt < 3 { throw PortalError.refused("offline") }
                return live
            }, timing: timing)
        _ = await collect(updates) { update, _ in
            if case .event = update { return true }
            return false
        }
        #expect(pauses.withValue { Array($0.filter { [1, 2, 4, 8, 10].contains($0) }.prefix(2)) } == [1, 2])
    }

    @Test func aRefusedRenewalReportsSignedOut() async {
        let transport = ScriptedTransport { request in
            if request.url?.path == "/.well-known/openid-configuration" { return (200, Self.discovery) }
            return (400, ScriptedTransport.json(["error": "invalid_grant"]))
        }
        let connection = Connection(account: makeAccount(expiresAt: Date().addingTimeInterval(1)), transport: transport)
        let updates = ConversationFeed.updates(
            connection: connection, conversationId: "conversation01", socketFactory: { _, _ in ScriptedSocket(frames: []) }, timing: Self.fastTiming())
        let collected = await collect(updates) { _, _ in false }
        #expect(collected == [.signedOut])
    }
}
