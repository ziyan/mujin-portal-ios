import Foundation
import Observation
import PortalKit

/// AppModel is the app's state: which accounts are signed in, which one is in
/// use, and a connection for each.
@MainActor
@Observable
final class AppModel {
    let store: any AccountStore
    let transport: any HTTPTransport
    let socketFactory: FeedSocketFactory
    let isDemo: Bool

    private(set) var ring: AccountRing
    /// Why the last sign-in did not happen, in words for the person.
    var signInError: String?
    var isSigningIn = false
    /// Said once at the top of the screen, such as a sign-in the server ended.
    var notice: String?

    private var connections: [String: Connection] = [:]
    private let webSignIn = WebSignIn()

    init(store: any AccountStore, transport: any HTTPTransport, socketFactory: @escaping FeedSocketFactory, isDemo: Bool = false) {
        self.store = store
        self.transport = transport
        self.socketFactory = socketFactory
        self.isDemo = isDemo
        self.ring = (try? store.loadRing()) ?? AccountRing()
    }

    /// The model for this launch: the real network, or the demo server when
    /// launched with `-demo` (screenshots and UI tests).
    static func make() -> AppModel {
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            return DemoServer.makeModel()
        }
        return AppModel(store: KeychainAccountStore(), transport: URLSessionTransport(), socketFactory: URLSessionFeedSocket.factory)
    }

    var activeAccount: Account? { ring.active }
    var accounts: [Account] { ring.accounts }

    /// The connection for an account, made once and kept so that a token
    /// renewal under way is shared by every screen.
    func connection(for account: Account) -> Connection {
        if let existing = connections[account.accountKey] { return existing }
        let connection = Connection(account: account, transport: transport, store: store)
        connections[account.accountKey] = connection
        return connection
    }

    func reloadRing() {
        ring = (try? store.loadRing()) ?? ring
    }

    func switchTo(_ account: Account) {
        try? store.activate(account.accountKey)
        reloadRing()
    }

    /// Signs out of one account on this phone.
    func remove(_ account: Account) async {
        await OIDCClient(server: account.server, transport: transport).revoke(account)
        try? store.remove(account.accountKey)
        connections[account.accountKey] = nil
        reloadRing()
    }

    /// A screen calls this with every error it gets: a sign-in the server
    /// has ended removes the account, since nothing more can be done with it.
    func handle(_ error: Error, account: Account) {
        guard error as? PortalError == .signedOut else { return }
        try? store.remove(account.accountKey)
        connections[account.accountKey] = nil
        reloadRing()
        notice = String(localized: "The sign-in for \(account.displayName) on \(account.server.displayHost) has ended. Sign in again.")
    }

    /// Signs in to a server through its own sign-in page and keeps the account.
    func signIn(to server: ServerAddress) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        notice = nil
        defer { isSigningIn = false }
        do {
            let client = OIDCClient(server: server, transport: transport)
            let configuration = try await client.discover()
            var request = client.authorizationRequest(clientId: PortalClient.builtInClientId, configuration: configuration)
            if let refusal = await client.clientRefusal(for: request) {
                // The server does not know the app's built-in client. Try
                // registering the app; the server accepts that only when it
                // allows the app's redirect address.
                do {
                    let clientId = try await client.register(configuration: configuration)
                    request = client.authorizationRequest(clientId: clientId, configuration: configuration)
                } catch {
                    throw PortalError.clientNotRegistered(
                        String(
                            localized:
                                "\(server.displayHost) does not support signing in from this app yet (\(refusal)). Ask its administrator to update Portal."
                        ))
                }
            }
            let returned = try await webSignIn.authenticate(url: request.url)
            let account = try await client.complete(request, returnedURL: returned)
            try store.add(account)
            connections[account.accountKey] = nil
            reloadRing()
        } catch WebSignIn.Cancelled.cancelled {
            // The person closed the sign-in page.
        } catch {
            signInError = error.userMessage
        }
    }
}

extension Error {
    /// What to tell the person: the app's own words for its own errors, and the
    /// server's or the system's words for theirs.
    var userMessage: String {
        guard let error = self as? PortalError else { return localizedDescription }
        switch error {
        case .signedOut: return String(localized: "This sign-in has ended. Sign in again.")
        case .invalidServerAddress: return String(localized: "Enter a server address that starts with https://.")
        case .unreadableAnswer: return String(localized: "The server sent an answer the app cannot read.")
        case .refused(let message), .clientNotRegistered(let message): return message
        }
    }
}
