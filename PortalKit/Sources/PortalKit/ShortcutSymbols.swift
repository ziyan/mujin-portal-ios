import Foundation

/// ShortcutSymbols names the SF Symbol of each shortcut in the server's catalog. The server's `iconName` is shared by several
/// shortcuts (two bells, three tray icons), so a row is told apart by its id first, and `iconName` is the fallback for a
/// shortcut added to the catalog after this app.
public enum ShortcutSymbols {
    /// One symbol per shortcut id; no two are alike.
    public static let byShortcutId: [String: String] = [
        "page.overview": "house",
        "page.dashboard": "chart.bar",
        "page.materialFlow": "arrow.triangle.branch",
        "page.surveillance": "video",
        "page.incidents": "exclamationmark.shield",
        "page.controllers": "server.rack",
        "page.virtualControllers": "desktopcomputer",
        "page.tickets": "tray.full",
        "page.newTicket": "square.and.pencil",
        "page.sites": "building.2",
        "page.releases": "shippingbox",
        "page.help": "questionmark.circle",
        "page.assistant": "bubble.left.and.bubble.right",
        "assistant.goals": "scope",
        "assistant.ideas": "lightbulb",
        "assistant.knowledge": "brain.head.profile",
        "assistant.automations": "clock.arrow.2.circlepath",
        "assistant.oversight": "eye",
        "assistant.settings": "slider.horizontal.3",
        "account.profile": "person.crop.circle",
        "account.activity": "clock.arrow.circlepath",
        "account.tickets": "tray.and.arrow.down",
        "account.sites": "mappin.and.ellipse",
        "account.virtualControllers": "display",
        "settings.hub": "gearshape",
        "settings.preferences": "switch.2",
        "settings.notifications": "bell.and.waves.left.and.right",
        "page.notificationInbox": "bell",
        "settings.alarms": "bell.badge",
        "settings.incidents": "exclamationmark.bubble",
        "settings.sessions": "iphone",
        "settings.passkeys": "person.badge.key",
        "settings.tokens": "key",
        "settings.authorizedApps": "app.badge.checkmark",
        "settings.vpn": "lock.shield",
        "settings.ssh": "terminal",
        "settings.usage": "chart.bar.xaxis",
        "organization.overview": "building.columns",
        "organization.members": "person.2",
        "organization.groups": "person.2.crop.square.stack",
        "organization.roles": "checkmark.shield",
        "organization.sso": "person.badge.shield.checkmark",
        "organization.domains": "globe",
        "organization.audit": "list.bullet.clipboard",
        "organization.billing": "creditcard",
        "admin.providers": "cpu",
        "admin.agents": "person.crop.square",
        "admin.registrations": "person.badge.plus",
        "admin.grants": "key.horizontal",
        "admin.emailTemplates": "envelope",
        "admin.plans": "tag",
        "admin.oauthClients": "link.badge.plus",
        "admin.controllerUsage": "chart.xyaxis.line",
        "legal.privacy": "hand.raised",
        "legal.terms": "doc.plaintext",
    ]

    public static func symbol(shortcutId: String, iconName: String?, fallback: (String?) -> String) -> String {
        byShortcutId[shortcutId] ?? fallback(iconName)
    }
}
