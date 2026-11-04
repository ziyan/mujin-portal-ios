import Foundation
import PortalKit

/// SearchDemo is the demo's global search: invented rows, and the screens the screenshots show (recents and suggestions, a
/// controller id typed, a controller and one of its pages, a word that matches shortcuts, and a word that matches nothing).
enum SearchDemo {
    static let screens: Set<String> = ["search", "search-controller", "search-subpage", "search-shortcuts", "search-no-results"]

    static func owns(_ screen: String?) -> Bool { screen.map { screens.contains($0) || $0.hasPrefix(queryPrefix) } ?? false }

    /// A screen named `search-q:<text>` types <text> into the search field.
    static let queryPrefix = "search-q:"

    /// The text a screen types into the search field.
    static func query(for screen: String?) -> String {
        if let screen, screen.hasPrefix(queryPrefix) { return String(screen.dropFirst(queryPrefix.count)) }
        switch screen {
        case "search-controller": "controller01"
        case "search-subpage": "controller01 backups"
        case "search-shortcuts": "notifications"
        case "search-no-results": "zzqx"
        default: ""
        }
    }

    /// What the field starts with, for the screenshot run.
    static var startingQuery: String { query(for: ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) }

    /// The rows the demo person opened before, newest first.
    static let recents: [GlobalSearchResult] = [
        GlobalSearchResult(resultKind: .ticket, id: "1", title: "Gripper drops boxes at pick station 3", subtitle: "Open", path: "/ticket/1"),
        GlobalSearchResult(resultKind: .site, id: "site01", title: "Example Yard", subtitle: "Example Logistics", path: "/site/site01"),
        GlobalSearchResult(resultKind: .person, id: "user03", title: "Robin Demo", subtitle: "Example Logistics", path: "/user/user03"),
        GlobalSearchResult(resultKind: .shortcut, id: "settings.tokens", title: "API tokens", subtitle: "Security and access", path: "/settings/tokens", iconName: "tokens"),
    ]

    private struct Row {
        let kind: String
        let id: String
        let title: String
        let subtitle: String
        let path: String
        var iconName: String?
        var organizationId: String?
        var organizationName: String?
        /// Words that match the row without being in what it shows.
        var keywords = ""

        var json: [String: Any] {
            func nullable(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }
            return [
                "resultKind": kind, "id": id, "title": title, "subtitle": subtitle, "path": path, "iconName": nullable(iconName),
                "organizationId": nullable(organizationId), "organizationName": nullable(organizationName),
            ]
        }

        func matches(_ text: String) -> Bool {
            [title, subtitle, id, keywords].joined(separator: " ").lowercased().contains(text)
        }
    }

    private static func shortcut(_ id: String, _ title: String, _ section: String, _ path: String, _ icon: String, _ keywords: String = "") -> Row {
        Row(kind: "shortcut", id: id, title: title, subtitle: section, path: path, iconName: icon, keywords: keywords)
    }

    /// The suggestions of an empty field, in the order the server offers them.
    private static let suggestions: [Row] = [
        shortcut("page.dashboard", "Dashboard", "Pages", "/dashboard", "dashboard"),
        shortcut("page.controllers", "Controllers", "Pages", "/controller", "controllers"),
        shortcut("page.tickets", "Tickets", "Pages", "/ticket", "tickets"),
        shortcut("page.incidents", "Incidents", "Pages", "/incident", "incidents"),
        shortcut("page.assistant", "Assistant chats", "Assistant", "/agent", "assistant"),
        shortcut("settings.notifications", "Notification preferences", "Account", "/settings/notifications", "notifications"),
        shortcut("settings.hub", "Settings", "Account", "/settings", "settings"),
        shortcut("page.help", "Help", "Pages", "/help", "help"),
    ]

    /// Everything a typed word can match, best first.
    private static let rows: [Row] = [
        shortcut("page.notificationInbox", "Notification inbox", "Pages", "/notification", "notifications", "notifications bell unread mentions inbox"),
        shortcut("settings.notifications", "Notification preferences", "Account", "/settings/notifications", "notifications", "notifications email push alerts mute digest"),
        shortcut("settings.alarms", "Alarm subscriptions", "Account", "/settings/alarms", "alarms", "alarm notifications alarm alerts controller alarms"),
        shortcut("settings.incidents", "Incident subscriptions", "Account", "/settings/incidents", "incidents", "incident notifications incident alerts"),
        shortcut("settings.tokens", "API tokens", "Security and access", "/settings/tokens", "tokens", "tokens access tokens api keys"),
        shortcut("settings.sessions", "Sessions", "Security and access", "/settings/sessions", "sessions", "devices sign out"),
        Row(kind: "controller", id: "controller01", title: "controller01", subtitle: "Example Yard", path: "/controller/controller01"),
        shortcut("controller.alarms:controller01", "Alarms", "controller01", "/controller/controller01/alarms", "alarms", "controller01 alarms"),
        shortcut("controller.telemetry:controller01", "Telemetry", "controller01", "/controller/controller01/telemetry", "telemetry", "controller01 telemetry"),
        shortcut("controller.backups:controller01", "Backups", "controller01", "/controller/controller01/backups", "backups", "controller01 backups"),
        shortcut("controller.sync:controller01", "Sync", "controller01", "/controller/controller01/sync", "sync", "controller01 sync"),
        Row(kind: "virtualController", id: "virtual01", title: "Training cell", subtitle: "Copy of controller01", path: "/virtualcontroller/virtual01"),
        Row(kind: "site", id: "site01", title: "Example Yard", subtitle: "Example Logistics", path: "/site/site01"),
        Row(kind: "camera", id: "camera01", title: "Dock door 2", subtitle: "Example Yard", path: "/surveillance/camera01"),
        Row(kind: "person", id: "user03", title: "Robin Demo", subtitle: "Example Logistics", path: "/user/user03"),
        Row(kind: "groupChat", id: "chatconv02", title: "Pick station team", subtitle: "3 people", path: "/agent/chatconv02"),
        Row(kind: "conversation", id: "conversation02", title: "Restart the planner on controller01", subtitle: "", path: "/agent/conversation02"),
        Row(
            kind: "ticket", id: "1", title: "Gripper drops boxes at pick station 3", subtitle: "Open, high priority", path: "/ticket/1",
            keywords: "controller01"),
        Row(
            kind: "ticket", id: "4", title: "Planner restarts on controller01 every night", subtitle: "Open", path: "/ticket/4",
            organizationId: "organization02", organizationName: "Example Freight"),
        Row(kind: "release", id: "release01", title: "Release 4.2", subtitle: "Stable", path: "/release/release01"),
        Row(kind: "incident", id: "incident01", title: "Person near the conveyor", subtitle: "controller01, Example Yard", path: "/incident/incident01"),
    ]

    static func respond(operation: String, variables: [String: Any]) -> [String: Any]? {
        guard operation == "GlobalSearch" else { return nil }
        let text = (variables["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let found = text.count < GlobalSearchRules.minimumQueryLength ? suggestions : rows.filter { $0.matches(text) }
        return ["GlobalSearch": ["results": found.map(\.json)]]
    }
}
