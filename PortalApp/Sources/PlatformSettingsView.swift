import PortalKit
import SwiftUI

/// PlatformDestination is a screen of Platform settings. More pushes it as a value; the screens push the next one with a link that
/// names its destination, so they work on any stack.
enum PlatformDestination: Hashable {
    case hub
    case organizations
    case organization(id: String)
    /// The audit log of one organization, or of every organization when nil.
    case auditLog(organizationId: String?)
    case auditEvent(AuditEvent)
    case usage
    case controllerUsage
    case billing(organizationId: String)
    case transactions(organizationId: String)
    case plans
    case plan(Plan)
    case providers
    case provider(id: String)
    case agents
    case agent(id: String)
    case grants
    case organizationGrants(organizationId: String)
    case registrations
    case incidentAlerts
}

/// PlatformDestinationView builds the screen a PlatformDestination names.
struct PlatformDestinationView: View {
    let destination: PlatformDestination

    var body: some View {
        switch destination {
        case .hub: PlatformSettingsHub()
        case .organizations: PlatformOrganizationsView()
        case .organization(let id): OrganizationSettingsView(organizationId: id)
        case .auditLog(let organizationId): AuditLogView(organizationId: organizationId)
        case .auditEvent(let event): AuditEventView(event: event)
        case .usage: ProviderUsageView()
        case .controllerUsage: ControllerUsageView()
        case .billing(let organizationId): BillingView(organizationId: organizationId)
        case .transactions(let organizationId): BillingTransactionsView(organizationId: organizationId)
        case .plans: PlansView()
        case .plan(let plan): PlanView(plan: plan)
        case .providers: ProvidersView()
        case .provider(let id): ProviderView(providerId: id)
        case .agents: AgentsView()
        case .agent(let id): AgentView(agentId: id)
        case .grants: GrantsOrganizationsView()
        case .organizationGrants(let organizationId): OrganizationGrantsView(organizationId: organizationId)
        case .registrations: RegistrationsView()
        case .incidentAlerts: IncidentAlertsView()
        }
    }
}

extension SessionModel {
    /// Which platform settings the viewer is offered, from what the server says they hold.
    var platformAccess: PlatformAccess { PlatformAccess(people: peopleAccess) }
}

/// PlatformMoreSection is the row in More that opens Platform settings, for those who have something in it.
struct PlatformMoreSection: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        if session.platformAccess.hasEntry {
            Section {
                NavigationLink(value: MoreDestination.platform(.hub)) {
                    Label("Platform settings", systemImage: "gearshape.2")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("platformSettingsRow")
                .id("platformSettingsRow")
            }
        }
    }
}

/// localizedWords looks up English words that PortalKit wrote, such as "Waiting", in the string catalog. What the catalog lacks stays English.
func localizedWords(_ english: String) -> String {
    String(localized: String.LocalizationValue(english))
}

/// PageReload reads a screen's data again; screens call it after a change.
struct PageReload {
    let run: @MainActor () async -> Void

    func callAsFunction() async { await run() }
}

/// PlatformPage loads one thing for a screen and draws it when it arrives, with the same waiting and failure states every screen of
/// Platform settings has.
struct PlatformPage<Value: Sendable, Content: View>: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let title: LocalizedStringKey
    let failureTitle: LocalizedStringKey
    let load: @Sendable (Connection) async throws -> Value
    let content: (Value, PageReload) -> Content

    @State private var phase = LoadPhase.loading
    @State private var value: Value?

    init(
        title: LocalizedStringKey, failureTitle: LocalizedStringKey, load: @escaping @Sendable (Connection) async throws -> Value,
        @ViewBuilder content: @escaping (Value, PageReload) -> Content
    ) {
        self.title = title
        self.failureTitle = failureTitle
        self.load = load
        self.content = content
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label(failureTitle, systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await reload() } }
                }
            case .loaded:
                if let value { content(value, PageReload { await reload() }) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        do {
            value = try await load(appModel.connection(for: session.account))
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// PlatformLink is a row that opens another screen of Platform settings.
struct PlatformLink: View {
    let destination: PlatformDestination
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        NavigationLink(value: MoreDestination.platform(destination)) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.primary)
        }
    }
}

