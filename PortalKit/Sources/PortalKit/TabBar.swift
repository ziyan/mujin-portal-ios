import Foundation

/// TabBar decides which sections are on the tab bar. A phone shows five tabs at most, and More is always the last, so a person
/// chooses up to four. The iPad's sidebar lists the same sections, so one choice serves both.
public enum TabBar {
    /// How many sections the bar holds besides More, Chat included.
    public static let capacity = 4

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

    /// The bar before anyone edits it: Chat, Sites, Surveillance and Tickets. Surveillance is left out without cameras.
    public static func defaults(persona: Persona, hasCameras: Bool) -> [AppSection] {
        var sections = Navigation.sections(for: persona).filter { $0 != .more }
        if hasCameras, let index = sections.firstIndex(of: .site) { sections.insert(.surveillance, at: index + 1) }
        return Array(sections.prefix(capacity))
    }

    /// The sections on the bar, More left out, from what the person saved. Nothing saved gives the defaults. A saved section that
    /// is no longer allowed is dropped without a word, and the defaults fill the slots it leaves empty.
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
        var emptySlots = min(requested.count, slots) - kept.count
        for section in defaults where emptySlots > 0 && section != pinned && !kept.contains(section) {
            kept.append(section)
            emptySlots -= 1
        }
        return [pinned] + kept
    }

    /// Every tab to show: the chosen sections, then More.
    public static func tabs(saved: [String]?, persona: Persona, hasCameras: Bool) -> [AppSection] {
        resolve(saved: saved, persona: persona, hasCameras: hasCameras) + [.more]
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
