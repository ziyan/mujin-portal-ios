import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import PortalKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Guarded is a value behind a lock, for fakes that async code touches.
final class Guarded<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// ScriptedTransport answers requests from a closure and remembers them.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let recorded = Guarded<[URLRequest]>([])
    private let respond: @Sendable (URLRequest) async throws -> (Int, Data)

    init(respond: @escaping @Sendable (URLRequest) async throws -> (Int, Data)) {
        self.respond = respond
    }

    var requests: [URLRequest] { recorded.withValue { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withValue { $0.append(request) }
        let (status, data) = try await respond(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

func makeAccount(
    server: String = "https://portal.example.test", userId: String = "user01", accessToken: String = "access-1", refreshToken: String = "refresh-1",
    expiresAt: Date = Date().addingTimeInterval(300)
) -> Account {
    Account(
        server: try! ServerAddress(server), clientId: PortalClient.builtInClientId, userId: userId, displayName: "Alex Example",
        email: "alex@example.test", accessToken: accessToken, refreshToken: refreshToken, accessTokenExpiresAt: expiresAt)
}

/// A JWT-shaped string with the claims, unsigned.
func makeIDToken(subject: String, name: String? = nil, email: String? = nil) -> String {
    var claims: [String: Any] = ["sub": subject]
    if let name { claims["name"] = name }
    if let email { claims["email"] = email }
    func encode(_ object: Any) -> String {
        PKCE.base64URL(try! JSONSerialization.data(withJSONObject: object))
    }
    return "\(encode(["alg": "none"])).\(encode(claims)).signature"
}

/// ScriptedSocket plays back frames and records what the client sent.
final class ScriptedSocket: FeedSocket, @unchecked Sendable {
    private struct State {
        var incoming: [FeedFrame]
        var sent: [String] = []
        var isClosed = false
    }
    private let state: Guarded<State>
    private let onSend: @Sendable (String, ScriptedSocket) -> Void

    /// `frames` are handed out in order; once they run out, `receive` waits
    /// until the socket is closed (a socket gone silent).
    init(frames: [FeedFrame], onSend: @escaping @Sendable (String, ScriptedSocket) -> Void = { _, _ in }) {
        state = Guarded(State(incoming: frames))
        self.onSend = onSend
    }

    var sent: [String] { state.withValue { $0.sent } }
    var wasClosed: Bool { state.withValue { $0.isClosed } }

    func push(_ frame: FeedFrame) {
        state.withValue { $0.incoming.append(frame) }
    }

    func send(_ text: String) async throws {
        state.withValue { $0.sent.append(text) }
        onSend(text, self)
    }

    func receive() async throws -> FeedFrame {
        while true {
            let next: FeedFrame?? = state.withValue { state in
                if !state.incoming.isEmpty { return .some(state.incoming.removeFirst()) }
                return state.isClosed ? .some(nil) : nil
            }
            if let next { return next ?? .closed(code: nil) }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func close() {
        state.withValue { $0.isClosed = true }
    }
}

func ackFrame() -> FeedFrame { .text(#"{"type":"connection_ack"}"#) }

func eventFrame(_ payload: String) -> FeedFrame {
    .text(#"{"id":"1","type":"next","payload":{"data":{"OnConversationEvent":\#(payload)}}}"#)
}
