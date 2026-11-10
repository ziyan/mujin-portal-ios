import Foundation
import Testing

@testable import PortalKit

/// What a search result opens: the screen of the app, or nil when the app has none and the row opens on the web.
@Suite struct SearchLinkTests {
    /// One row of every kind the server sends, with the path it gives that kind.
    static let kinds: [(GlobalSearchResultKind, String, PortalLink?)] = [
        (.shortcut, "/settings/tokens", .screen(.tokens)),
        (.controller, "/controller/controller1", .controller(id: "controller1")),
        (.virtualController, "/virtualcontroller/virtual01", .virtualController(id: "virtual01")),
        (.site, "/site/site01", .site(id: "site01")),
        (.cell, "/site/site01/cell/cell01", .cell(id: "cell01", siteId: "site01")),
        (.camera, "/surveillance/camera01", .camera(id: "camera01")),
        (.organization, "/organization/organization01", .organization(id: "organization01")),
        (.person, "/user/user02", .user(id: "user02")),
        (.directChat, "/agent/chatconv01", .conversation(id: "chatconv01")),
        (.groupChat, "/agent/chatconv02", .conversation(id: "chatconv02")),
        (.conversation, "/agent/conversation01", .conversation(id: "conversation01")),
        (.ticket, "/ticket/12", .ticket(sequence: 12)),
        (.release, "/release/release01", .release(id: "release01")),
        (.page, "/site/site01/page/page01", .sitePage(id: "page01", siteId: "site01")),
        (.incident, "/incident/incident01", .incident(id: "incident01")),
    ]

    /// Every shortcut of the server's catalog, with the path it resolves to for a person with invented ids.
    static let shortcuts: [(String, String, PortalLink?)] = [
        ("page.overview", "/home", nil),
        ("page.dashboard", "/dashboard", nil),
        ("page.materialFlow", "/materialflow", nil),
        ("page.surveillance", "/surveillance", .screen(.surveillance)),
        ("page.incidents", "/incident", .screen(.incidents)),
        ("page.controllers", "/controller", .screen(.controllers)),
        ("page.virtualControllers", "/virtualcontroller", .screen(.virtualControllers)),
        ("page.tickets", "/ticket", .screen(.tickets)),
        ("page.newTicket", "/ticket/new", nil),
        ("page.sites", "/site", .screen(.sites)),
        ("page.releases", "/release", .screen(.releases)),
        ("page.help", "/help", nil),
        ("page.assistant", "/agent", .screen(.assistant)),
        ("assistant.goals", "/agent/goals", .screen(.goals)),
        ("assistant.ideas", "/agent/ideas", .screen(.ideas)),
        ("assistant.knowledge", "/agent/knowledge", .screen(.knowledge)),
        ("assistant.dreams", "/agent/knowledge?view=dreams", .screen(.dreams)),
        ("assistant.automations", "/agent/automations", .screen(.automations)),
        ("assistant.oversight", "/agent/oversight", nil),
        ("assistant.settings", "/agent/settings", .screen(.assistantSettings)),
        ("account.profile", "/user/user01", .user(id: "user01")),
        ("account.activity", "/user/user01/activity", nil),
        ("account.tickets", "/user/user01/tickets", nil),
        ("account.sites", "/user/user01/sites", nil),
        ("account.virtualControllers", "/user/user01/virtualcontrollers", nil),
        ("settings.hub", "/settings", .screen(.settings)),
        ("settings.preferences", "/settings/preferences", nil),
        ("settings.notifications", "/settings/notifications", .screen(.notificationSettings)),
        ("page.notificationInbox", "/notification", .screen(.notificationInbox)),
        ("settings.alarms", "/settings/alarms", nil),
        ("settings.incidents", "/settings/incidents", .screen(.incidentAlerts)),
        ("settings.sessions", "/settings/sessions", .screen(.sessions)),
        ("settings.passkeys", "/settings/passkeys", .screen(.passkeys)),
        ("settings.tokens", "/settings/tokens", .screen(.tokens)),
        ("settings.authorizedApps", "/settings/authorizedApps", .screen(.authorizedApps)),
        ("settings.vpn", "/settings/vpn", .screen(.vpn)),
        ("settings.ssh", "/settings/ssh", .screen(.sshKeys)),
        ("settings.usage", "/settings/usage", nil),
        ("organization.overview", "/organization/organization01", .organization(id: "organization01")),
        ("organization.members", "/organization/organization01/members", .organizationPage(.members, organizationId: "organization01")),
        ("organization.groups", "/organization/organization01/groups", .organizationPage(.groups, organizationId: "organization01")),
        ("organization.roles", "/organization/organization01/roles", .organizationPage(.roles, organizationId: "organization01")),
        ("organization.sso", "/organization/organization01/sso", nil),
        ("organization.domains", "/organization/organization01/domains", nil),
        ("organization.audit", "/organization/organization01/audit", .organizationPage(.audit, organizationId: "organization01")),
        ("organization.billing", "/organization/organization01/billing", .organizationPage(.billing, organizationId: "organization01")),
        ("admin.providers", "/settings/providers", .screen(.providers)),
        ("admin.agents", "/settings/agents", .screen(.agents)),
        ("admin.registrations", "/settings/registrations", .screen(.registrations)),
        ("admin.grants", "/settings/grants", .screen(.grants)),
        ("admin.emailTemplates", "/settings/emailTemplates", nil),
        ("admin.plans", "/settings/plans", .screen(.plans)),
        ("admin.oauthClients", "/settings/oauthClients", nil),
        ("admin.controllerUsage", "/settings/controllerUsage", .screen(.controllerUsage)),
        ("legal.privacy", "/privacy", nil),
        ("legal.terms", "/terms", nil),
    ]

