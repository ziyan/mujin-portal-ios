import PortalKit
import SwiftUI

/// OrganizationPickerView is where a Mujin user chooses the organization whose people to manage.
struct OrganizationPickerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var phase = LoadPhase.loading
    @State private var organizations: [OrganizationSummary] = []
    @State private var query = ""

    private var shown: [OrganizationSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? organizations : organizations.filter { ($0.name ?? "").localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load organizations", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                List {
                    PortalRows {
                        ForEach(shown) { organization in
                            NavigationLink {
                                PeopleHubView(organizationId: organization.id)
                            } label: {
                                Label(organization.name ?? organization.id, systemImage: "building.2")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .portalList()
                .overlay {
                    if shown.isEmpty {
                        if query.isEmpty {
                            ContentUnavailableView("No organizations", systemImage: "building.2")
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search organizations")
        .task { await load() }
    }

    private func load() async {
        do {
            organizations = try await appModel.connection(for: session.account).organizations()
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// PeopleHubView is the people of one organization: its members, groups and roles, as far as the viewer may open them.
struct PeopleHubView: View {
    @Environment(SessionModel.self) private var session
    let organizationId: String

    var body: some View {
        let access = session.peopleAccess
        List {
            PortalRows {
                Section {
                    if access.canSeeMembers(in: organizationId) {
                        NavigationLink {
                            MembersView(organizationId: organizationId)
                        } label: {
                            Label("Members", systemImage: "person.2")
                                .foregroundStyle(.primary)
                        }
                    }
                    if access.canSeeGroups(in: organizationId) {
                        NavigationLink {
                            GroupsView(organizationId: organizationId)
                        } label: {
                            Label("Groups", systemImage: "person.3")
                                .foregroundStyle(.primary)
                        }
                    }
                    if access.canOpenRoles(in: organizationId) {
                        NavigationLink {
                            RolesView(organizationId: organizationId)
                        } label: {
                            Label("Roles", systemImage: "checkmark.shield")
                                .foregroundStyle(.primary)
                        }
                    }
                } footer: {
                    Text("A group gives its members the roles it holds at the sites it covers.")
                }
            }
        }
        .portalList()
        .navigationTitle(session.organizationName(for: organizationId) ?? String(localized: "People"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// MemberRow is one person in a list: their picture, name and address.
struct MemberRow: View {
    let member: OrganizationMember

    var body: some View {
        HStack(spacing: 12) {
            UserAvatar(userId: member.id, name: member.shownName, hasAvatar: member.hasAvatar, modifiedAt: member.modifiedAt, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.shownName)
                    .foregroundStyle(Color.primary)
                if let email = member.email, !email.isEmpty, email != member.shownName {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                if member.isDeactivated {
                    Label("Deactivated", systemImage: "person.slash")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}

/// MembersView lists the people of an organization, with a search.
struct MembersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String

    @State private var phase = LoadPhase.loading
    @State private var members: [OrganizationMember] = []
    @State private var query = ""
    @State private var includesDeactivated = false

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load members", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search members")
        .toolbar {
            if MemberDirectory.deactivatedCount(members) > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Show deactivated people", isOn: $includesDeactivated)
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease")
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: appModel.presentedWeb == nil) { _, isClosed in
            if isClosed { Task { await load() } }
        }
    }

    private var list: some View {
        let shown = MemberDirectory.filter(members, query: query, includesDeactivated: includesDeactivated)
        return List {
            PortalRows {
                Section {
                    ForEach(shown) { member in
                        NavigationLink {
                            UserDetailView(userId: member.id, organizationId: organizationId)
                        } label: {
                            MemberRow(member: member)
                        }
                    }
                } footer: {
                    if !shown.isEmpty { Text("^[\(shown.count) person](inflect: true)") }
                }
                if session.peopleAccess.canManageUsers(in: organizationId) {
                    OnTheWebRow(
                        title: "Add a person on the web", explanation: "People are added in Portal on the web, where their email address is checked. Come back to see them listed.",
                        path: "/organization/\(organizationId)/members")
                }
            }
        }
        .portalList()
        .overlay {
            if shown.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No members", systemImage: "person.2")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            members = try await appModel.connection(for: session.account).organizationMembers(organizationId: organizationId)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// UserDetailView is one person: their details, the sites and roles they hold, their groups and their recent tickets.
struct UserDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let userId: String
    let organizationId: String

    @State private var phase = LoadPhase.loading
    @State private var profile: UserProfile?
    @State private var siteRoles: [UserSiteRoles] = []
    @State private var siteOrganizations: [String: String] = [:]
    @State private var groups: [AccessGroup] = []
    @State private var tickets: [Ticket] = []
    @State private var isConfirmingDeactivation = false
    @State private var actions = ActionState()

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this person", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if let profile { details(profile) }
            }
        }
        .navigationTitle(profile?.shownName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .failureAlert(actions)
    }

    private func details(_ profile: UserProfile) -> some View {
        let access = session.peopleAccess
        let canDeactivate = access.canDeactivateUsers(in: profile.organizationId ?? organizationId) && profile.id != session.userId
        return List {
            PortalRows {
                Section {
                    HStack(spacing: 16) {
                        UserAvatar(userId: profile.id, name: profile.shownName, hasAvatar: profile.hasAvatar, modifiedAt: profile.modifiedAt, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.shownName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            if let email = profile.email, !email.isEmpty {
                                Text(email)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                            if profile.isDeactivated {
                                Label("Deactivated", systemImage: "person.slash")
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                Section("Details") {
                    if let jobRole = profile.jobRole, !jobRole.isEmpty { LabeledContent("Job title") { Text(jobRole).foregroundStyle(Color.secondary) } }
                    if let organization = session.organizationName(for: profile.organizationId ?? organizationId) {
                        LabeledContent("Organization") { Text(organization).foregroundStyle(Color.secondary) }
                    }
                    LabeledContent("Last signed in") {
                        Text(AccountText.relative(profile.loggedInAt) ?? String(localized: "Never")).foregroundStyle(Color.secondary)
                    }
                    if let joined = AccountText.day(profile.createdAt) { LabeledContent("Joined") { Text(joined).foregroundStyle(Color.secondary) } }
                }
                Section {
                    if siteRoles.isEmpty {
                        Text("Not a member of any site.")
                            .foregroundStyle(Color.secondary)
                    }
                    ForEach(siteRoles) { entry in
                        NavigationLink {
                            SiteView(organizationId: siteOrganizations[entry.siteId], siteId: entry.siteId, embedsNavigation: false)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.siteName)
                                    .foregroundStyle(Color.primary)
                                Text(entry.roleNames.isEmpty ? String(localized: "No role listed") : entry.roleNames.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Sites and roles")
                } footer: {
                    Text("Roles come from the groups this person is in.")
                }
                if !groups.isEmpty {
                    Section("Groups") {
                        ForEach(groups) { group in
                            NavigationLink {
                                GroupDetailView(groupId: group.id, organizationId: group.organizationId ?? organizationId)
                            } label: {
                                Text(group.shownName)
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                }
                if !tickets.isEmpty {
                    Section("Recent tickets") {
                        ForEach(tickets) { ticket in
                            NavigationLink {
                                TicketDetailView(ticketId: ticket.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ticket.title ?? "")
                                        .foregroundStyle(Color.primary)
                                    Text(Self.ticketLine(ticket))
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                }
                if canDeactivate {
                    Section {
                        if profile.isDeactivated {
                            Button {
                                Task { await setActive(true) }
                            } label: {
                                Text("Reactivate")
                                    .foregroundStyle(Color.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(role: .destructive) {
                                isConfirmingDeactivation = true
                            } label: {
                                Text("Deactivate")
                                    .foregroundStyle(Color.statusError)
                            }
                            .confirmationDialog("Deactivate \(profile.shownName)?", isPresented: $isConfirmingDeactivation, titleVisibility: .visible) {
                                Button("Deactivate", role: .destructive) { Task { await setActive(false) } }
                            } message: {
                                Text("They can no longer sign in. You can reactivate them later.")
                            }
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private static func ticketLine(_ ticket: Ticket) -> String {
        var parts: [String] = []
        if let sequence = ticket.sequence { parts.append("#\(sequence)") }
        if let status = ticket.status, !status.isEmpty { parts.append(status.capitalized) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        let access = session.peopleAccess
        let identifier = userId
        do {
            let loaded = try await connection.userProfile(id: identifier)
            profile = loaded
            async let sites = try? connection.userSites(userId: identifier)
            async let assignments = try? connection.siteRoleAssignments(userId: identifier)
            async let roles = try? connection.roles()
            let loadedSites = await sites ?? []
            let roleNames = Dictionary((await roles ?? []).map { ($0.id, $0.shownName) }, uniquingKeysWith: { first, _ in first })
            siteRoles = UserSites.roles(sites: loadedSites, assignments: await assignments ?? [], roleNames: roleNames)
            siteOrganizations = Dictionary(loadedSites.compactMap { site in site.organizationId.map { (site.id, $0) } }, uniquingKeysWith: { first, _ in first })
            phase = .loaded
            if access.canSeeGroups(in: loaded.organizationId ?? organizationId) {
                groups = (try? await connection.userGroups(userId: identifier)) ?? []
            }
            let candidates = (try? await connection.tickets(organizationId: loaded.organizationId ?? organizationId)) ?? []
            tickets = Array(candidates.filter { $0.authorUserId == identifier || $0.requesterUserId == identifier }.prefix(5))
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) } else { actions.errorMessage = error.userMessage }
        }
    }

    private func setActive(_ isActive: Bool) async {
        let connection = appModel.connection(for: session.account)
        let identifier = userId
        if await actions.run(appModel: appModel, session: session, { try await connection.setUserActive(id: identifier, isActive: isActive) }) {
            await load()
        }
    }
}
