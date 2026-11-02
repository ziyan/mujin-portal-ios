import Observation
import PortalKit
import SwiftUI

/// AccountDestination is a screen for the person's own account or for the people of an organization. More pushes it as a value; the
/// screens themselves push the next one with a link that names its destination, so they work on any stack.
enum AccountDestination: Hashable {
    case profile
    case sessions
    case passkeys
    case tokens
    case authorizedApps
    case vpn
    case sshKeys
    case organizations
    case people(organizationId: String)
    case members(organizationId: String)
    case user(id: String, organizationId: String)
    case groups(organizationId: String)
    case group(id: String, organizationId: String)
    case roles(organizationId: String)
    case role(id: String, organizationId: String)
}

/// AccountDestinationView builds the screen an AccountDestination names.
struct AccountDestinationView: View {
    let destination: AccountDestination

    var body: some View {
        switch destination {
        case .profile: ProfileSettingsView()
        case .sessions: ManagedListView(spec: .sessions)
        case .passkeys: ManagedListView(spec: .passkeys)
        case .tokens: ManagedListView(spec: .tokens)
        case .authorizedApps: ManagedListView(spec: .authorizedApps)
        case .vpn: ManagedListView(spec: .vpn)
        case .sshKeys: ManagedListView(spec: .sshKeys)
        case .organizations: OrganizationPickerView()
        case .people(let organizationId): PeopleHubView(organizationId: organizationId)
        case .members(let organizationId): MembersView(organizationId: organizationId)
        case .user(let id, let organizationId): UserDetailView(userId: id, organizationId: organizationId)
        case .groups(let organizationId): GroupsView(organizationId: organizationId)
        case .group(let id, let organizationId): GroupDetailView(groupId: id, organizationId: organizationId)
        case .roles(let organizationId): RolesView(organizationId: organizationId)
        case .role(let id, let organizationId): RoleDetailView(roleId: id, organizationId: organizationId)
        }
    }
}

extension SessionModel {
    /// What the viewer may see and do among people, from what the server says they hold.
    var peopleAccess: PeopleAccess {
        PeopleAccess(permissions: profile?.me.permissions ?? [], isMujinUser: isStaff, viewerOrganizationId: organizationId)
    }

    /// The name of an organization, when it is known.
    func organizationName(for organizationId: String) -> String? {
        let name = organizationNames[organizationId] ?? (organizationId == self.organizationId ? profile?.organizationName : nil)
        return (name ?? "").isEmpty ? nil : name
    }
}

/// AccountSettingsSection is what Settings lists for the person's own account.
struct AccountSettingsSection: View {
    var body: some View {
        Section("Account") {
            accountLink(.profile, "Profile and preferences", "person.crop.circle")
            accountLink(.sessions, "Sessions", "laptopcomputer.and.iphone")
            accountLink(.passkeys, "Passkeys", "person.badge.key")
            accountLink(.tokens, "API tokens", "key")
            accountLink(.authorizedApps, "Authorized apps", "app.badge.checkmark")
            accountLink(.vpn, "VPN", "network")
            accountLink(.sshKeys, "SSH keys", "terminal")
        }
    }
}

private func accountLink(_ destination: AccountDestination, _ title: LocalizedStringKey, _ symbol: String) -> some View {
    NavigationLink(value: MoreDestination.account(destination)) {
        Label(title, systemImage: symbol)
            .foregroundStyle(.primary)
    }
}

/// AccountMoreSections is what More adds for people management.
struct AccountMoreSections: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        let access = session.peopleAccess
        if access.hasPeopleEntry {
            Section("People") {
                if session.isStaff {
                    link(.organizations, "People by organization", "person.2")
                } else if let organizationId = session.organizationId {
                    if access.canSeeMembers(in: organizationId) { link(.members(organizationId: organizationId), "Members", "person.2") }
                    if access.canSeeGroups(in: organizationId) { link(.groups(organizationId: organizationId), "Groups", "person.3") }
                    if access.canOpenRoles(in: organizationId) { link(.roles(organizationId: organizationId), "Roles", "checkmark.shield") }
                }
            }
        }
    }

    private func link(_ destination: AccountDestination, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        accountLink(destination, title, symbol)
    }
}

/// ActionState runs the changes a screen makes and keeps the words of one that failed.
@MainActor
@Observable
final class ActionState {
    var errorMessage: String?
    private(set) var isWorking = false

    /// Runs the work. Returns whether it succeeded; on failure the message is kept for the screen's alert.
    @discardableResult
    func run(appModel: AppModel, session: SessionModel, _ work: () async throws -> Void) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            return true
        } catch {
            appModel.handle(error, account: session.account)
            errorMessage = error.userMessage
            return false
        }
    }
}

extension View {
    /// Says what went wrong when a change was refused, in an alert that asks for nothing more than an OK.
    func failureAlert(_ state: ActionState) -> some View {
        alert(
            "Could not do that", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } }),
            actions: { Button("OK", role: .cancel) {} }, message: { Text(state.errorMessage ?? "") })
    }
}

/// WebPage opens a page of Portal on the web in the built-in browser, signed in through the web session handoff.
@MainActor
struct WebPage {
    let appModel: AppModel
    let session: SessionModel

    func open(_ path: String) {
        let url = session.account.server.endpoint(path)
        Task { await appModel.openInApp(url, account: session.account) }
    }
}

/// OnTheWebRow is the row for what the app is not allowed to create: it opens the matching Portal page on the web, and the screen
/// reads its list again when the person closes the browser.
struct OnTheWebRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    let path: String

    var body: some View {
        Section {
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
        } footer: {
            Text(explanation)
        }
    }
}

enum AccountText {
    /// "5 minutes ago", or nil when there is no date.
    static func relative(_ text: String?) -> String? {
        PortalDate.parse(text).map { $0.formatted(.relative(presentation: .named)) }
    }

    /// "Mar 1, 2026", or nil when there is no date.
    static func day(_ text: String?) -> String? {
        PortalDate.parse(text).map { $0.formatted(.dateTime.year().month().day()) }
    }

    static func permissions(_ count: Int) -> String {
        count == 1 ? String(localized: "1 permission") : String(localized: "\(count) permissions")
    }

    static func added(_ text: String?) -> String? {
        day(text).map { String(localized: "Added \($0)") }
    }

    static func lastUsed(_ text: String?) -> String {
        relative(text).map { String(localized: "Last used \($0)") } ?? String(localized: "Never used")
    }
}