    @Test func everyKindOpensItsScreen() {
        #expect(Self.kinds.count == GlobalSearchResultKind.allCases.count)
        #expect(Set(Self.kinds.map(\.0)) == Set(GlobalSearchResultKind.allCases))
        for (kind, path, expected) in Self.kinds {
            let result = GlobalSearchResult(resultKind: kind, id: "id", title: "Title", path: path)
            #expect(result.link == expected, "\(kind) at \(path)")
            #expect(expected != nil, "\(kind) has a screen except a documentation page")
        }
    }

    @Test func everyShortcutOfTheCatalogIsMapped() {
        #expect(Self.shortcuts.count == 56)
        #expect(Set(Self.shortcuts.map(\.0)).count == Self.shortcuts.count)
        for (identifier, path, expected) in Self.shortcuts {
            let result = GlobalSearchResult(resultKind: .shortcut, id: identifier, title: "Title", path: path, iconName: "settings")
            #expect(result.link == expected, "\(identifier) at \(path)")
        }
    }

    @Test func aDocumentationPageIsReadAsASitePage() {
        #expect(PortalLink(path: "/site/site01/page/page01") == .sitePage(id: "page01", siteId: "site01"))
    }

    @Test func eachScreenKeepsItsPathAndReadsBackAsItself() {
        for screen in PortalScreen.allCases {
            #expect(PortalLink(path: screen.path) == .screen(screen), "\(screen.path)")
            #expect(PortalLink.screen(screen).path == screen.path)
        }
        for page in OrganizationPage.allCases {
            let link = PortalLink.organizationPage(page, organizationId: "organization01")
            #expect(PortalLink(path: link.path) == link)
        }
    }

    @Test func everyLinkReadsBackFromItsAddress() throws {
        let server = try ServerAddress("https://portal.example.test")
        let links: [PortalLink] = Self.kinds.compactMap(\.2) + Self.shortcuts.compactMap(\.2)
        for link in links {
            #expect(PortalLink(url: link.url(server: server), server: server) == link, "\(link.path)")
        }
    }

    @Test func aPathWithAQueryOrFragmentIsReadWithoutThem() {
        #expect(PortalLink(path: "/ticket/12?tab=comments") == .ticket(sequence: 12))
        #expect(PortalLink(path: "/settings/tokens#new") == .screen(.tokens))
    }

    @Test func aCameraPlaybackPageOpensTheCamera() {
        #expect(PortalLink(path: "/surveillance/camera01/playback") == .camera(id: "camera01"))
    }

    @Test func aPageBelowASiteOpensTheSite() {
        #expect(PortalLink(path: "/site/site01/members") == .site(id: "site01"))
        #expect(PortalLink(path: "/site/site01/cell") == .site(id: "site01"))
    }

    @Test func pathsTheAppDoesNotReadAreNil() {
        for path in ["", "/", "/home", "/help", "/ticket/new", "/user/user01/activity", "/organization/organization01/sso", "/agent/oversight", "/settings/nothing", "/settings/tokens/extra", "/user/a%2Fb"] {
            #expect(PortalLink(path: path) == nil, "\(path)")
        }
    }

    @Test func anIncidentAndASearchHitAreFoundByTheirIds() async throws {
        let (connection, transport) = scriptedConnection { operation, variables in
            #expect(operation == "GetIncident")
            #expect(variables["incidentId"] as? String == "incident01")
            return ["GetIncident": ["incident": ["id": "incident01", "title": "Pallet leaning"]]]
        }
        #expect(try await connection.incident(id: "incident01").id == "incident01")
        #expect(transport.requests.count == 1)
    }

    @Test func aMissingIncidentIsAnError() async {
        let (connection, _) = scriptedConnection { _, _ in ["GetIncident": ["incident": NSNull()]] }
        await #expect(throws: PortalError.self) { try await connection.incident(id: "missing") }
    }

    @Test func everyShortcutHasItsOwnSymbol() {
        let identifiers = Self.shortcuts.map(\.0)
        #expect(Set(ShortcutSymbols.byShortcutId.keys) == Set(identifiers))
        let symbols = identifiers.compactMap { ShortcutSymbols.byShortcutId[$0] }
        #expect(Set(symbols).count == identifiers.count, "two shortcuts share a symbol")
        #expect(ShortcutSymbols.byShortcutId["settings.notifications"] != ShortcutSymbols.byShortcutId["page.notificationInbox"])
    }

    @Test func aShortcutAddedLaterFallsBackToItsIconName() {
        #expect(ShortcutSymbols.symbol(shortcutId: "future.page", iconName: "x", fallback: { "fallback.\($0 ?? "")" }) == "fallback.x")
    }
}
