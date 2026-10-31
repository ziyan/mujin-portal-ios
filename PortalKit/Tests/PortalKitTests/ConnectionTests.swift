import Foundation
import Testing

@testable import PortalKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite struct ConnectionTests {
    static let discovery: Data = ScriptedTransport.json([
        "issuer": "https://portal.example.test",
        "authorization_endpoint": "https://portal.example.test/api/v1/oidc/authorize",
        "token_endpoint": "https://portal.example.test/api/v1/oidc/token",
    ])

    /// A server that answers GraphQL with `{"data":{"Me":{...}}}` for the token it
    /// currently accepts, and rotates refresh tokens the way Portal does.
    final class FakeServer: @unchecked Sendable {
        let state = Guarded<(accepted: String, refreshCount: Int, nextRefresh: Int)>(("access-1", 0, 2))
        let tokenDelayNanoseconds: UInt64

        init(tokenDelayNanoseconds: UInt64 = 0) {
            self.tokenDelayNanoseconds = tokenDelayNanoseconds
        }

        func respond(_ request: URLRequest) async throws -> (Int, Data) {
            switch request.url?.path {
            case "/.well-known/openid-configuration":
                return (200, ConnectionTests.discovery)
            case "/api/v1/oidc/token":
                try await Task.sleep(nanoseconds: tokenDelayNanoseconds)
                let rotated = state.withValue { state -> Int in
                    state.refreshCount += 1
                    let number = state.nextRefresh
                    state.nextRefresh += 1
                    state.accepted = "access-\(number)"
                    return number
                }
                return (200, ScriptedTransport.json(["access_token": "access-\(rotated)", "refresh_token": "refresh-\(rotated)", "expires_in": 300]))
            default:
                let presented = request.value(forHTTPHeaderField: "Authorization")
                let accepted = state.withValue { $0.accepted }
                if presented == "Bearer \(accepted)" {
                    return (200, ScriptedTransport.json(["data": ["Me": ["id": "user01", "name": "Alex Example"]]]))
                }
                return (401, Data())
            }
        }
    }

    func connection(server: FakeServer, account: Account) -> (Connection, ScriptedTransport, MemoryAccountStore) {
        let transport = ScriptedTransport(respond: server.respond)
        let store = MemoryAccountStore()
        try? store.add(account)
        return (Connection(account: account, transport: transport, store: store), transport, store)
    }

    @Test func aFreshTokenIsSentAsBearerWithoutRenewing() async throws {
        let server = FakeServer()
        let (connection, transport, _) = connection(server: server, account: makeAccount())
        let me = try await connection.me()
        #expect(me.name == "Alex Example")
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(transport.requests[0].url?.path == "/api/v1/graphql")
    }

    @Test func aTokenAboutToExpireIsRenewedFirstAndStored() async throws {
        let server = FakeServer()
        let (connection, _, store) = connection(server: server, account: makeAccount(expiresAt: Date().addingTimeInterval(5)))
        _ = try await connection.me()
        #expect(server.state.withValue { $0.refreshCount } == 1)
        #expect(try store.loadRing().active?.refreshToken == "refresh-2")
    }

    @Test func concurrentCallersShareOneRenewal() async throws {
        let server = FakeServer(tokenDelayNanoseconds: 50_000_000)
        let (connection, _, _) = connection(server: server, account: makeAccount(expiresAt: Date().addingTimeInterval(5)))
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try await connection.me().id } }
            for try await id in group { #expect(id == "user01") }
        }
        // The server retires a refresh token on first use: a second renewal would be refused.
        #expect(server.state.withValue { $0.refreshCount } == 1)
    }

    @Test func aRefusedTokenIsRenewedAndTheRequestRetriedOnce() async throws {
        let server = FakeServer()
        server.state.withValue { $0.accepted = "access-other" }
        let (connection, transport, _) = connection(server: server, account: makeAccount())
        // Renewal makes the server accept the new token.
        let me = try await connection.me()
        #expect(me.id == "user01")
        let graphQLRequests = transport.requests.filter { $0.url?.path == "/api/v1/graphql" }
        #expect(graphQLRequests.count == 2)
        #expect(graphQLRequests[1].value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
    }

    @Test func aSecondRefusalEndsTheSignIn() async throws {
        let transport = ScriptedTransport { request in
            switch request.url?.path {
            case "/.well-known/openid-configuration": return (200, Self.discovery)
            case "/api/v1/oidc/token": return (200, ScriptedTransport.json(["access_token": "access-2", "refresh_token": "refresh-2", "expires_in": 300]))
            default: return (401, Data())
            }
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        await #expect(throws: PortalError.signedOut) { _ = try await connection.me() }
        #expect(await connection.isSignedOut)
    }

    @Test func aRefusedRefreshTokenEndsTheSignIn() async throws {
        let transport = ScriptedTransport { request in
            switch request.url?.path {
            case "/.well-known/openid-configuration": return (200, Self.discovery)
            default: return (400, ScriptedTransport.json(["error": "invalid_grant"]))
            }
        }
        let connection = Connection(account: makeAccount(expiresAt: Date().addingTimeInterval(1)), transport: transport)
        await #expect(throws: PortalError.signedOut) { _ = try await connection.me() }
        #expect(await connection.isSignedOut)
    }

    @Test func graphQLErrorsAreThrownInTheServersWords() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["Me": NSNull()], "errors": [["message": "permission denied"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        await #expect(throws: PortalError.refused("permission denied")) { _ = try await connection.me() }
    }

    @Test func variablesAndDocumentAreSentAsJSON() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SendMessage": ["runId": "run01"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        let runId = try await connection.sendMessage(conversationId: "conversation01", text: "Hello")
        #expect(runId == "run01")
        let body = try JSONDecoder().decode(JSONValue.self, from: transport.requests[0].httpBody!)
        #expect(body["variables"]?["conversationId"]?.stringValue == "conversation01")
        #expect(body["variables"]?["message"]?.stringValue == "Hello")
        #expect(body["query"]?.stringValue?.contains("SendMessage") == true)
    }

    @Test func approvalVerdictsUseThePortalWords() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["ResolveToolApproval": NSNull()]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        try await connection.resolveToolApproval(id: "approval01", isApproved: false, reason: "not now")
        let body = try JSONDecoder().decode(JSONValue.self, from: transport.requests[0].httpBody!)
        #expect(body["variables"]?["verdict"]?.stringValue == "rejected")
        #expect(body["variables"]?["reason"]?.stringValue == "not now")
    }
}
