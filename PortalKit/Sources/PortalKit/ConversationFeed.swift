import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// FeedFrame is what a feed socket hands back: a text frame, or the news
/// that the socket is closed (with the close code when there is one).
public enum FeedFrame: Equatable, Sendable {
    case text(String)
    case closed(code: Int?)
}

/// FeedSocket is the WebSocket under a feed: URLSession's in the app, a
/// scripted one in tests and in the demo.
public protocol FeedSocket: Sendable {
    func send(_ text: String) async throws
    /// The next frame. Returns `.closed` rather than throwing when the socket
    /// ends, whoever ended it.
    func receive() async throws -> FeedFrame
    func close()
}

/// Opens a socket to a server's subscription endpoint with the bearer token
/// on the upgrade request, which is where Portal reads it.
public typealias FeedSocketFactory = @Sendable (_ server: ServerAddress, _ accessToken: String) async throws -> any FeedSocket

/// FeedUpdate is what a screen hears from a feed.
public enum FeedUpdate: Equatable, Sendable {
    /// The socket is subscribed. Anything said while it was down is gone, so
    /// the screen reloads the conversation and clears what it showed live;
    /// the server then replays the running turn from its start.
    case connected
    case event(ConversationEvent)
    /// The socket dropped; a new one opens after a pause.
    case reconnecting
    /// The server refused a renewed token as well: the sign-in has ended.
    case signedOut
}

/// FeedTiming holds the feed's clocks, so tests can run them instantly.
public struct FeedTiming: Sendable {
    /// How long a socket may say nothing before it is taken for dead.
    public var silenceLimit: TimeInterval = 15
    /// How often the client pings. Portal answers a ping at once, so a live
    /// socket is never silent for long even when the conversation is idle.
    public var pingInterval: TimeInterval = 5
    /// The pauses before each reconnect attempt, the last one repeating.
    public var backoff: [TimeInterval] = [1, 2, 4, 8, 10]
    public var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    public var now: @Sendable () -> Date = { Date() }

    public init() {}

    func pause(afterFailures failures: Int) -> TimeInterval {
        guard !backoff.isEmpty else { return 0 }
        return backoff[min(max(failures - 1, 0), backoff.count - 1)]
    }
}

/// SilenceWatch remembers when a socket last said anything.
final class SilenceWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var heardAt: Date

    init(now: Date) { heardAt = now }

    func heard(at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        heardAt = date
    }

    func silence(at date: Date) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return date.timeIntervalSince(heardAt)
    }
}

/// SubscriptionRequest is one subscription to keep alive: its document, its
/// variables and the root field the payloads come under.
public struct SubscriptionRequest: Sendable {
    public let query: String
    public let variables: [String: JSONValue]
    public let field: String

    public init(query: String, variables: [String: JSONValue] = [:], field: String) {
        self.query = query
        self.variables = variables
        self.field = field
    }
}

/// RawFeedUpdate is what a kept-alive subscription hands its caller before
/// the payload is read into a type.
enum RawFeedUpdate: Equatable, Sendable {
    case connected
    case payload(JSONValue)
    case reconnecting
    case signedOut
}

