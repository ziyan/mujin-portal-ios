import Foundation
import Observation
import SwiftUI
import PortalKit
import UIKit
import UserNotifications
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
    /// Where a tapped notification or the assistant speaking first asks the app to go.
    var pendingRoute: PendingRoute?
    /// The memory page a citation in an answer points at, shown over whatever is open.
    var openedCitation: MemoryCitation?
    /// Said once at the top of the screen, such as a sign-in the server ended.
    var notice: String?

    /// The built-in browser being shown, and the page in Safari's view.
    var presentedWeb: WebSession?
    var safariPage: IdentifiableURL?
    /// One browser per account, kept after its screen closes.
    private var webSessions: [String: WebSession] = [:]

    /// A place in the app for one account, from a notification or the assistant speaking first.
    struct PendingRoute: Equatable {
        let userId: String
        let route: PushRoute
    }

    private var connections: [String: Connection] = [:]
    private let webSignIn = WebSignIn()
    private let presence = PresenceReporting()

    /// The one model of the process. Notification taps reach it before any view exists.
    static let shared = AppModel.make()

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
        // A memory citation in an answer opens the page it cites.
        if let citation = MemoryCitation(url: url) {
            openedCitation = citation
            return .handled
        }
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
        // A blank page and the right header first: the browser is reused, and shows the last page until told otherwise.
        session.reset(for: BrowserTarget(url: url, serverHost: account.server.url.host?.lowercased() ?? ""))
        presentedWeb = session
        if isDemo { return }
        // A new one-time address for every page, since it works once and within a minute.
        let handoff = await connection(for: account).webSessionHandoff(to: url)
        session.open(target: url, handoff: handoff)
    }

    /// A browser of its own for a controller's screen, in the account's data store
    /// (so it holds the same cookie) and signed in through a handoff address.
    func makeScreenSession(for account: Account, url: URL) -> WebSession {
        // The page is laid out at the phone's width and does its own panning and zooming, so the web view does none.
        let session = WebSession(accountKey: account.accountKey, dataStoreId: isDemo ? nil : account.webDataStoreId, contentMode: .mobile)
        let scrollView = session.webView.scrollView
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.bouncesZoom = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
        scrollView.contentInsetAdjustmentBehavior = .never
        session.portalHost = account.server.url.host?.lowercased()
        session.renewHandoff = { [weak self] target in
            guard let self, let current = self.ring.accounts.first(where: { $0.accountKey == account.accountKey }) else { return nil }
            return await self.connection(for: current).webSessionHandoff(to: target)
        }
        if isDemo {
            session.loadHTML(
                """
                <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>
                body { margin: 0; background: #101418; color: #d7dee6; font-family: -apple-system, sans-serif; }
                .bar { background: #1d3c8a; padding: 10px 14px; font-size: 13px; }
                .win { margin: 24px; border: 1px solid #2c3540; border-radius: 8px; padding: 16px; background: #181e25; }
                </style></head><body><div class="bar">controller01 (stub screen for the demo)</div>
                <div class="win"><b>Planner</b><br>Running</div><div class="win"><b>Robot bridge</b><br>Connected</div></body></html>
                """)
        } else {
            Task {
                let handoff = await connection(for: account).webSessionHandoff(to: url)
                session.open(target: url, handoff: handoff)
            }
        }
        return session
    }

    func webSession(for account: Account) -> WebSession {
        if let existing = webSessions[account.accountKey] { return existing }
        let session = WebSession(accountKey: account.accountKey, dataStoreId: isDemo ? nil : account.webDataStoreId)
        session.portalHost = account.server.url.host?.lowercased()
        // The web session lasts 12 hours at most and ends with the grant: when
        // a page lands on Portal's login, ask for a new address once.
        session.renewHandoff = { [weak self] target in
            guard let self, let current = self.ring.accounts.first(where: { $0.accountKey == account.accountKey }) else { return nil }
            return await self.connection(for: current).webSessionHandoff(to: target)
        }
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
        // This account stops receiving pushes on this phone first, while the
        // other accounts on it keep theirs; revoking the grant ends them anyway.
        if !isDemo, let token = PushDeviceToken.stored() {
            try? await connection(for: account).unregisterPushDevice(deviceToken: token)
        }
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
            let request = client.authorizationRequest(clientId: PortalClient.builtInClientId, configuration: configuration)
            if let refusal = await client.clientRefusal(for: request) {
                throw PortalError.clientNotRegistered(
                    String(
                        localized:
                            "\(server.displayHost) does not support signing in from this app yet (\(refusal)). Ask its administrator to update Portal."
                    ))
            }
            let returned = try await webSignIn.authenticate(url: request.url)
            let account = try await client.complete(request, returnedURL: returned)
            try store.add(account)
            connections[account.accountKey] = nil
            reloadRing()
            await registerPushDevices()
        } catch WebSignIn.Cancelled.cancelled {
            // The person closed the sign-in page.
        } catch {
            signInError = error.userMessage
        }
    }

    // MARK: push

    /// Tells every signed-in account's server this phone's token. The same
    /// phone with two accounts registers once per account, at every launch
    /// and whenever the token changes.
    func registerPushDevices() async {
        guard !isDemo, let token = PushDeviceToken.stored() else { return }
        let environment = PushEnvironment.current
        let version = AboutView.versionText
        let name = UIDevice.current.name
        for account in ring.accounts {
            let connection = connection(for: account)
            do {
                try await connection.registerPushDevice(deviceToken: token, environment: environment, deviceName: name, appVersion: version)
            } catch {
                handle(error, account: account)
            }
        }
    }

    /// The account a notification is for: several can share a phone.
    func account(forUserId userId: String) -> Account? {
        ring.accounts.first { $0.userId == userId }
    }

    /// A notification was tapped: switch to its account and go where it says.
    func open(_ payload: PushPayload) {
        guard let account = account(forUserId: payload.userId) else { return }
        if account.accountKey != activeAccount?.accountKey { switchTo(account) }
        pendingRoute = PendingRoute(userId: payload.userId, route: payload.route)
    }

    /// Does what a notification's button asked, as the account it is for.
    func perform(_ action: PushAction, for payload: PushPayload) async {
        guard let account = account(forUserId: payload.userId) else { return }
        do {
            try await connection(for: account).perform(action)
        } catch PortalError.cardNoLongerWaiting {
            // Answered somewhere else already; the replacement push clears it.
        } catch {
            handle(error, account: account)
            // The button did nothing: bring the person to the place instead.
            open(payload)
        }
    }

    /// How a notification that arrives while the app is open shows. The
    /// passive replacement for an answered card only clears the original.
    func presentation(for payload: PushPayload) async -> UNNotificationPresentationOptions {
        if payload.isAnswered {
            await Self.removeDelivered(interactionId: payload.interactionId)
            return []
        }
        return [.banner, .list, .sound]
    }

    static func removeDelivered(interactionId: String?) async {
        guard let interactionId else { return }
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.deliveredNotifications().compactMap { notification -> String? in
            PushPayload(userInfo: notification.request.content.userInfo)?.interactionId == interactionId ? notification.request.identifier : nil
        }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// The route for an account, once its screens exist. Taken so it runs once.
    func takeRoute(for account: Account) -> PushRoute? {
        guard let pending = pendingRoute, pending.userId == account.userId else { return nil }
        pendingRoute = nil
        return pending.route
    }

    // MARK: presence

    /// Tells the active account's server whether the app is in front, and
    /// opens the conversation the assistant just started.
    func scenePhaseChanged(isActive: Bool) {
        guard !isDemo else { return }
        presence.setActive(isActive, account: activeAccount, connection: activeAccount.map { connection(for: $0) }) { [weak self] pending in
            self?.assistantSpoke(pending)
        }
    }

    func touched() { presence.touched() }

    private func assistantSpoke(_ pending: PendingSpeakFirst) {
        guard let account = activeAccount else { return }
        let memory = SpeakFirstMemory()
        guard memory.isNew(pending) else { return }
        memory.markHandled(pending)
        pendingRoute = PendingRoute(userId: account.userId, route: .conversation(id: pending.conversationId))
    }
}

