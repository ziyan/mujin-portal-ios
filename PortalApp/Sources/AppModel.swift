import Foundation
import Observation
import SwiftUI
import PortalKit
import WebKit

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
    /// Whether the active account's server can register this phone for push
    /// notifications. Until it can, the token is only kept on the phone.
    var isPushRegistrationOffered = false
    /// Said once at the top of the screen, such as a sign-in the server ended.
    var notice: String?

    /// The built-in browser being shown, and the page in Safari's view.
    var presentedWeb: WebSession?
    var safariPage: IdentifiableURL?
    /// One browser per account, kept after its screen closes.
    private var webSessions: [String: WebSession] = [:]

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

    /// Decides where a tapped link opens: Portal and its controllers in the
    /// built-in browser, other web addresses in Safari's view, anything else
    /// (mail, phone) in the system.
    func handleLink(_ url: URL) -> OpenURLAction.Result {
        guard let account = activeAccount else { return .systemAction }
        switch LinkClassifier.classify(url, server: account.server) {
        case .portal, .controller:
            Task { await openInApp(url, account: account) }
            return .handled
        case .external:
            safariPage = IdentifiableURL(url: url)
            return .handled
        case .other:
            return .systemAction
        }
    }

    /// Opens a Portal or controller page in the account's browser. When the
    /// server can hand over a web session, the page opens signed in;
    /// otherwise it opens as it is and Portal's login page shows.
    func openInApp(_ url: URL, account: Account) async {
        let session = webSession(for: account)
        presentedWeb = session
        if isDemo { return }
        let target = await connection(for: account).webSessionHandoff(to: url) ?? url
        session.load(target)
    }

    func webSession(for account: Account) -> WebSession {
        if let existing = webSessions[account.accountKey] { return existing }
        let session = WebSession(accountKey: account.accountKey, dataStoreId: isDemo ? nil : account.webDataStoreId)
        webSessions[account.accountKey] = session
        return session
    }

    /// Forgets an account's browser and deletes the cookies it kept.
    private func removeWebData(of account: Account) async {
        if presentedWeb?.accountKey == account.accountKey { presentedWeb = nil }
        webSessions[account.accountKey] = nil
        if !isDemo { try? await WKWebsiteDataStore.remove(forIdentifier: account.webDataStoreId) }
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
        await removeWebData(of: account)
        reloadRing()
    }

    /// A screen calls this with every error it gets: a sign-in the server
    /// has ended removes the account, since nothing more can be done with it.
    func handle(_ error: Error, account: Account) {
        guard error as? PortalError == .signedOut else { return }
        try? store.remove(account.accountKey)
        connections[account.accountKey] = nil
        Task { await removeWebData(of: account) }
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
