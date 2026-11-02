import PortalKit
import SwiftUI

/// GroupsView lists the groups of an organization.
struct GroupsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String

    @State private var phase = LoadPhase.loading
    @State private var groups: [AccessGroup] = []
    @State private var isCreating = false

    private var canEdit: Bool { session.peopleAccess.canEditGroups(in: organizationId) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load groups", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, phase == .loaded {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New group", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            NameFormSheet(title: "New group", submitTitle: "Create", namePrompt: "Group name", initialName: "", initialDescription: "") { name, description in
                _ = try await appModel.connection(for: session.account).createGroup(organizationId: organizationId, name: name, description: description)
                await load()
            }
        }
        .task { await load() }
    }

    private var list: some View {
        List {
            PortalRows {
                Section {
                    ForEach(groups) { group in
                        NavigationLink {
                            GroupDetailView(groupId: group.id, organizationId: organizationId)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.shownName)
                                    .foregroundStyle(Color.primary)
                                if group.isDefault == true {
                                    Text("Default group")
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                }
                                Text("^[\(group.siteCount) site](inflect: true), ^[\(group.roleCount) role](inflect: true)")
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("People in a group get its roles at the sites it covers.")
                }
            }
        }
        .portalList()
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No groups", systemImage: "person.2.crop.square.stack")
                } description: {
                    Text("Make a group, add people to it and choose the sites and roles it gives.")
                }
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            groups = try await appModel.connection(for: session.account).groups(organizationId: organizationId)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// GroupDetailView is one group: its details, the sites it covers, the roles it gives and the people in it.
struct GroupDetailView: View {
    private enum Editing: String, Identifiable {
        case details
        case sites
        case roles
        case people
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let groupId: String
    let organizationId: String

    @State private var phase = LoadPhase.loading
    @State private var group: AccessGroup?
    @State private var roles: [AccessRole] = []
    @State private var sites: [SiteSummary] = []
    @State private var members: [OrganizationMember] = []
    @State private var memberIds: [String] = []
    @State private var editing: Editing?
    @State private var isConfirmingDefault = false
    @State private var isConfirmingDeletion = false
    @State private var actions = ActionState()

    private var canEdit: Bool { session.peopleAccess.canEditGroups(in: group?.organizationId ?? organizationId) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this group", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if let group { details(group) }
            }
        }
        .navigationTitle(group?.shownName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, group != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = .details }
                }
            }
        }
        .sheet(item: $editing) { kind in
            if let group { editorSheet(kind, group: group) }
        }
        .task { await load() }
        .failureAlert(actions)
    }

    private func details(_ group: AccessGroup) -> some View {
        let siteNames = Dictionary(sites.map { ($0.id, $0.name ?? $0.id) }, uniquingKeysWith: { first, _ in first })
        let roleNames = Dictionary(roles.map { ($0.id, $0.shownName) }, uniquingKeysWith: { first, _ in first })
        let memberByIdentifier = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return List {
            PortalRows {
                Section {
                    if let text = group.description, !text.isEmpty {
                        Text(text).foregroundStyle(Color.primary)
                    }
                    if group.isDefault == true {
                        Label("Default group", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.secondary)
                    } else if canEdit {
                        Button {
                            isConfirmingDefault = true
                        } label: {
                            Text("Make this the default group")
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Make this the default group?", isPresented: $isConfirmingDefault, titleVisibility: .visible) {
                            Button("Make default") { Task { await makeDefault() } }
                        } message: {
                            Text("A person who joins the organization and is in no group is put in the default group.")
                        }
                    }
                }
                Section {
                    ForEach(group.siteIds ?? [], id: \.self) { siteId in Text(siteNames[siteId] ?? siteId).foregroundStyle(Color.primary) }
                    if (group.siteIds ?? []).isEmpty { Text("No sites yet.").foregroundStyle(Color.secondary) }
                    if canEdit { chooseButton("Choose sites", .sites) }
                } header: {
                    Text("Sites")
                }
                Section {
                    ForEach(group.roles ?? [], id: \.self) { roleId in Text(roleNames[roleId] ?? roleId).foregroundStyle(Color.primary) }
                    if (group.roles ?? []).isEmpty { Text("No roles yet. People get no access from this group.").foregroundStyle(Color.secondary) }
                    if canEdit { chooseButton("Choose roles", .roles) }
                } header: {
                    Text("Roles")
                } footer: {
                    Text("These roles apply at every site of the group.")
                }
                Section {
                    ForEach(memberIds, id: \.self) { memberId in
                        NavigationLink {
                            UserDetailView(userId: memberId, organizationId: group.organizationId ?? organizationId)
                        } label: {
                            if let member = memberByIdentifier[memberId] {
                                PersonRow(member: member)
                            } else {
                                Text("Someone")
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                    if memberIds.isEmpty { Text("Nobody yet.").foregroundStyle(Color.secondary) }
                    if canEdit { chooseButton("Choose people", .people) }
                } header: {
                    Text("People")
                }
                if canEdit {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingDeletion = true
                        } label: {
                            Text("Delete group")
                                .foregroundStyle(Color.statusError)
                        }
                        .confirmationDialog("Delete \(group.shownName)?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
                            Button("Delete group", role: .destructive) { Task { await delete() } }
                        } message: {
                            Text("Its people lose the access it gave them. This cannot be undone.")
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func chooseButton(_ title: LocalizedStringKey, _ kind: Editing) -> some View {
        Button {
            editing = kind
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func editorSheet(_ kind: Editing, group: AccessGroup) -> some View {
        switch kind {
        case .details:
            NameFormSheet(
                title: "Edit group", submitTitle: "Save", namePrompt: "Group name", initialName: group.name ?? "", initialDescription: group.description ?? ""
            ) { name, description in
                try await appModel.connection(for: session.account).modifyGroup(id: groupId, name: name, description: description)
                await load()
            }
        case .sites:
            MultiSelectSheet(
                title: "Sites", emptyMessage: "There are no sites to choose from.",
                items: sites.filter { $0.isArchived != true || (group.siteIds ?? []).contains($0.id) }
                    .map { SelectionItem(id: $0.id, title: $0.name ?? $0.id) }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
                initiallySelected: Set(group.siteIds ?? [])
            ) { wanted in
                let connection = appModel.connection(for: session.account)
                let changes = SelectionChanges(current: Set(group.siteIds ?? []), wanted: wanted)
                do {
                    for siteId in changes.added { try await connection.assignSite(siteId, toGroup: groupId) }
                    for siteId in changes.removed { try await connection.removeSite(siteId, fromGroup: groupId) }
                } catch {
                    await load()
                    throw error
                }
                await load()
            }
        case .roles:
            MultiSelectSheet(
                title: "Roles", emptyMessage: "There are no roles to choose from. Make one under Roles first.",
                items: roles.map { SelectionItem(id: $0.id, title: $0.shownName, subtitle: AccountText.permissions($0.permissionCount)) },
                initiallySelected: Set(group.roles ?? [])
            ) { wanted in
                try await appModel.connection(for: session.account).setGroupRoles(groupId: groupId, roleIds: wanted.sorted())
                await load()
            }
        case .people:
            MultiSelectSheet(
                title: "People", emptyMessage: "There is nobody in this organization to choose.",
                items: MemberDirectory.filter(members.filter { !$0.isDeactivated || memberIds.contains($0.id) }, includesDeactivated: true)
                    .map { SelectionItem(id: $0.id, title: $0.shownName, subtitle: $0.email) },
                initiallySelected: Set(memberIds)
            ) { wanted in
                let connection = appModel.connection(for: session.account)
                let changes = SelectionChanges(current: Set(memberIds), wanted: wanted)
                do {
                    try await connection.assignUsers(changes.added, toGroup: groupId)
                    try await connection.removeUsers(changes.removed, fromGroup: groupId)
                } catch {
                    await load()
                    throw error
                }
                await load()
            }
        }
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        let identifier = groupId
        do {
            let loaded = try await connection.group(id: identifier)
            group = loaded
            phase = .loaded
            let groupOrganizationId = loaded.organizationId ?? organizationId
            // A group of the administrator organization may cover any organization's sites; any other group, its own organization's.
            let coversEverySite = session.profile?.isMujinOrganization == true && groupOrganizationId == session.organizationId
            async let loadedRoles = try? connection.roles(organizationId: groupOrganizationId)
            async let loadedSites = try? connection.allSites(organizationId: coversEverySite ? nil : groupOrganizationId)
            async let loadedIds = try? connection.groupUserIds(groupId: identifier)
            async let loadedMembers = try? connection.organizationMembers(organizationId: groupOrganizationId)
            roles = await loadedRoles ?? []
            sites = await loadedSites ?? []
            memberIds = await loadedIds ?? []
            members = await loadedMembers ?? []
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) } else { actions.errorMessage = error.userMessage }
        }
    }

    private func makeDefault() async {
        let connection = appModel.connection(for: session.account)
        let identifier = groupId
        if await actions.run(appModel: appModel, session: session, { try await connection.setDefaultGroup(id: identifier) }) { await load() }
    }

    private func delete() async {
        let connection = appModel.connection(for: session.account)
        let identifier = groupId
        if await actions.run(appModel: appModel, session: session, { try await connection.deleteGroup(id: identifier) }) { dismiss() }
    }
}