/// SubscriptionFeed keeps one graphql-transport-ws subscription alive: it
/// pings, watches for silence, renews the token when Portal closes the socket
/// with 4401 (its access tokens last five minutes), and reconnects with a
/// growing pause.
enum SubscriptionFeed {
    static func updates(
        connection: Connection, request: SubscriptionRequest, socketFactory: @escaping FeedSocketFactory, timing: FeedTiming
    ) -> AsyncStream<RawFeedUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await run(connection: connection, request: request, socketFactory: socketFactory, timing: timing) {
                    continuation.yield($0)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum Ending {
        case unauthorized
        case lost(wasSubscribed: Bool)
    }

    static func run(
        connection: Connection, request: SubscriptionRequest, socketFactory: FeedSocketFactory, timing: FeedTiming,
        yield: @Sendable (RawFeedUpdate) -> Void
    ) async {
        var failures = 0
        var refusedToken: String?
        while !Task.isCancelled {
            do {
                let token: String
                if let refused = refusedToken {
                    token = try await connection.accessToken(replacing: refused)
                    refusedToken = nil
                } else {
                    token = try await connection.accessToken()
                }
                let server = await connection.server
                let ending = await runSocket(socket: try await socketFactory(server, token), request: request, timing: timing, yield: yield)
                switch ending {
                case .unauthorized:
                    refusedToken = token
                    failures = 0
                    yield(.reconnecting)
                    continue
                case .lost(let wasSubscribed):
                    failures = wasSubscribed ? 1 : failures + 1
                    // A socket that never subscribed, twice, may be one the
                    // server refuses for its token: renew before the next try.
                    if !wasSubscribed, failures >= 2 { refusedToken = token }
                }
            } catch let error as PortalError where error == .signedOut {
                yield(.signedOut)
                return
            } catch is CancellationError {
                return
            } catch {
                failures += 1
            }
            yield(.reconnecting)
            do {
                try await timing.sleep(timing.pause(afterFailures: failures))
            } catch {
                return
            }
        }
    }

    private static func runSocket(
        socket: any FeedSocket, request: SubscriptionRequest, timing: FeedTiming, yield: @Sendable (RawFeedUpdate) -> Void
    ) async -> Ending {
        let watch = SilenceWatch(now: timing.now())
        let guardian = Task {
            while !Task.isCancelled {
                do { try await timing.sleep(timing.pingInterval) } catch { return }
                if watch.silence(at: timing.now()) > timing.silenceLimit {
                    socket.close()
                    return
                }
                try? await socket.send(SubscriptionMessage.ping.encoded())
            }
        }
        defer {
            guardian.cancel()
            socket.close()
        }
        var isSubscribed = false
        do {
            try await socket.send(SubscriptionMessage.connectionInit.encoded())
            while !Task.isCancelled {
                let frame = try await socket.receive()
                watch.heard(at: timing.now())
                switch frame {
                case .closed(let code):
                    return code == SubscriptionMessage.unauthorizedCloseCode ? .unauthorized : .lost(wasSubscribed: isSubscribed)
                case .text(let text):
                    guard let message = try? SubscriptionMessage(decoding: text) else { continue }
                    switch message {
                    case .connectionAck:
                        try await socket.send(SubscriptionMessage.subscribe(id: "1", query: request.query, variables: request.variables).encoded())
                        isSubscribed = true
                        yield(.connected)
                    case .ping:
                        try await socket.send(SubscriptionMessage.pong.encoded())
                    case .next(_, let data, let errors):
                        if !errors.isEmpty { continue }
                        guard let payload = data?[request.field], payload != .null else { continue }
                        yield(.payload(payload))
                    case .error, .complete:
                        return .lost(wasSubscribed: isSubscribed)
                    default:
                        continue
                    }
                }
            }
        } catch {
            return .lost(wasSubscribed: isSubscribed)
        }
        return .lost(wasSubscribed: isSubscribed)
    }
}

/// ConversationFeed streams a conversation's events through the
/// graphql-transport-ws subscription OnConversationEvent.
public enum ConversationFeed {
    public static func updates(
        connection: Connection, conversationId: String, socketFactory: @escaping FeedSocketFactory, timing: FeedTiming = FeedTiming()
    ) -> AsyncStream<FeedUpdate> {
        let request = SubscriptionRequest(
            query: Documents.onConversationEvent, variables: ["conversationId": .string(conversationId)], field: "OnConversationEvent")
        let raw = SubscriptionFeed.updates(connection: connection, request: request, socketFactory: socketFactory, timing: timing)
        return AsyncStream { continuation in
            let task = Task {
                for await update in raw {
                    switch update {
                    case .connected: continuation.yield(.connected)
                    case .reconnecting: continuation.yield(.reconnecting)
                    case .signedOut: continuation.yield(.signedOut)
                    case .payload(let payload):
                        if let event = try? JSONDecoder().decode(ConversationEvent.self, from: JSONEncoder().encode(payload)) {
                            continuation.yield(.event(event))
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// NotificationFeedUpdate is what the inbox feed tells a screen.
public enum NotificationFeedUpdate: Equatable, Sendable {
    /// The socket is subscribed. Events are not replayed after a reconnect,
    /// so the inbox is read again.
    case connected
    /// A row was created. The event carries no content: read the row.
    case created(notificationId: String, kind: String?)
    case reconnecting
    case signedOut
}

/// NotificationFeed streams the inbox's OnNotification subscription, with the
/// same keep-alive, 4401 renewal and reconnect as a conversation's.
public enum NotificationFeed {
    public static func updates(
        connection: Connection, socketFactory: @escaping FeedSocketFactory, timing: FeedTiming = FeedTiming()
    ) -> AsyncStream<NotificationFeedUpdate> {
        let request = SubscriptionRequest(query: Documents.onNotification, field: "OnNotification")
        let raw = SubscriptionFeed.updates(connection: connection, request: request, socketFactory: socketFactory, timing: timing)
        return AsyncStream { continuation in
            let task = Task {
                for await update in raw {
                    switch update {
                    case .connected: continuation.yield(.connected)
                    case .reconnecting: continuation.yield(.reconnecting)
                    case .signedOut: continuation.yield(.signedOut)
                    case .payload(let payload):
                        guard payload["type"]?.stringValue == "created", let id = payload["notificationId"]?.stringValue, !id.isEmpty else { continue }
                        continuation.yield(.created(notificationId: id, kind: payload["kind"]?.stringValue))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#if canImport(Darwin)
    /// URLSessionFeedSocket is a feed socket on URLSession.
    public final class URLSessionFeedSocket: FeedSocket, @unchecked Sendable {
        private let task: URLSessionWebSocketTask

        init(task: URLSessionWebSocketTask) {
            self.task = task
        }

        public func send(_ text: String) async throws {
            try await task.send(.string(text))
        }

        public func receive() async throws -> FeedFrame {
            do {
                switch try await task.receive() {
                case .string(let text): return .text(text)
                case .data(let data): return .text(String(decoding: data, as: UTF8.self))
                @unknown default: return .text("")
                }
            } catch {
                // The close code is set once the socket has ended.
                let code = task.closeCode.rawValue
                return .closed(code: code > 0 ? code : nil)
            }
        }

        public func close() {
            task.cancel(with: .goingAway, reason: nil)
        }

        /// The real socket: an upgrade request with the bearer token, which
        /// is where Portal authenticates a subscription.
        public static let factory: FeedSocketFactory = { server, accessToken in
            var request = URLRequest(url: server.subscriptionEndpoint)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(SubscriptionMessage.subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
            let task = URLSession.shared.webSocketTask(with: request)
            task.resume()
            return URLSessionFeedSocket(task: task)
        }
    }
#endif
