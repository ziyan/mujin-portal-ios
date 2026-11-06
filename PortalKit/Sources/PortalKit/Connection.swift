import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Connection is the app talking to one server as one person: GraphQL over
/// HTTPS with the account's bearer token, renewed before it runs out.
public actor Connection {
    /// The account identity stays the same when its tokens are renewed.
    public nonisolated let accountKey: String
    public private(set) var account: Account
    let transport: any HTTPTransport
    let store: (any AccountStore)?

    /// The renewal under way. Whoever needs a token meanwhile waits for it
    /// rather than renewing again: the server retires a refresh token the
    /// first time it is used, so a second renewal with it is refused.
    private var renewal: Task<Account, Error>?

    /// Whether the server has ended this sign-in: it refused the refresh
    /// token, or refused a request again with a token loaded afresh.
    public private(set) var isSignedOut = false

    /// Whether this server's chat messages carry voice and call fields, which an older server refuses. Set from its capabilities.
    public private(set) var hasVoiceMessages = false
    public private(set) var hasChatCalls = false

    public func setChatMedia(hasVoice: Bool, hasCalls: Bool) {
        hasVoiceMessages = hasVoice
        hasChatCalls = hasCalls
    }

    /// Whether this server's messages carry thread fields, which an older server refuses. Set from its capabilities.
    public private(set) var hasMessageThreads = false

    public func setMessageThreads(_ hasThreads: Bool) {
        hasMessageThreads = hasThreads
    }

    /// The document as this server takes it.
    public func prepared(_ document: String) -> String {
        let withMedia = Documents.withChatMedia(document, hasVoice: hasVoiceMessages, hasCalls: hasChatCalls)
        return hasMessageThreads ? Documents.withThreads(withMedia) : withMedia
    }

    /// How long before a token runs out it is renewed. Access tokens last
    /// five minutes, so this is a margin for the request in flight.
    static let renewBefore: TimeInterval = 30

    public init(account: Account, transport: any HTTPTransport, store: (any AccountStore)? = nil) {
        self.accountKey = account.accountKey
        self.account = account
        self.transport = transport
        self.store = store
    }

    public var server: ServerAddress { account.server }

    /// The token to send now, renewed first when it is close to running out.
    public func accessToken(now: Date = Date()) async throws -> String {
        if isSignedOut { throw PortalError.signedOut }
        if let renewal {
            return try await outcome(of: renewal).accessToken
        }
        if account.accessTokenExpiresAt.timeIntervalSince(now) < Self.renewBefore {
            // Another process may have renewed the sign-in already, which
            // retired the refresh token held here.
            if let stored = try? store?.load(accountKey: account.accountKey), stored.accessTokenExpiresAt > account.accessTokenExpiresAt {
                account = stored
                if account.accessTokenExpiresAt.timeIntervalSince(now) >= Self.renewBefore { return account.accessToken }
            }
            guard !account.refreshToken.isEmpty else { return account.accessToken }
            return try await renew(now: now).accessToken
        }
        return account.accessToken
    }

    /// A token to use in place of one the server refused: a newer one this
    /// connection already has, or else a renewal.
    public func accessToken(replacing refused: String, now: Date = Date()) async throws -> String {
        if let renewal {
            return try await outcome(of: renewal).accessToken
        }
        if account.accessToken != refused {
            return account.accessToken
        }
        // Without a refresh token there is nothing to renew with, but only the server refusing one ends a sign-in.
        guard !account.refreshToken.isEmpty else { throw PortalError.notPermitted }
        return try await renew(now: now).accessToken
    }

    /// Renews the sign-in once, however many callers ask while it is under
    /// way, and stores it.
    func renew(now: Date) async throws -> Account {
        if let renewal {
            return try await outcome(of: renewal)
        }
        let renewing = Task { [account, transport, store] in
            let renewed = try await OIDCClient(server: account.server, transport: transport).refresh(account, now: now)
            try? store?.save(renewed)
            return renewed
        }
        renewal = renewing
        defer { renewal = nil }
        return try await outcome(of: renewing)
    }

    private func outcome(of renewing: Task<Account, Error>) async throws -> Account {
        do {
            let renewed = try await renewing.value
            if renewed.accessTokenExpiresAt >= account.accessTokenExpiresAt {
                account = renewed
            }
            return renewed
        } catch {
            if error as? PortalError == .signedOut {
                isSignedOut = true
            }
            throw error
        }
    }

    /// Sends a request with the account's token. A 401 is tried once more
    /// with a token loaded afresh; a second 401 means the sign-in has ended.
    func send(authorizing request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        let token = try await accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 401 else {
            return (data, response)
        }
        let freshToken = try await accessToken(replacing: token)
        request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
        let (retriedData, retriedResponse) = try await transport.send(request)
        if retriedResponse.statusCode == 401 {
            // A fresh token was refused too. That says something about this request, not about the sign-in:
            // the account stays, and only the refresh token being refused (invalid_grant) ends it.
            throw PortalError.notPermitted
        }
        return (retriedData, retriedResponse)
    }

    struct GraphQLAnswer<Answer: Decodable>: Decodable {
        let data: Answer?
        let errors: [GraphQLError]?
    }

    public struct GraphQLError: Decodable, Equatable, Sendable {
        public struct Extensions: Decodable, Equatable, Sendable {
            /// A machine-readable code, such as `CARD_NO_LONGER_WAITING` or `ASSISTANT_BUSY`.
            public let code: String?
            /// For a card that is no longer waiting: `answered`, `cancelled` or `expired`.
            public let reason: String?
        }
        public let message: String
        public let extensions: Extensions?

        public init(message: String, extensions: Extensions? = nil) {
            self.message = message
            self.extensions = extensions
        }
    }

    /// Runs a GraphQL document and decodes its data.
    public func execute<Answer: Decodable & Sendable>(
        _ document: String, variables: [String: JSONValue] = [:], as answer: Answer.Type
    ) async throws -> Answer {
        var request = URLRequest(url: account.server.endpoint("/api/v1/graphql"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": JSONValue.string(prepared(document)), "variables": .object(variables)])
        let (data, _) = try await send(authorizing: request)
        // The errors are read on their own first: a refused field comes back
        // as null beside them, which the answer's own shape does not allow.
        if let error = (try? JSONDecoder().decode(GraphQLAnswer<JSONValue>.self, from: data))?.errors?.first {
            throw PortalError(graphQLError: error)
        }
        guard let decoded = try? JSONDecoder().decode(GraphQLAnswer<Answer>.self, from: data), let value = decoded.data else {
            throw PortalError.unreadableAnswer
        }
        return value
    }
}
