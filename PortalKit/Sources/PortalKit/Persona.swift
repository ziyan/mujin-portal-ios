import Foundation

/// Persona is which kind of person is signed in, which decides the app's
/// structure: customers work inside their own organization, Mujin users work
/// across organizations.
public enum Persona: String, Equatable, Sendable {
    case customer
    case staff

    /// The organization says it, when the app could read it. Otherwise the
    /// permissions that only staff hold decide.
    public static func resolve(isMujinOrganization: Bool?, permissions: [String]) -> Persona {
        if let isMujinOrganization { return isMujinOrganization ? .staff : .customer }
        let staffPermissions: Set<String> = ["platform:administer", "monitoring:read", "agent:manage"]
        return permissions.contains { staffPermissions.contains($0) } ? .staff : .customer
    }
}

/// AppSection is one of the app's top-level places.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case monitoring
    case assistant
    case chats
    case tickets
    case site
    case customers
    case more

    public var id: String { rawValue }
}

/// Navigation decides the sections each persona sees, in order. A phone shows
/// five tabs at most; the iPad's sidebar lists the same sections.
public enum Navigation {
    public static func sections(for persona: Persona) -> [AppSection] {
        switch persona {
        case .customer: [.assistant, .site, .tickets, .more]
        case .staff: [.monitoring, .assistant, .tickets, .customers, .more]
        }
    }

    /// The section the app opens on.
    public static func home(for persona: Persona) -> AppSection {
        sections(for: persona)[0]
    }
}

/// Profile is the signed-in person with what decides their navigation.
public struct Profile: Equatable, Sendable {
    public let me: Me
    public let organizationName: String?
    public let isMujinOrganization: Bool?

    public init(me: Me, organizationName: String? = nil, isMujinOrganization: Bool? = nil) {
        self.me = me
        self.organizationName = organizationName
        self.isMujinOrganization = isMujinOrganization
    }

    public var persona: Persona {
        Persona.resolve(isMujinOrganization: isMujinOrganization, permissions: me.permissions ?? [])
    }
}
