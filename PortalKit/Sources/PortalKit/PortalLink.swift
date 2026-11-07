import Foundation

/// PortalLink is a page of the Portal web app that the app has a screen for:
/// the same pages Portal's server turns into a native card when a link to one
/// is sent in a chat. It is read from a web address and written back to one,
/// so a link copied in the app opens the same page in a browser.
public enum PortalLink: Equatable, Hashable, Sendable {
    /// `/ticket/<sequence>`: the number shown as "#12", not the ticket's id.
    case ticket(sequence: Int64)
    /// `/controller/<id>`
    case controller(id: String)
    /// `/controller/<id>/backups`
    case controllerBackups(id: String)
    /// `/virtualcontroller/<id>`
    case virtualController(id: String)
    /// `/virtualcontroller/<id>/snapshots`
    case virtualControllerSnapshots(id: String)
    /// `/release/<id>`
    case release(id: String)
    /// `/site/<id>`
    case site(id: String)
    /// `/site/<siteId>/cell/<id>`
    case cell(id: String, siteId: String)
    /// `/site/<siteId>/page/<id>`: a documentation page of a site.
    case sitePage(id: String, siteId: String)
    /// `/site/<siteId>/page`: the tree of a site's documentation pages.
    case sitePages(siteId: String)
    /// `/surveillance/<cameraId>`
    case camera(id: String)
    /// `/organization/<id>`
    case organization(id: String)
    /// `/organization/<id>/members`, `/groups`, `/roles`, `/audit` and `/billing`
    case organizationPage(OrganizationPage, organizationId: String)
    /// `/user/<id>`
    case user(id: String)
    /// `/agent/<id>`: a conversation with the assistant, or a chat; both are conversations to the server.
    case conversation(id: String)
    /// `/incident/<id>`
    case incident(id: String)
    /// `/chat/<chatId>/<messageId>`: one message of a chat, which the app opens in the reader's own conversation of it.
    case chatMessage(chatId: String, messageId: String)
    /// A list or settings page the app has a screen for, such as `/settings/tokens`.
    case screen(PortalScreen)

    /// Reads a web address on the account's own server. Nil for another
    /// server, a lookalike host, a path the app has no screen for, or an id
    /// with characters Portal's ids never have. A trailing slash, a query,
    /// a fragment and any page below the one (such as `/controller/<id>/backups`)
    /// are ignored, and percent-encoding is undone, as Portal's own parser does.
    public init?(url: URL, server: ServerAddress) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        guard let host = url.host?.lowercased(), host == (server.url.host ?? "").lowercased() else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let query = components.percentEncodedQuery, let screen = PortalScreen(path: "\(components.percentEncodedPath)?\(query)") {
            self = .screen(screen)
            return
        }
        self.init(segments: Self.segments(ofEncodedPath: components.percentEncodedPath))
    }

    /// Reads a web path such as `/ticket/12`, which is what the server's search results carry. The same rules as for an address.
    public init?(path: String) {
        if let screen = PortalScreen(path: path) {
            self = .screen(screen)
            return
        }
        var text = path
        if let end = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<end]) }
        self.init(segments: Self.segments(ofEncodedPath: text))
    }

    /// Reads the path of a page below an entity, which is what the server's search offers for "controller01 backups". Nil when
    /// the app has no screen for that very page: unlike a link, such a row names one page, so it must not open the entity instead.
    public init?(subpagePath path: String) {
        var text = path
        if let end = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<end]) }
        let segments = Self.segments(ofEncodedPath: text)
        guard segments.count == 3, Self.isIdentifier(segments[1]) else { return nil }
        switch (segments[0].lowercased(), segments[2].lowercased()) {
        case ("controller", "backups"): self = .controllerBackups(id: segments[1])
        case ("virtualcontroller", "snapshots"): self = .virtualControllerSnapshots(id: segments[1])
        case ("surveillance", "playback"): self = .camera(id: segments[1])
        case ("organization", let name):
            guard let page = OrganizationPage(rawValue: name) else { return nil }
            self = .organizationPage(page, organizationId: segments[1])
        default: return nil
        }
    }

    private static func segments(ofEncodedPath path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? "" }
    }

    private init?(segments: [String]) {
        guard let first = segments.first?.lowercased() else { return nil }
        guard segments.count >= 2 else {
            guard let screen = PortalScreen(path: "/" + first) else { return nil }
            self = .screen(screen)
            return
        }
        let identifier = segments[1]
        switch first {
        case "ticket":
            // A ticket page has nothing below it.
            guard segments.count == 2, Self.isDigits(identifier), let sequence = Int64(identifier), sequence > 0 else { return nil }
            self = .ticket(sequence: sequence)
        case "controller":
            guard Self.isIdentifier(identifier) else { return nil }
            self = .controller(id: identifier)
        case "virtualcontroller":
            guard Self.isIdentifier(identifier) else { return nil }
            self = .virtualController(id: identifier)
        case "release":
            guard Self.isIdentifier(identifier) else { return nil }
            self = .release(id: identifier)
        case "site":
            guard Self.isIdentifier(identifier) else { return nil }
            if segments.count == 3, segments[2].lowercased() == "page" {
                self = .sitePages(siteId: identifier)
                return
            }
            if segments.count >= 4, Self.isIdentifier(segments[3]) {
                switch segments[2].lowercased() {
                case "cell":
                    self = .cell(id: segments[3], siteId: identifier)
                    return
                case "page":
                    self = .sitePage(id: segments[3], siteId: identifier)
                    return
                default:
                    break
                }
            }
            self = .site(id: identifier)
        case "surveillance":
            // The camera's playback page opens the camera.
            guard Self.isIdentifier(identifier) else { return nil }
            self = .camera(id: identifier)
        case "organization":
            guard Self.isIdentifier(identifier) else { return nil }
            if segments.count == 2 {
                self = .organization(id: identifier)
            } else if segments.count == 3, let page = OrganizationPage(rawValue: segments[2].lowercased()) {
                self = .organizationPage(page, organizationId: identifier)
            } else {
                return nil
            }
        case "user":
            // The pages below a person (their activity, tickets) have no screen of their own.
            guard segments.count == 2, Self.isIdentifier(identifier) else { return nil }
            self = .user(id: identifier)
        case "agent":
            if segments.count == 2, let screen = PortalScreen(path: "/agent/" + identifier.lowercased()) {
                self = .screen(screen)
            } else if segments.count == 2, Self.isIdentifier(identifier), identifier.lowercased() != "oversight" {
                self = .conversation(id: identifier)
            } else {
                return nil
            }
        case "incident":
            guard segments.count == 2, Self.isIdentifier(identifier) else { return nil }
            self = .incident(id: identifier)
        case "chat":
            guard segments.count == 3, Self.isIdentifier(identifier), Self.isIdentifier(segments[2]) else { return nil }
            self = .chatMessage(chatId: identifier, messageId: segments[2])
        case "settings":
            guard segments.count == 2, let screen = PortalScreen(path: "/settings/" + identifier.lowercased()) else { return nil }
            self = .screen(screen)
        default:
            return nil
        }
    }

    /// The path of the page on the server, which is also what the web app's address bar shows.
    public var path: String {
        switch self {
        case .ticket(let sequence): "/ticket/\(sequence)"
        case .controller(let id): "/controller/\(id)"
        case .controllerBackups(let id): "/controller/\(id)/backups"
        case .virtualController(let id): "/virtualcontroller/\(id)"
        case .virtualControllerSnapshots(let id): "/virtualcontroller/\(id)/snapshots"
        case .release(let id): "/release/\(id)"
        case .site(let id): "/site/\(id)"
        case .cell(let id, let siteId): "/site/\(siteId)/cell/\(id)"
        case .sitePage(let id, let siteId): "/site/\(siteId)/page/\(id)"
        case .sitePages(let siteId): "/site/\(siteId)/page"
        case .camera(let id): "/surveillance/\(id)"
        case .organization(let id): "/organization/\(id)"
        case .organizationPage(let page, let organizationId): "/organization/\(organizationId)/\(page.rawValue)"
        case .user(let id): "/user/\(id)"
        case .conversation(let id): "/agent/\(id)"
        case .incident(let id): "/incident/\(id)"
        case .chatMessage(let chatId, let messageId): "/chat/\(chatId)/\(messageId)"
        case .screen(let screen): screen.path
        }
    }

    /// The address to copy or share: the page on the account's server.
    public func url(server: ServerAddress) -> URL {
        server.endpoint(path)
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    /// Portal's ids are letters, digits, `_` and `-`.
    private static func isIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D }
    }
}

