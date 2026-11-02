import PortalKit
import SwiftUI

/// ManagedFact is one labelled value on an item's own screen.
struct ManagedFact: Hashable, Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// ManagedItem is one session, token, passkey, app, VPN device or SSH key, as the lists of the account screens show it.
struct ManagedItem: Hashable, Identifiable {
    let id: String
    let title: String
    /// What tells this one from the others, under its title in the list.
    var lines: [String] = []
    var facts: [ManagedFact] = []
    /// The name that can be changed, or nil when this one cannot be renamed.
    var renameableName: String?
    /// Why this one is not ended here, when it is not.
    var protectionNote: String?
}

struct ManagedSection: Identifiable, Hashable {
    let id: String
    var title: String?
    var items: [ManagedItem]
}

/// ManagedListSpec says what a list of the account screens loads, shows and changes. The six lists differ in these words and calls and
/// in nothing else, so one screen draws them all.
struct ManagedListSpec {
    var title: LocalizedStringKey
    var emptyTitle: LocalizedStringKey
    var emptySymbol: String
    var emptyMessage: LocalizedStringKey
    /// Said under the list.
    var introduction: LocalizedStringKey?
    var renamePrompt: LocalizedStringKey = "Name"
    var removeTitle: LocalizedStringKey
    var removeMessage: @Sendable (ManagedItem) -> String
    /// The page of Portal on the web that adds one, for what the app is not allowed to create.
    var webPath: String?
    var webTitle: LocalizedStringKey = ""
    var webExplanation: LocalizedStringKey = ""
    var removeAllTitle: LocalizedStringKey?
    var removeAllMessage: LocalizedStringKey = ""
    var load: @Sendable (Connection) async throws -> [ManagedSection]
    var rename: (@Sendable (Connection, String, String) async throws -> Void)?
    var remove: @Sendable (Connection, String) async throws -> Void
    var removeAll: (@Sendable (Connection, [String]) async throws -> Void)?
}

/// ManagedListView is one of the account's lists: what is signed in, allowed or keyed to the person.
struct ManagedListView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let spec: ManagedListSpec

    @State private var phase = LoadPhase.loading
    @State private var sections: [ManagedSection] = []
    @State private var isConfirmingRemoveAll = false
    @State private var actions = ActionState()
    /// The demo opens the first row, as a person taps it.
    @State private var demoItem: ManagedItem?
    @State private var hasOpenedDemoItem = false

    private var itemCount: Int { sections.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this list", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle(spec.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $demoItem) { item in
            ManagedItemView(spec: spec, item: item) { await load() }
        }
        .task { await load() }
        // The person comes back from the web page that added one.
        .onChange(of: appModel.presentedWeb == nil) { _, isClosed in
            if isClosed { Task { await load() } }
        }
        .failureAlert(actions)
    }

    private var list: some View {
        List {
            PortalRows {
                if itemCount == 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(spec.emptyTitle, systemImage: spec.emptySymbol)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Text(spec.emptyMessage)
                                .foregroundStyle(Color.secondary)
                        }
                    } footer: {
                        if let introduction = spec.introduction { Text(introduction) }
                    }
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            NavigationLink {
                                ManagedItemView(spec: spec, item: item) { await load() }
                            } label: {
                                ManagedItemRow(item: item)
                            }
                        }
                    } header: {
                        if let title = section.title { Text(title) }
                    } footer: {
                        if section.id == sections.last?.id, let introduction = spec.introduction { Text(introduction) }
                    }
                }
                if let webPath = spec.webPath {
                    OnTheWebRow(title: spec.webTitle, explanation: spec.webExplanation, path: webPath)
                }
                if let removeAllTitle = spec.removeAllTitle, let removeAll = spec.removeAll, itemCount > 0 {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingRemoveAll = true
                        } label: {
                            Text(removeAllTitle)
                                .foregroundStyle(Color.statusError)
                        }
                        .confirmationDialog(removeAllTitle, isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
                            Button(removeAllTitle, role: .destructive) {
                                let identifiers = sections.flatMap(\.items).map(\.id)
                                Task {
                                    let connection = appModel.connection(for: session.account)
                                    await actions.run(appModel: appModel, session: session) { try await removeAll(connection, identifiers) }
                                    await load()
                                }
                            }
                        } message: {
                            Text(spec.removeAllMessage)
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        do {
            sections = try await spec.load(connection)
            phase = .loaded
            if appModel.isDemo, !hasOpenedDemoItem, AccountDemo.opensFirstItem(DemoOptions.screen) {
                hasOpenedDemoItem = true
                demoItem = sections.first?.items.first
            }
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading {
                phase = .failed(error.userMessage)
            } else {
                actions.errorMessage = error.userMessage
            }
        }
    }
}

private struct ManagedItemRow: View {
    let item: ManagedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .foregroundStyle(Color.primary)
            ForEach(item.lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}

/// ManagedItemView is one item on a screen of its own: all that is known of it, a new name when it may have one, and the way to end it.
struct ManagedItemView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let spec: ManagedListSpec
    let item: ManagedItem
    let onChanged: () async -> Void

    @State private var name = ""
    @State private var isConfirmingRemoval = false
    @State private var actions = ActionState()

    private var hasNewName: Bool {
        guard let current = item.renameableName else { return false }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !wanted.isEmpty && wanted != current
    }

    var body: some View {
        List {
            PortalRows {
                if item.renameableName != nil {
                    Section("Name") {
                        TextField(spec.renamePrompt, text: $name)
                            .autocorrectionDisabled()
                    }
                }
                if !item.facts.isEmpty {
                    Section {
                        ForEach(item.facts) { fact in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.label)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                                Text(fact.value)
                                    .foregroundStyle(Color.primary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                if let note = item.protectionNote {
                    Section { Text(note).foregroundStyle(Color.secondary) }
                } else {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingRemoval = true
                        } label: {
                            Text(spec.removeTitle)
                                .foregroundStyle(Color.statusError)
                        }
                        .confirmationDialog(spec.removeTitle, isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                            Button(spec.removeTitle, role: .destructive) { Task { await remove() } }
                        } message: {
                            Text(spec.removeMessage(item))
                        }
                    }
                }
            }
        }
        .portalList()
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item.renameableName != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await rename() } }
                        .disabled(!hasNewName || actions.isWorking)
                }
            }
        }
        .onAppear { name = item.renameableName ?? "" }
        .failureAlert(actions)
    }

    private func rename() async {
        guard let rename = spec.rename else { return }
        let connection = appModel.connection(for: session.account)
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = item.id
        if await actions.run(appModel: appModel, session: session, { try await rename(connection, identifier, wanted) }) {
            await onChanged()
            dismiss()
        }
    }

    private func remove() async {
        let connection = appModel.connection(for: session.account)
        let identifier = item.id
        let remove = spec.remove
        if await actions.run(appModel: appModel, session: session, { try await remove(connection, identifier) }) {
            await onChanged()
            dismiss()
        }
    }
}