/// PresenceReporting keeps the server told that the app is in front: at once
/// on foreground, every minute while visible, and once when it leaves.
@MainActor
final class PresenceReporting {
    private var task: Task<Void, Never>?
    private var lastTouch = Date()
    private var reportedConnection: Connection?
    private let reporterId = ReporterIdentity.current()

    func touched() { lastTouch = Date() }

    func setActive(
        _ isActive: Bool, account: Account?, connection: Connection?, onSpeakFirst: @escaping @MainActor (PendingSpeakFirst) -> Void
    ) {
        task?.cancel()
        task = nil
        if isActive, let connection {
            lastTouch = Date()
            reportedConnection = connection
            let reporterId = reporterId
            task = Task { [weak self] in
                while !Task.isCancelled {
                    let idle = PresenceRules.idleSeconds(since: self?.lastTouch ?? Date(), now: Date())
                    if let pending = try? await connection.reportPresence(isVisible: true, idleSeconds: idle, reporterId: reporterId) {
                        onSpeakFirst(pending)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(PresenceRules.reportInterval * 1_000_000_000))
                }
            }
        } else if let connection = reportedConnection {
            reportedConnection = nil
            let reporterId = reporterId
            // Said once as the app leaves the front; the system may suspend the app right after.
            let background = UIApplication.shared.beginBackgroundTask(withName: "presence")
            Task {
                _ = try? await connection.reportPresence(isVisible: false, idleSeconds: 0, reporterId: reporterId)
                UIApplication.shared.endBackgroundTask(background)
            }
        }
    }
}
