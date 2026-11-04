import Foundation

/// TabBar decides which sections are on the tab bar. A phone shows five tabs at most. More and Search are always there, Search
/// set apart at the trailing end, so a person chooses up to three, Chat included. The iPad's sidebar lists the same sections, so
/// one choice serves both.
public enum TabBar {
    /// How many sections the bar holds besides More and Search, Chat included.
    public static let capacity = 3

    /// Chat is always the first tab: conversations, chats and the assistant's questions open there, and it is the screen the
    /// app starts on. The person chooses the rest.
    public static let pinned = AppSection.assistant

    /// The sections a person may put on the bar besides Chat, in the order the editor lists them. A person without cameras is
    /// not offered Surveillance, and only Mujin staff are offered Incidents.
    public static func choosable(persona: Persona, hasCameras: Bool) -> [AppSection] {
        var sections: [AppSection] = persona == .staff ? [.tickets, .site] : [.site, .tickets]
        if hasCameras { sections.append(.surveillance) }
        sections += [.releases, .goals, .ideas, .knowledge, .automations]
        if persona == .staff { sections.append(.incidents) }
        sections.append(.settings)
        return sections
    }

    /// The bar before anyone edits it: Chat, Sites and Tickets (Tickets and Sites swapped for Mujin staff). Surveillance is one
    /// tap away under More and in search, and a person who wants it on the bar chooses it.
    public static func defaults(persona: Persona, hasCameras: Bool) -> [AppSection] {
        Array(Navigation.sections(for: persona).filter { $0 != .more }.prefix(capacity))
    }

    /// The sections on the bar, More and Search left out, from what the person saved. Nothing saved gives the defaults. A saved
    /// section that is no longer allowed is dropped without a word, and the defaults fill the slots it leaves empty. A choice made
    /// when the bar held one more section than it does now loses its last one, except Surveillance, which the default bar used to
    /// hold and now leaves out: a person who chose it keeps it, in the last slot.
    public static func resolve(saved: [String]?, persona: Persona, hasCameras: Bool) -> [AppSection] {
        let defaults = defaults(persona: persona, hasCameras: hasCameras)
        guard let saved else { return defaults }
        let allowed = choosable(persona: persona, hasCameras: hasCameras)
        let slots = capacity - 1
        let requested = saved.filter { $0 != pinned.rawValue }
        var kept: [AppSection] = []
        for name in requested {
            guard let section = AppSection(rawValue: name), allowed.contains(section), !kept.contains(section), kept.count < slots else { continue }
            kept.append(section)
        }
        if kept.count == slots, !kept.contains(.surveillance), requested.contains(AppSection.surveillance.rawValue), allowed.contains(.surveillance) {
            kept[slots - 1] = .surveillance
        }
        var emptySlots = min(requested.count, slots) - kept.count
        for section in defaults where emptySlots > 0 && section != pinned && !kept.contains(section) {
            kept.append(section)
            emptySlots -= 1
        }
        return [pinned] + kept
    }

    /// Every tab to show: the chosen sections, then More, then Search.
    public static func tabs(saved: [String]?, persona: Persona, hasCameras: Bool) -> [AppSection] {
        resolve(saved: saved, persona: persona, hasCameras: hasCameras) + [.more, .search]
    }
}

/// TabBarStore remembers the tab bar each account chose, per account and server, across launches.
public struct TabBarStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(accountKey: String) -> String { "tabBar|\(accountKey)" }

    /// The saved section names, or nil when the person never chose.
    public func load(accountKey: String) -> [String]? {
        defaults.stringArray(forKey: key(accountKey: accountKey))
    }

    /// Saves the choice. Nil forgets it, which brings the defaults back.
    public func save(_ names: [String]?, accountKey: String) {
        if let names { defaults.set(names, forKey: key(accountKey: accountKey)) } else { defaults.removeObject(forKey: key(accountKey: accountKey)) }
    }
}