/// PlatformWebRow is a row for what the app is not allowed to do: it opens the matching page of Portal on the web.
struct PlatformWebRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let title: LocalizedStringKey
    let path: String

    var body: some View {
        Button {
            WebPage(appModel: appModel, session: session).open(path)
        } label: {
            HStack {
                Label(title, systemImage: "safari")
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// PlatformTextSheet asks for one line of text, to name or to change something.
struct PlatformTextSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    let initialText: String
    var isSecret = false
    var explanation: LocalizedStringKey?
    let onSubmit: (String) async throws -> Void

    @State private var text = ""
    @State private var actions = ActionState()

    private var wanted: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section {
                        if isSecret {
                            SecureField(prompt, text: $text)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                        } else {
                            TextField(prompt, text: $text)
                        }
                    } footer: {
                        if let explanation { Text(explanation) }
                    }
                }
            }
            .portalList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await submit() } }
                        .disabled(wanted.isEmpty || wanted == initialText || actions.isWorking)
                }
            }
            .onAppear { text = initialText }
            .failureAlert(actions)
        }
    }

    private func submit() async {
        let value = wanted
        let submit = onSubmit
        if await actions.run(appModel: appModel, session: session, { try await submit(value) }) { dismiss() }
    }
}

/// PlatformSettingsHub is where Platform settings starts: for a Mujin user the organizations and the pages of the whole platform, for
/// anyone else their own organization.
struct PlatformSettingsHub: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        if session.isStaff {
            staffList
        } else if let organizationId = session.organizationId {
            OrganizationSettingsView(organizationId: organizationId, isHub: true)
        } else {
            ContentUnavailableView("Nothing to set", systemImage: "gearshape.2")
        }
    }

    private var staffList: some View {
        let access = session.platformAccess
        return List {
            PortalRows {
                if access.isPlatformAdministrator {
                    Section {
                        PlatformLink(destination: .organizations, title: "Organizations", symbol: "building.2")
                    } footer: {
                        Text("The profile, audit log and billing of each organization.")
                    }
                } else if let organizationId = session.organizationId, access.hasOrganizationPages(organizationId) {
                    Section {
                        PlatformLink(destination: .organization(id: organizationId), title: "Your organization", symbol: "building.2")
                    }
                }
                if access.hasPlatformPages {
                    Section("Platform") {
                        if access.canReadPlatformAudit { PlatformLink(destination: .auditLog(organizationId: nil), title: "Audit log", symbol: "list.bullet.clipboard") }
                        if access.canReadUsage {
                            PlatformLink(destination: .usage, title: "AI usage", symbol: "chart.bar")
                            PlatformLink(destination: .controllerUsage, title: "Controller usage", symbol: "server.rack")
                        }
                        if access.canSeePlans { PlatformLink(destination: .plans, title: "Plans", symbol: "tag") }
                        if access.canManageProviders { PlatformLink(destination: .providers, title: "AI providers", symbol: "cpu") }
                        if access.canManageAgents { PlatformLink(destination: .agents, title: "AI agents", symbol: "person.crop.square") }
                        if access.canManageGrants { PlatformLink(destination: .grants, title: "AI access by organization", symbol: "key.horizontal") }
                        if access.canDecideRegistrations { PlatformLink(destination: .registrations, title: "Registrations", symbol: "person.badge.plus") }
                    }
                }
                if access.isPlatformAdministrator {
                    Section {
                        PlatformWebRow(title: "Email templates", path: "/settings/emailTemplates")
                        PlatformWebRow(title: "OAuth clients", path: "/settings/oauthClients")
                    } header: {
                        Text("On the web")
                    } footer: {
                        Text("The app is not allowed to change these. They open in Portal on the web, signed in as you.")
                    }
                }
                if access.canSeeIncidentAlerts {
                    Section {
                        PlatformLink(destination: .incidentAlerts, title: "Incident alerts", symbol: "bell.badge")
                    }
                }
            }
        }
        .portalList()
        .navigationTitle("Platform settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// PlatformOrganizationsView is where a platform administrator chooses an organization to look after, the switched-off ones too.
struct PlatformOrganizationsView: View {
    @State private var query = ""

    var body: some View {
        PlatformPage(
            title: "Organizations", failureTitle: "Could not load organizations",
            load: { try await $0.allOrganizations() }
        ) { organizations, reload in
            OrganizationsList(organizations: organizations, query: query, reload: reload)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search organizations")
    }
}

private struct OrganizationsList: View {
    let organizations: [OrganizationSummary]
    let query: String
    let reload: PageReload

    private var shown: [OrganizationSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? organizations : organizations.filter { ($0.name ?? "").localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        List {
            PortalRows {
                ForEach(shown) { organization in
                    NavigationLink(value: MoreDestination.platform(.organization(id: organization.id))) {
                        HStack(spacing: 12) {
                            OrganizationAvatar(organizationId: organization.id, hasLogo: organization.hasLogo, modifiedAt: organization.modifiedAt, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(organization.name ?? organization.id)
                                    .foregroundStyle(Color.primary)
                                if organization.isActive == false {
                                    Text("Switched off")
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
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
        .refreshable { await reload() }
    }
}

/// OrganizationSettingsView is one organization: its name, whether it is switched on, and the pages that belong to it.
struct OrganizationSettingsView: View {
    let organizationId: String
    var isHub = false

    var body: some View {
        PlatformPage(
            title: isHub ? "Platform settings" : "Organization", failureTitle: "Could not load this organization",
            load: { [organizationId] connection in OrganizationSnapshot(profile: try await connection.organizationProfile(id: organizationId)) }
        ) { snapshot, reload in
            OrganizationSettingsList(organizationId: organizationId, profile: snapshot.profile, isHub: isHub, reload: reload)
        }
    }
}

struct OrganizationSnapshot: Sendable {
    let profile: OrganizationSummary?
}

private struct OrganizationSettingsList: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String
    let profile: OrganizationSummary?
    let isHub: Bool
    let reload: PageReload

    @State private var isRenaming = false
    @State private var isConfirmingSwitch = false
    @State private var actions = ActionState()

    var body: some View {
        let access = session.platformAccess
        let name = profile?.name ?? session.organizationName(for: organizationId) ?? organizationId
        List {
            PortalRows {
                Section {
                    HStack(spacing: 12) {
                        OrganizationAvatar(organizationId: organizationId, hasLogo: profile?.hasLogo, modifiedAt: profile?.modifiedAt, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Text(profile?.isActive == false ? String(localized: "Switched off") : String(localized: "Active"))
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if access.canEditOrganization(organizationId) {
                        Button {
                            isRenaming = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    if session.peopleAccess.hasPeopleScreens(in: organizationId) {
                        NavigationLink(value: MoreDestination.account(.people(organizationId: organizationId))) {
                            Label("People", systemImage: "person.2")
                                .foregroundStyle(.primary)
                        }
                    }
                    if access.canReadAudit(of: organizationId) {
                        PlatformLink(destination: .auditLog(organizationId: organizationId), title: "Audit log", symbol: "list.bullet.clipboard")
                    }
                    if access.canViewBilling(of: organizationId) {
                        PlatformLink(destination: .billing(organizationId: organizationId), title: "Billing", symbol: "creditcard")
                    }
                    if session.isStaff, access.canManageGrants {
                        PlatformLink(destination: .organizationGrants(organizationId: organizationId), title: "AI access", symbol: "key.horizontal")
                    }
                }
                if access.canEditOrganization(organizationId) {
                    Section {
                        PlatformWebRow(title: "Email domains", path: "/organization/\(organizationId)/domains")
                        PlatformWebRow(title: "Single sign-on", path: "/organization/\(organizationId)/sso")
                    } header: {
                        Text("On the web")
                    } footer: {
                        Text("The app is not allowed to change how people sign in. These open in Portal on the web, signed in as you.")
                    }
                }
                if isHub, access.canSeeIncidentAlerts {
                    Section {
                        PlatformLink(destination: .incidentAlerts, title: "Incident alerts", symbol: "bell.badge")
                    }
                }
                if access.canSetOrganizationActive, organizationId != session.organizationId, let profile {
                    Section {
                        Button(role: profile.isActive == false ? nil : .destructive) {
                            isConfirmingSwitch = true
                        } label: {
                            Text(profile.isActive == false ? String(localized: "Switch on this organization") : String(localized: "Switch off this organization"))
                                .foregroundStyle(profile.isActive == false ? Color.primary : Color.statusError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog(switchTitle(isOff: profile.isActive == false), isPresented: $isConfirmingSwitch, titleVisibility: .visible) {
                            Button(switchActionTitle(isOff: profile.isActive == false), role: profile.isActive == false ? nil : .destructive) {
                                Task { await switchActive(isActive: profile.isActive == false) }
                            }
                        } message: {
                            Text(switchMessage(isOff: profile.isActive == false, name: name))
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await reload() }
        .sheet(isPresented: $isRenaming) {
            PlatformTextSheet(title: "Rename organization", prompt: "Name", initialText: profile?.name ?? "") { newName in
                try await appModel.connection(for: session.account).renameOrganization(id: organizationId, name: newName)
                await session.loadPlaces()
                await reload()
            }
        }
        .failureAlert(actions)
    }

    private func switchTitle(isOff: Bool) -> LocalizedStringKey {
        isOff ? "Switch on this organization?" : "Switch off this organization?"
    }

    private func switchActionTitle(isOff: Bool) -> LocalizedStringKey {
        isOff ? "Switch on" : "Switch off"
    }

    private func switchMessage(isOff: Bool, name: String) -> String {
        isOff
            ? String(localized: "People of \(name) will be able to sign in again.")
            : String(localized: "People of \(name) will not be able to sign in until it is switched on again.")
    }

    private func switchActive(isActive: Bool) async {
        let connection = appModel.connection(for: session.account)
        let identifier = organizationId
        if await actions.run(appModel: appModel, session: session, { try await connection.setOrganizationActive(id: identifier, isActive: isActive) }) {
            await reload()
        }
    }
}
