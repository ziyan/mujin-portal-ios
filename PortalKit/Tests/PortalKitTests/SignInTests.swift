import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import PortalKit

@Suite struct OIDCClientTests {
    static var discovery: [String: Any] { [
        "issuer": "https://portal.example.test",
        "authorization_endpoint": "https://portal.example.test/api/v1/oidc/authorize",
        "token_endpoint": "https://portal.example.test/api/v1/oidc/token",
    ] }

    func client(_ respond: @escaping @Sendable (URLRequest) async throws -> (Int, Data)) -> (OIDCClient, ScriptedTransport) {
        let transport = ScriptedTransport(respond: respond)
        return (OIDCClient(server: try! ServerAddress("https://portal.example.test"), transport: transport), transport)
    }

    @Test func discoveryIsReadFromTheWellKnownPath() async throws {
        let (client, transport) = client { _ in (200, ScriptedTransport.json(Self.discovery)) }
        let configuration = try await client.discover()
        #expect(configuration.tokenEndpoint.path == "/api/v1/oidc/token")
        #expect(transport.requests.first?.url?.path == "/.well-known/openid-configuration")
    }

    @Test func theAuthorizationAddressAsksForPKCEAndTheScopes() async throws {
        let (client, _) = client { _ in (200, ScriptedTransport.json(Self.discovery)) }
        let configuration = try await client.discover()
        let request = client.authorizationRequest(clientId: "mujin-portal-ios", configuration: configuration, pkce: PKCE(verifier: "v"), state: "s1")
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("response_type") == "code")
        #expect(value("client_id") == "mujin-portal-ios")
        #expect(value("redirect_uri") == "com.ziyan.mujinportal:/oauth")
        #expect(value("scope") == "openid profile email offline_access api:read api:write")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == PKCE(verifier: "v").challenge)
        #expect(value("state") == "s1")
    }

    @Test func theReturnedCodeIsExchangedForAnAccount() async throws {
        let (client, transport) = client { request in
            if request.url?.path == "/api/v1/oidc/token" {
                return (
                    200,
                    ScriptedTransport.json([
                        "access_token": "access-9", "refresh_token": "refresh-9", "expires_in": 300, "token_type": "Bearer",
                        "id_token": makeIDToken(subject: "user77", name: "Alex Example", email: "alex@example.test"),
                    ]))
            }
            return (200, ScriptedTransport.json(Self.discovery))
        }
        let configuration = try await client.discover()
        let request = client.authorizationRequest(clientId: "mujin-portal-ios", configuration: configuration, pkce: PKCE(verifier: "v"), state: "s1")
        let now = Date(timeIntervalSince1970: 1_000)
        let account = try await client.complete(request, returnedURL: URL(string: "com.ziyan.mujinportal:/oauth?code=abc&state=s1")!, now: now)
        #expect(account.userId == "user77")
        #expect(account.displayName == "Alex Example")
        #expect(account.accessToken == "access-9")
        #expect(account.refreshToken == "refresh-9")
        #expect(account.accessTokenExpiresAt == now.addingTimeInterval(300))
        let body = String(decoding: transport.requests.last!.httpBody!, as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=abc"))
        #expect(body.contains("code_verifier=v"))
        #expect(body.contains("redirect_uri=com.ziyan.mujinportal%3A%2Foauth"))
    }

    @Test func aReturnWithTheWrongStateOrAnErrorIsRefused() throws {
        #expect(throws: PortalError.self) {
            try OIDCClient.authorizationCode(in: URL(string: "com.ziyan.mujinportal:/oauth?code=abc&state=other")!, state: "s1")
        }
        #expect(throws: PortalError.refused("The person said no")) {
            try OIDCClient.authorizationCode(
                in: URL(string: "com.ziyan.mujinportal:/oauth?error=access_denied&error_description=The%20person%20said%20no&state=s1")!, state: "s1")
        }
    }

    @Test func refreshRotatesTheRefreshToken() async throws {
        let (client, transport) = client { request in
            if request.url?.path == "/api/v1/oidc/token" {
                return (200, ScriptedTransport.json(["access_token": "access-2", "refresh_token": "refresh-2", "expires_in": 300]))
            }
            return (200, ScriptedTransport.json(Self.discovery))
        }
        let now = Date(timeIntervalSince1970: 5_000)
        let renewed = try await client.refresh(makeAccount(), now: now)
        #expect(renewed.accessToken == "access-2")
        #expect(renewed.refreshToken == "refresh-2")
        #expect(renewed.userId == "user01")
        #expect(String(decoding: transport.requests.last!.httpBody!, as: UTF8.self).contains("refresh_token=refresh-1"))
    }

    @Test func aRefusedRefreshTokenMeansSignedOut() async {
        let (client, _) = client { request in
            if request.url?.path == "/api/v1/oidc/token" { return (400, ScriptedTransport.json(["error": "invalid_grant"])) }
            return (200, ScriptedTransport.json(Self.discovery))
        }
        await #expect(throws: PortalError.signedOut) { try await client.refresh(makeAccount()) }
    }

    @Test func anUnknownClientIsReportedInTheServersWords() async throws {
        let (client, _) = client { request in
            if request.url?.path == "/api/v1/oidc/authorize" {
                return (400, ScriptedTransport.json(["error": "invalid_client", "error_description": "unknown or disabled client"]))
            }
            return (200, ScriptedTransport.json(Self.discovery))
        }
        let configuration = try await client.discover()
        let request = client.authorizationRequest(clientId: "mujin-portal-ios", configuration: configuration)
        #expect(await client.clientRefusal(for: request) == "unknown or disabled client")
    }

    @Test func signingOutAsksTheDiscoveredRevocationEndpointToEndTheGrant() async throws {
        var document = Self.discovery
        document["revocation_endpoint"] = "https://portal.example.test/api/v1/oidc/revoke"
        let discovery = ScriptedTransport.json(document)
        let (client, transport) = client { request in
            if request.url?.path == "/api/v1/oidc/revoke" { return (200, Data()) }
            return (200, discovery)
        }
        await client.revoke(makeAccount())
        let revocation = try #require(transport.requests.last)
        #expect(revocation.url?.path == "/api/v1/oidc/revoke")
        #expect(revocation.httpMethod == "POST")
        let body = String(decoding: revocation.httpBody!, as: UTF8.self)
        #expect(body.contains("client_id=mujin-portal-ios"))
        #expect(body.contains("token=refresh-1"))
    }

    @Test func aServerWithoutARevocationEndpointIsLeftAlone() async {
        let (client, transport) = client { _ in (200, ScriptedTransport.json(Self.discovery)) }
        await client.revoke(makeAccount())
        #expect(transport.requests.allSatisfy { $0.url?.path == "/.well-known/openid-configuration" })
    }
}
