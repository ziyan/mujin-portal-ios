import PortalKit
import SwiftUI

/// RolesView lists the roles of an organization.
struct RolesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String

    @State private var phase = LoadPhase.loading
    @State private var roles: [AccessRole] = []
    @State private var isCreating = false

    private var canEdit: Bool { session.peopleAccess.canEditRoles(in: organizationId) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load roles", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Roles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, phase == .loaded {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New role", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            NameFormSheet(title: "New role", submitTitle: "Create", namePrompt: "Role name", initialName: "", initialDescription: "") { name, description in
                _ = try await appModel.connection(for: session.account).createRole(organizationId: organizationId, name: name, description: description)
                await load()
            }
        }
        .task { await load() }
    }

    private var list: some View {
        List {
            PortalRows {
                Section {
                    ForEach(roles) { role in
                        NavigationLink {
                            RoleDetailView(roleId: role.id, organizationId: organizationId)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(role.shownName)
                                    .foregroundStyle(Color.primary)
                                Text(AccountText.permissions(role.permissionCount))
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                                if let text = role.description, !text.isEmpty {
                                    Text(text)
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("A role is a set of permissions. Groups hand roles to their people at the sites they cover.")
                }
            }
        }
        .portalList()
        .overlay {
            if roles.isEmpty {
                ContentUnavailableView {
                    Label("No roles", systemImage: "checkmark.shield")
                } description: {
                    Text("Make a role, choose its permissions, then give it to a group.")
                }
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            roles = try await appModel.connection(for: session.account).roles(organizationId: organizationId)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// RoleDetailView is one role: its description and every permission, grouped by what it is about. A switch saves at once.
struct RoleDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let roleId: String
    let organizationId: String

    @State private var phase = LoadPhase.loading
    @State private var role: AccessRole?
    @State private var catalog: [PermissionGroup] = []
    @State private var held: [String] = []
    @State private var isEditing = false
    @State private var isConfirmingDeletion = false
    @State private var saveTask: Task<Void, Never>?
    @State private var actions = ActionState()

    private var canEdit: Bool { session.peopleAccess.canEditRoles(in: role?.organizationId ?? organizationId) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this role", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if let role { details(role) }
            }
        }
        .navigationTitle(role?.shownName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, role != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let role {
                NameFormSheet(
                    title: "Edit role", submitTitle: "Save", namePrompt: "Role name", initialName: role.name ?? "", initialDescription: role.description ?? ""
                ) { name, description in
                    try await appModel.connection(for: session.account).modifyRole(id: roleId, name: name, description: description)
                    await load()
                }
            }
        }
        .task { await load() }
        .failureAlert(actions)
    }

    private func details(_ role: AccessRole) -> some View {
        List {
            PortalRows {
                if let text = role.description, !text.isEmpty {
                    Section { Text(text).foregroundStyle(Color.primary) }
                }
                ForEach(catalog) { group in
                    Section {
                        ForEach(group.permissions, id: \.self) { key in
                            Toggle(isOn: binding(for: key)) {
                                Text(key)
                                    .foregroundStyle(Color.primary)
                            }
                            .disabled(!canEdit)
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Text("\(group.selectedCount(in: Set(held))) of \(group.permissions.count)")
                                .monospacedDigit()
                        }
                    }
                }
                if catalog.isEmpty {
                    Section { Text("This server offers no permissions to choose from.").foregroundStyle(Color.secondary) }
                }
                if canEdit {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingDeletion = true
                        } label: {
                            Text("Delete role")
                                .foregroundStyle(Color.statusError)
                        }
                        .confirmationDialog("Delete \(role.shownName)?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
                            Button("Delete role", role: .destructive) { Task { await delete() } }
                        } message: {
                            Text("Groups lose the permissions it gave them. This cannot be undone.")
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(get: { held.contains(key) }, set: { isOn in setPermission(key, isOn: isOn) })
    }

    /// Shows the change at once and saves the whole set. Saves go one after the other, so the last switch the person made is the last one saved.
    private func setPermission(_ key: String, isOn: Bool) {
        held = PermissionCatalog.setting(key, isOn: isOn, in: held)
        let snapshot = held
        let previous = saveTask
        let connection = appModel.connection(for: session.account)
        let identifier = roleId
        saveTask = Task {
            await previous?.value
            let succeeded = await actions.run(appModel: appModel, session: session) {
                try await connection.setRolePermissions(roleId: identifier, permissions: snapshot)
            }
            // A refused change is taken back by reading the role again.
            if !succeeded { await load() }
        }
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        let identifier = roleId
        do {
            let loaded = try await connection.role(id: identifier)
            role = loaded
            held = loaded.permissions ?? []
            phase = .loaded
            let catalogKeys = (try? await connection.permissionCatalog(organizationId: loaded.organizationId ?? organizationId)) ?? []
            catalog = PermissionCatalog.grouped(catalogKeys)
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) } else { actions.errorMessage = error.userMessage }
        }
    }

    private func delete() async {
        let connection = appModel.connection(for: session.account)
        let identifier = roleId
        if await actions.run(appModel: appModel, session: session, { try await connection.deleteRole(id: identifier) }) { dismiss() }
    }
}
