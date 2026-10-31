import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The sign-in settings every Portal instance shares with this app.
public enum PortalClient {
    /// The built-in native client every Portal instance registers for this app.
    public static let builtInClientId = "mujin-portal-ios"
    /// Where the browser returns after sign-in: a private-use scheme (RFC 8252).
    public static let redirectURI = "com.ziyan.mujinportal:/oauth"
    public static let callbackScheme = "com.ziyan.mujinportal"
    public static let scopes = ["openid", "profile", "email", "offline_access", "api:read", "api:write"]
}

/// OIDCConfiguration is what a server's discovery document says about
/// itself, reduced to what the app uses.
public struct OIDCConfiguration: Decodable, Equatable, Sendable {
    public let issuer: String
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let revocationEndpoint: URL?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case revocationEndpoint = "revocation_endpoint"
    }
}

/// AuthorizationRequest is a sign-in under way: the page to show the person
/// and what is needed to finish when the browser returns.
public struct AuthorizationRequest: Equatable, Sendable {
    public let url: URL
    public let state: String
    public let pkce: PKCE
    public let clientId: String
    public let configuration: OIDCConfiguration
}

/// OIDCClient signs the app in to one Portal instance as a public client
/// (authorization code with PKCE, no secret).
public struct OIDCClient: Sendable {
    public let server: ServerAddress
    let transport: any HTTPTransport

    public init(server: ServerAddress, transport: any HTTPTransport) {
        self.server = server
        self.transport = transport
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case idToken = "id_token"
        }
    }

    struct OAuthRefusal: Decodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    /// Reads the server's discovery document.
    public func discover() async throws -> OIDCConfiguration {
        var request = URLRequest(url: server.endpoint("/.well-known/openid-configuration"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw PortalError.refused("This server does not offer sign-in for the app (HTTP \(response.statusCode)).")
        }
        guard let configuration = try? JSONDecoder().decode(OIDCConfiguration.self, from: data) else {
            throw PortalError.unreadableAnswer
        }
        return configuration
    }

    /// Prepares a sign-in for a client: the address of the server's sign-in
    /// page and the secrets to finish with.
    public func authorizationRequest(clientId: String, configuration: OIDCConfiguration, pkce: PKCE = PKCE(), state: String = PKCE.randomState()) -> AuthorizationRequest {
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: PortalClient.redirectURI),
            URLQueryItem(name: "scope", value: PortalClient.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return AuthorizationRequest(url: components.url!, state: state, pkce: pkce, clientId: clientId, configuration: configuration)
    }

    /// Asks the server whether it knows the client, before the person is
    /// sent to a page that would only show an error. Returns nil when the
    /// client is known, or the server's own words when it is not.
    public func clientRefusal(for request: AuthorizationRequest) async -> String? {
        var probe = URLRequest(url: request.url)
        probe.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await transport.send(probe) else { return nil }
        guard response.statusCode == 400 || response.statusCode == 401 else { return nil }
        if let refusal = try? JSONDecoder().decode(OAuthRefusal.self, from: data) {
            return refusal.errorDescription ?? refusal.error
        }
        return "HTTP \(response.statusCode)"
    }

    /// The code a return to the redirect address carries, when it answers the
    /// request made with `state`. Throws the server's refusal when the return
    /// carries an error.
    public static func authorizationCode(in returned: URL, state: String) throws -> String {
        let items = URLComponents(url: returned, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw PortalError.refused(value("error_description") ?? error)
        }
        guard value("state") == state, let code = value("code"), !code.isEmpty else {
            throw PortalError.refused("The sign-in did not finish. Try again.")
        }
        return code
    }

    /// Exchanges the returned code for the app's sign-in.
    public func complete(_ request: AuthorizationRequest, returnedURL: URL, now: Date = Date()) async throws -> Account {
        let code = try Self.authorizationCode(in: returnedURL, state: request.state)
        let token = try await post(
            to: request.configuration.tokenEndpoint,
            form: [
                "grant_type": "authorization_code", "client_id": request.clientId, "code": code,
                "code_verifier": request.pkce.verifier, "redirect_uri": PortalClient.redirectURI,
            ], invalidGrant: .refused("The sign-in expired before it finished. Try again."))
        guard let idToken = token.idToken, let claims = IDTokenClaims(idToken) else { throw PortalError.unreadableAnswer }
        return Account(
            server: server, clientId: request.clientId, userId: claims.subject, displayName: claims.name ?? claims.email ?? claims.subject,
            email: claims.email ?? "", accessToken: token.accessToken, refreshToken: token.refreshToken ?? "",
            accessTokenExpiresAt: now.addingTimeInterval(token.expiresIn ?? 300))
    }

    /// Renews an account's sign-in. The server retires the old refresh token.
    public func refresh(_ account: Account, now: Date = Date()) async throws -> Account {
        let configuration = try await discover()
        let token = try await post(
            to: configuration.tokenEndpoint,
            form: ["grant_type": "refresh_token", "client_id": account.clientId, "refresh_token": account.refreshToken],
            invalidGrant: .signedOut)
        var renewed = account
        renewed.accessToken = token.accessToken
        renewed.refreshToken = token.refreshToken ?? account.refreshToken
        renewed.accessTokenExpiresAt = now.addingTimeInterval(token.expiresIn ?? 300)
        return renewed
    }

    /// Ends the grant at the server through the discovery document's
    /// `revocation_endpoint` (RFC 7009): every refresh token, the web
    /// sessions handed to the built-in browser and the push devices of this
    /// sign-in go with it. The answer is always 200 for a known client, so
    /// nothing is read from it; a failure only means the person can end the
    /// grant under Authorized apps on the web.
    public func revoke(_ account: Account) async {
        guard let endpoint = (try? await discover())?.revocationEndpoint else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "token": account.refreshToken.isEmpty ? account.accessToken : account.refreshToken, "client_id": account.clientId,
        ])
        _ = try? await transport.send(request)
    }

    func post(to endpoint: URL, form: [String: String], invalidGrant: PortalError) async throws -> TokenResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            if let refusal = try? JSONDecoder().decode(OAuthRefusal.self, from: data), refusal.error == "invalid_grant" {
                throw invalidGrant
            }
            throw Self.refusal(data)
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else { throw PortalError.unreadableAnswer }
        return token
    }

    static func refusal(_ data: Data) -> PortalError {
        if let refusal = try? JSONDecoder().decode(OAuthRefusal.self, from: data) {
            return .refused(refusal.errorDescription ?? refusal.error)
        }
        return .unreadableAnswer
    }

    /// The fields form-encoded, in a stable order.
    static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = form.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}

/// IDTokenClaims reads who an ID token is for. The token comes straight from
/// the token endpoint over TLS, so its signature is not checked again here.
struct IDTokenClaims {
    let subject: String
    let name: String?
    let email: String?

    init?(_ token: String) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload), let claims = try? JSONDecoder().decode([String: JSONValue].self, from: data),
            let subject = claims["sub"]?.stringValue, !subject.isEmpty
        else { return nil }
        self.subject = subject
        self.name = claims["name"]?.stringValue
        self.email = claims["email"]?.stringValue
    }
}
