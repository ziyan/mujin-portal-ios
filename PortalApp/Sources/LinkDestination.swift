import PortalKit

/// LinkedScreen is a screen a link opens, ready to show.
enum LinkedScreen: Equatable {
    case route(PortalRoute)
    case more(MoreDestination)
}

/// LinkResolution is what the app does with a Portal link: a search result, a tapped link in a chat or a notification.
enum LinkResolution: Equatable {
    /// A screen to show in a sheet, known without asking the server.
    case screen(LinkedScreen)
    /// A screen to show in a sheet once the page it names is looked up, such as a ticket by its number.
    case lookup
    /// A conversation or a chat, opened on the Chat tab.
    case conversation(String)
    /// One message of a chat, opened in the person's own conversation of it.
    case chatMessage(chatId: String, messageId: String)
    /// A tab already on the bar.
    case tab(AppSection)
    /// The notification inbox.
    case notifications
    /// The app has no screen for it, or this person is not offered the one it has: the page opens in the browser, signed in.
    case web

    /// Whether the link is shown in a sheet.
    var isSheet: Bool {
        switch self {
        case .screen, .lookup: true
        case .conversation, .chatMessage, .tab, .notifications, .web: false
        }
    }
}

extension SessionModel {
    /// Decides what a link opens. `organizationId` is the organization of the search result it came from, when that is not the
    /// person's own.
    func resolution(for link: PortalLink, organizationId: String?) -> LinkResolution {
        let organization = organizationId ?? self.organizationId
        switch link {
        case .ticket, .controller, .controllerBackups, .virtualController, .virtualControllerSnapshots, .camera, .incident:
            return .lookup
        case .release(let id):
            return .screen(.route(.release(id: id)))
        case .site(let id):
            // A link does not say whose site it is, and it need not be the person's own organization. The screen reads that from the site.
            return .screen(.route(.site(id: id, organizationId: organizationId)))
        case .cell(let id, let siteId):
            return .screen(.route(.cell(id: id, siteId: siteId, organizationId: organizationId)))
        case .sitePages(let siteId):
            // The pages need no organization: the screens read the site, whoever it belongs to. A server without them opens the web.
            return capabilities.offersSitePages ? .screen(.route(.sitePages(siteId: siteId))) : .web
        case .sitePage(let id, let siteId):
            return capabilities.offersSitePages ? .screen(.route(.sitePage(id: id, siteId: siteId))) : .web
        case .conversation(let id):
            return .conversation(id)
        case .chatMessage(let chatId, let messageId):
            return capabilities.offersMessageLinks ? .chatMessage(chatId: chatId, messageId: messageId) : .web
        case .user(let id):
            if id == userId { return .screen(.more(.account(.profile))) }
            guard let organization, peopleAccess.canSeeMembers(in: organization) else { return .web }
            return .screen(.more(.account(.user(id: id, organizationId: organization))))
        case .organization(let id):
            if platformAccess.hasOrganizationPages(id) { return .screen(.more(.platform(.organization(id: id)))) }
            return peopleAccess.hasPeopleEntry && id == self.organizationId ? .screen(.more(.account(.people(organizationId: id)))) : .web
        case .organizationPage(let page, let id):
            switch page {
            case .members: return peopleAccess.canSeeMembers(in: id) ? .screen(.more(.account(.members(organizationId: id)))) : .web
            case .groups: return peopleAccess.canSeeGroups(in: id) ? .screen(.more(.account(.groups(organizationId: id)))) : .web
            case .roles: return peopleAccess.canOpenRoles(in: id) ? .screen(.more(.account(.roles(organizationId: id)))) : .web
            case .audit: return platformAccess.canReadAudit(of: id) ? .screen(.more(.platform(.auditLog(organizationId: id)))) : .web
            case .billing: return platformAccess.canViewBilling(of: id) ? .screen(.more(.platform(.billing(organizationId: id)))) : .web
            }
        case .screen(let screen):
            return resolution(for: screen)
        }
    }

    private func resolution(for screen: PortalScreen) -> LinkResolution {
        /// A screen that is a tab for people who put it on the bar, and a screen of More for the rest.
        func tabOrScreen(_ section: AppSection, _ destination: MoreDestination) -> LinkResolution {
            tabSections.contains(section) ? .tab(section) : .screen(.more(destination))
        }
        func moreScreen(_ destination: MoreDestination, if isOffered: Bool = true) -> LinkResolution {
            isOffered ? .screen(.more(destination)) : .web
        }
        switch screen {
        case .assistant: return .tab(.assistant)
        case .notificationInbox: return .notifications
        case .tickets: return tabOrScreen(.tickets, .tickets)
        case .sites: return tabOrScreen(.site, .sites)
        case .surveillance: return tabOrScreen(.surveillance, .surveillance)
        case .releases: return tabOrScreen(.releases, .releases)
        case .goals: return tabOrScreen(.goals, .goals)
        case .ideas: return tabOrScreen(.ideas, .ideas)
        case .knowledge: return tabOrScreen(.knowledge, .knowledge)
        case .dreams: return moreScreen(.dreams)
        case .automations: return tabOrScreen(.automations, .automations)
        case .incidents: return isStaff ? tabOrScreen(.incidents, .incidents) : .web
        case .settings: return tabOrScreen(.settings, .settings)
        case .controllers: return .screen(.route(.allControllers))
        case .virtualControllers: return .screen(.route(.allVirtualControllers))
        case .assistantSettings: return moreScreen(.assistantSettings)
        case .notificationSettings: return moreScreen(.notificationSettings)
        case .sessions: return moreScreen(.account(.sessions))
        case .passkeys: return moreScreen(.account(.passkeys))
        case .tokens: return moreScreen(.account(.tokens))
        case .authorizedApps: return moreScreen(.account(.authorizedApps))
        case .vpn: return moreScreen(.account(.vpn))
        case .sshKeys: return moreScreen(.account(.sshKeys))
        case .incidentAlerts: return moreScreen(.platform(.incidentAlerts), if: platformAccess.canSeeIncidentAlerts)
        case .providers: return moreScreen(.platform(.providers), if: platformAccess.canManageProviders)
        case .agents: return moreScreen(.platform(.agents), if: platformAccess.canManageAgents)
        case .registrations: return moreScreen(.platform(.registrations), if: platformAccess.canDecideRegistrations)
        case .grants: return moreScreen(.platform(.grants), if: platformAccess.canManageGrants)
        case .plans: return moreScreen(.platform(.plans), if: platformAccess.canSeePlans)
        case .controllerUsage: return moreScreen(.platform(.controllerUsage), if: platformAccess.canReadUsage)
        }
    }
}
