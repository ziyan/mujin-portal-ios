import PortalKit
import SwiftUI

/// AICatalogSnapshot is the providers and agents of the platform, read together because an agent names the providers it runs on.
struct AICatalogSnapshot: Sendable {
    let providers: [AIProvider]
    let agents: [AIAgent]
}

private func loadCatalog(_ connection: Connection) async throws -> AICatalogSnapshot {
    async let providers = connection.aiProviders()
    async let agents = connection.aiAgents()
    return AICatalogSnapshot(providers: try await providers, agents: try await agents)
}

// MARK: providers

/// ProvidersView lists the models the assistant can run on.
struct ProvidersView: View {
    var body: some View {
        PlatformPage(title: "AI providers", failureTitle: "Could not load providers", load: { (connection: Connection) -> AICatalogSnapshot in try await loadCatalog(connection) }) {
            snapshot, reload in
            ProvidersList(providers: snapshot.providers, reload: reload)
        }
    }
}

private struct ProvidersList: View {
    let providers: [AIProvider]
    let reload: PageReload

    @State private var isAdding = false

    var body: some View {
        List {
            PortalRows {
                if providers.isEmpty {
                    Section { Text("There are no providers yet.").foregroundStyle(Color.secondary) }
                } else {
                    Section {
                        ForEach(providers) { provider in
                            NavigationLink(value: MoreDestination.platform(.provider(id: provider.id))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.shownName)
                                        .foregroundStyle(Color.primary)
                                    Text([provider.typeName, provider.modelName ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                    if provider.isEnabled == false {
                                        Text("Switched off")
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    } else if !provider.hasAPIKey {
                                        Label("No key set", systemImage: "exclamationmark.triangle")
                                            .font(.footnote)
                                            .foregroundStyle(Color.statusWarning)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Add provider", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding) {
            ProviderFormSheet(provider: nil) { await reload() }
        }
    }
}

/// ProviderFormSheet adds a provider or changes its name, model and address. The key is set apart, because the server never takes it with the rest.
private struct ProviderFormSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider?
    let onSaved: () async -> Void

    @State private var name = ""
    @State private var type = AIProviderType.anthropic
    @State private var modelName = ""
    @State private var baseUrl = ""
    @State private var actions = ActionState()

    private var isNew: Bool { provider == nil }
    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasModel = !modelName.trimmingCharacters(in: .whitespaces).isEmpty
        guard hasName && hasModel && !actions.isWorking else { return false }
        guard let provider else { return true }
        return name.trimmingCharacters(in: .whitespaces) != provider.shownName || modelName.trimmingCharacters(in: .whitespaces) != (provider.modelName ?? "")
            || baseUrl.trimmingCharacters(in: .whitespaces) != (provider.baseUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section {
                        TextField("Name", text: $name)
                        if isNew {
                            Picker("Vendor", selection: $type) {
                                ForEach(AIProviderType.allCases, id: \.self) { type in Text(type.title).tag(type) }
                            }
                        }
                        TextField("Model name", text: $modelName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Address (optional)", text: $baseUrl)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } footer: {
                        if isNew { Text("Set the key from the provider's page after adding it.") }
                    }
                }
            }
            .portalList()
            .navigationTitle(isNew ? LocalizedStringKey("Add provider") : LocalizedStringKey("Edit provider"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                name = provider?.name ?? ""
                type = AIProviderType(rawValue: provider?.providerType ?? "") ?? .anthropic
                modelName = provider?.modelName ?? ""
                baseUrl = provider?.baseUrl ?? ""
            }
            .failureAlert(actions)
        }
    }

    private func save() async {
        let connection = appModel.connection(for: session.account)
        let newName = name.trimmingCharacters(in: .whitespaces)
        let newModel = modelName.trimmingCharacters(in: .whitespaces)
        let newAddress = baseUrl.trimmingCharacters(in: .whitespaces)
        let chosenType = type
        let existing = provider
        let saved = await actions.run(appModel: appModel, session: session) {
            if let existing {
                try await connection.modifyAIProvider(id: existing.id, name: newName, modelName: newModel, baseUrl: newAddress)
            } else {
                try await connection.createAIProvider(name: newName, type: chosenType, modelName: newModel, baseUrl: newAddress)
            }
        }
        if saved {
            await onSaved()
            dismiss()
        }
    }
}

/// ProviderView is one provider: whether it is on, what it runs, whether it has a key, and the ways to change it.
struct ProviderView: View {
    let providerId: String

    var body: some View {
        PlatformPage(title: "Provider", failureTitle: "Could not load this provider", load: { (connection: Connection) -> AICatalogSnapshot in try await loadCatalog(connection) }) {
            snapshot, reload in
            if let provider = snapshot.providers.first(where: { $0.id == providerId }) {
                ProviderDetail(provider: provider, reload: reload)
            } else {
                ContentUnavailableView("This provider is gone", systemImage: "cpu")
            }
        }
    }
}

private struct ProviderDetail: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    let reload: PageReload

    @State private var isEditing = false
    @State private var isSettingKey = false
    @State private var isConfirmingDelete = false
    @State private var actions = ActionState()

    var body: some View {
        List {
            PortalRows {
                Section {
                    Toggle(
                        "On",
                        isOn: Binding(
                            get: { provider.isEnabled != false },
                            set: { isOn in Task { await change { try await $0.modifyAIProvider(id: provider.id, isEnabled: isOn) } } })
                    )
                } footer: {
                    Text("A provider that is switched off is not used for new answers.")
                }
                Section {
                    LabeledContent("Name") { Text(provider.shownName).foregroundStyle(Color.secondary) }
                    LabeledContent("Vendor") { Text(provider.typeName).foregroundStyle(Color.secondary) }
                    if let model = provider.modelName, !model.isEmpty { LabeledContent("Model") { Text(model).foregroundStyle(Color.secondary) } }
                    if let address = provider.baseUrl, !address.isEmpty { LabeledContent("Address") { Text(address).foregroundStyle(Color.secondary) } }
                    if let window = provider.contextWindow { LabeledContent("Context window") { Text(UsageFormat.tokens(window)).foregroundStyle(Color.secondary) } }
                    if let limit = provider.maxOutputTokens { LabeledContent("Longest answer") { Text(UsageFormat.tokens(limit)).foregroundStyle(Color.secondary) } }
                    LabeledContent("Key") {
                        Text(provider.hasAPIKey ? (provider.apiKeyFingerprint ?? "") : String(localized: "Not set")).foregroundStyle(Color.secondary)
                    }
                } footer: {
                    Text("A key is stored sealed and is never shown again.")
                }
            }
        }
        .portalList()
        .navigationTitle(provider.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DetailMenu {
                    Section {
                        Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
                        Button { isSettingKey = true } label: {
                            Label(provider.hasAPIKey ? "Replace the key" : "Set the key", systemImage: "key")
                        }
                    }
                    Section {
                        Button(role: .destructive) { isConfirmingDelete = true } label: { Label("Delete provider", systemImage: "trash") }
                    }
                }
                .confirmationDialog("Delete this provider?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete \(provider.shownName)", role: .destructive) {
                        Task {
                            if await change({ try await $0.deleteAIProvider(id: provider.id) }) { dismiss() }
                        }
                    }
                } message: {
                    Text("Agents and organizations that use it lose it.")
                }
            }
        }
        .refreshable { await reload() }
        .sheet(isPresented: $isEditing) { ProviderFormSheet(provider: provider) { await reload() } }
        .sheet(isPresented: $isSettingKey) {
            PlatformTextSheet(title: "Provider key", prompt: "Key", initialText: "", isSecret: true, explanation: "Paste the key from the vendor. It replaces the one stored now.") { key in
                try await appModel.connection(for: session.account).setAIProviderKey(id: provider.id, apiKey: key)
                await reload()
            }
        }
        .failureAlert(actions)
    }

    @discardableResult
    private func change(_ work: @escaping (Connection) async throws -> Void) async -> Bool {
        let connection = appModel.connection(for: session.account)
        let succeeded = await actions.run(appModel: appModel, session: session) { try await work(connection) }
        if succeeded { await reload() }
        return succeeded
    }
}

// MARK: agents

/// AgentsView lists the assistants people can talk to.
struct AgentsView: View {
    var body: some View {
        PlatformPage(title: "AI agents", failureTitle: "Could not load agents", load: { (connection: Connection) -> AICatalogSnapshot in try await loadCatalog(connection) }) {
            snapshot, reload in
            AgentsList(snapshot: snapshot, reload: reload)
        }
    }
}

private struct AgentsList: View {
    let snapshot: AICatalogSnapshot
    let reload: PageReload

    @State private var isAdding = false

    var body: some View {
        List {
            PortalRows {
                if snapshot.agents.isEmpty {
                    Section { Text("There are no agents yet.").foregroundStyle(Color.secondary) }
                } else {
                    Section {
                        ForEach(snapshot.agents) { agent in
                            NavigationLink(value: MoreDestination.platform(.agent(id: agent.id))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.shownName)
                                        .foregroundStyle(Color.primary)
                                    if let description = agent.description, !description.isEmpty {
                                        Text(description)
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(2)
                                    }
                                    if agent.isMain == true {
                                        Text("Main assistant")
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    }
                                    if agent.isEnabled == false {
                                        Text("Switched off")
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Add agent", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding) {
            AgentFormSheet(agent: nil, providers: snapshot.providers) { await reload() }
        }
    }
}

/// AgentFormSheet adds an agent or changes its name, description, instructions and the providers it runs on.
private struct AgentFormSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let agent: AIAgent?
    let providers: [AIProvider]
    let onSaved: () async -> Void

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var systemPrompt = ""
    @State private var defaultProviderId = ""
    @State private var quickProviderId = ""
    @State private var actions = ActionState()

    private var isNew: Bool { agent == nil }
    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPrompt = !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasName && hasPrompt && !actions.isWorking else { return false }
        guard let agent else { return true }
        return name != agent.shownName || descriptionText != (agent.description ?? "") || systemPrompt != (agent.systemPrompt ?? "")
            || defaultProviderId != (agent.defaultProviderId ?? "") || quickProviderId != (agent.quickProviderId ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section {
                        TextField("Name", text: $name)
                        TextField("Description", text: $descriptionText, axis: .vertical)
                            .lineLimit(1...4)
                    }
                    Section {
                        TextField("Instructions", text: $systemPrompt, axis: .vertical)
                            .lineLimit(4...16)
                    } header: {
                        Text("Instructions")
                    } footer: {
                        Text("What the agent is told before every conversation.")
                    }
                    Section {
                        providerPicker("Main provider", selection: $defaultProviderId)
                        providerPicker("Quick provider", selection: $quickProviderId)
                    } footer: {
                        Text("The quick provider answers small things fast. Leave it empty to use the main one.")
                    }
                }
            }
            .portalList()
            .navigationTitle(isNew ? LocalizedStringKey("Add agent") : LocalizedStringKey("Edit agent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                name = agent?.name ?? ""
                descriptionText = agent?.description ?? ""
                systemPrompt = agent?.systemPrompt ?? ""
                defaultProviderId = agent?.defaultProviderId ?? ""
                quickProviderId = agent?.quickProviderId ?? ""
            }
            .failureAlert(actions)
        }
    }

    private func providerPicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag("")
            ForEach(providers) { provider in Text(provider.shownName).tag(provider.id) }
        }
    }

    private func save() async {
        let connection = appModel.connection(for: session.account)
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDefault = defaultProviderId
        let newQuick = quickProviderId
        let existing = agent
        let saved = await actions.run(appModel: appModel, session: session) {
            if let existing {
                try await connection.modifyAIAgent(
                    id: existing.id, name: newName, description: newDescription, systemPrompt: newPrompt, defaultProviderId: newDefault, quickProviderId: newQuick)
            } else {
                try await connection.createAIAgent(name: newName, description: newDescription, systemPrompt: newPrompt, defaultProviderId: newDefault)
            }
        }
        if saved {
            await onSaved()
            dismiss()
        }
    }
}

/// AgentView is one agent: whether it is on, its instructions, the providers it runs on, and the ways to change it.
struct AgentView: View {
    let agentId: String

    var body: some View {
        PlatformPage(title: "Agent", failureTitle: "Could not load this agent", load: { (connection: Connection) -> AICatalogSnapshot in try await loadCatalog(connection) }) {
            snapshot, reload in
            if let agent = snapshot.agents.first(where: { $0.id == agentId }) {
                AgentDetail(agent: agent, providers: snapshot.providers, reload: reload)
            } else {
                ContentUnavailableView("This agent is gone", systemImage: "person.crop.square")
            }
        }
    }
}

private struct AgentDetail: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let agent: AIAgent
    let providers: [AIProvider]
    let reload: PageReload

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var actions = ActionState()

    var body: some View {
        List {
            PortalRows {
                Section {
                    Toggle(
                        "On",
                        isOn: Binding(
                            get: { agent.isEnabled != false },
                            set: { isOn in Task { await change { try await $0.modifyAIAgent(id: agent.id, isEnabled: isOn) } } })
                    )
                } footer: {
                    if agent.isMain == true { Text("This is the main assistant people talk to first.") }
                }
                Section {
                    if let description = agent.description, !description.isEmpty { Text(description).foregroundStyle(Color.primary) }
                    LabeledContent("Main provider") { Text(AICatalog.providerName(agent.defaultProviderId, in: providers) ?? String(localized: "None")).foregroundStyle(Color.secondary) }
                    LabeledContent("Quick provider") { Text(AICatalog.providerName(agent.quickProviderId, in: providers) ?? String(localized: "None")).foregroundStyle(Color.secondary) }
                }
                if let prompt = agent.systemPrompt, !prompt.isEmpty {
                    Section("Instructions") {
                        Text(prompt)
                            .font(.footnote)
                            .foregroundStyle(Color.primary)
                            .lineLimit(12)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .portalList()
        .navigationTitle(agent.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DetailMenu {
                    Section {
                        Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
                    }
                    if agent.isMain != true {
                        Section {
                            Button(role: .destructive) { isConfirmingDelete = true } label: { Label("Delete agent", systemImage: "trash") }
                        }
                    }
                }
                .confirmationDialog("Delete this agent?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete \(agent.shownName)", role: .destructive) {
                        Task {
                            if await change({ try await $0.deleteAIAgent(id: agent.id) }) { dismiss() }
                        }
                    }
                } message: {
                    Text("Its conversations stay, but nobody can start a new one with it.")
                }
            }
        }
        .refreshable { await reload() }
        .sheet(isPresented: $isEditing) { AgentFormSheet(agent: agent, providers: providers) { await reload() } }
        .failureAlert(actions)
    }

    @discardableResult
    private func change(_ work: @escaping (Connection) async throws -> Void) async -> Bool {
        let connection = appModel.connection(for: session.account)
        let succeeded = await actions.run(appModel: appModel, session: session) { try await work(connection) }
        if succeeded { await reload() }
        return succeeded
    }
}

// MARK: grants

/// GrantsOrganizationsView is where a platform administrator chooses the organization whose AI access to set.
struct GrantsOrganizationsView: View {
    @State private var query = ""

    var body: some View {
        PlatformPage(title: "AI access", failureTitle: "Could not load organizations", load: { try await $0.allOrganizations() }) { organizations, reload in
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = text.isEmpty ? organizations : organizations.filter { ($0.name ?? "").localizedCaseInsensitiveContains(text) }
            List {
                PortalRows {
                    ForEach(shown) { organization in
                        NavigationLink(value: MoreDestination.platform(.organizationGrants(organizationId: organization.id))) {
                            Label(organization.name ?? organization.id, systemImage: "building.2")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .portalList()
            .overlay {
                if shown.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .refreshable { await reload() }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search organizations")
    }
}

struct GrantsSnapshot: Sendable {
    let catalog: AICatalogSnapshot
    let grants: AIGrants
}

/// OrganizationGrantsView is the providers and agents one organization may use, each switched on or off.
struct OrganizationGrantsView: View {
    let organizationId: String

    var body: some View {
        PlatformPage(
            title: "AI access", failureTitle: "Could not load AI access",
            load: { [organizationId] (connection: Connection) -> GrantsSnapshot in
                async let catalog = loadCatalog(connection)
                async let grants = connection.aiGrants(organizationId: organizationId)
                return GrantsSnapshot(catalog: try await catalog, grants: try await grants)
            }
        ) { snapshot, reload in
            OrganizationGrantsList(organizationId: organizationId, snapshot: snapshot, reload: reload)
        }
    }
}

private struct OrganizationGrantsList: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String
    let snapshot: GrantsSnapshot
    let reload: PageReload

    @State private var actions = ActionState()

    var body: some View {
        List {
            PortalRows {
                Section {
                    if snapshot.catalog.providers.isEmpty { Text("There are no providers.").foregroundStyle(Color.secondary) }
                    ForEach(snapshot.catalog.providers) { provider in
                        Toggle(
                            provider.shownName,
                            isOn: Binding(
                                get: { snapshot.grants.providerIds.contains(provider.id) },
                                set: { isOn in
                                    Task { await change { try await $0.setProviderGrant(organizationId: organizationId, providerId: provider.id, isGranted: isOn) } }
                                })
                        )
                    }
                } header: {
                    Text("Providers")
                } footer: {
                    Text("People of \(session.organizationName(for: organizationId) ?? String(localized: "this organization")) can use the providers that are on.")
                }
                Section {
                    if snapshot.catalog.agents.isEmpty { Text("There are no agents.").foregroundStyle(Color.secondary) }
                    ForEach(snapshot.catalog.agents) { agent in
                        Toggle(
                            agent.shownName,
                            isOn: Binding(
                                get: { snapshot.grants.agentIds.contains(agent.id) },
                                set: { isOn in
                                    Task { await change { try await $0.setAgentGrant(organizationId: organizationId, agentId: agent.id, isGranted: isOn) } }
                                })
                        )
                    }
                } header: {
                    Text("Agents")
                }
            }
        }
        .portalList()
        .refreshable { await reload() }
        .failureAlert(actions)
    }

    private func change(_ work: @escaping (Connection) async throws -> Void) async {
        let connection = appModel.connection(for: session.account)
        _ = await actions.run(appModel: appModel, session: session) { try await work(connection) }
        await reload()
    }
}