/// OrganizationPage is a page below an organization that the app has a screen for.
public enum OrganizationPage: String, CaseIterable, Hashable, Sendable {
    case members
    case groups
    case roles
    case audit
    case billing
}

/// PortalScreen is a list or settings page of the web app that the app has a screen for. Pages the app has no screen for (the
/// dashboard, help, preferences, email templates) are not here: a link to one opens on the web.
public enum PortalScreen: String, CaseIterable, Hashable, Sendable {
    case controllers = "/controller"
    case virtualControllers = "/virtualcontroller"
    case tickets = "/ticket"
    case sites = "/site"
    case releases = "/release"
    case surveillance = "/surveillance"
    case incidents = "/incident"
    case notificationInbox = "/notification"
    case assistant = "/agent"
    case goals = "/agent/goals"
    case ideas = "/agent/ideas"
    case knowledge = "/agent/knowledge"
    /// A view of the memory page on the web, and a screen of its own in the app.
    case dreams = "/agent/knowledge?view=dreams"
    case automations = "/agent/automations"
    case assistantSettings = "/agent/settings"
    case settings = "/settings"
    case notificationSettings = "/settings/notifications"
    case incidentAlerts = "/settings/incidents"
    case sessions = "/settings/sessions"
    case passkeys = "/settings/passkeys"
    case tokens = "/settings/tokens"
    case authorizedApps = "/settings/authorizedapps"
    case vpn = "/settings/vpn"
    case sshKeys = "/settings/ssh"
    case providers = "/settings/providers"
    case agents = "/settings/agents"
    case registrations = "/settings/registrations"
    case grants = "/settings/grants"
    case plans = "/settings/plans"
    case controllerUsage = "/settings/controllerusage"

    public init?(path: String) {
        // The web app writes `authorizedApps` and `controllerUsage`; the comparison ignores case.
        guard let screen = Self.allCases.first(where: { $0.rawValue == path.lowercased() }) else { return nil }
        self = screen
    }

    /// The path as the web app writes it.
    public var path: String {
        switch self {
        case .authorizedApps: "/settings/authorizedApps"
        case .controllerUsage: "/settings/controllerUsage"
        default: rawValue
        }
    }
}
