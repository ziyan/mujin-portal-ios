import SwiftUI

/// NameFormSheet asks for the name and description of a group or a role, to make one or to change one.
struct NameFormSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let submitTitle: LocalizedStringKey
    let namePrompt: LocalizedStringKey
    let initialName: String
    let initialDescription: String
    let onSubmit: (String, String) async throws -> Void

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var actions = ActionState()

    private var wantedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var wantedDescription: String { descriptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isChanged: Bool { wantedName != initialName || wantedDescription != initialDescription }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section {
                        TextField(namePrompt, text: $name)
                        TextField("Description", text: $descriptionText, axis: .vertical)
                            .lineLimit(1...6)
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
                    Button(submitTitle) { Task { await submit() } }
                        .disabled(wantedName.isEmpty || !isChanged || actions.isWorking)
                }
            }
            .onAppear {
                name = initialName
                descriptionText = initialDescription
            }
            .failureAlert(actions)
        }
    }

    private func submit() async {
        let newName = wantedName
        let newDescription = wantedDescription
        let submit = onSubmit
        if await actions.run(appModel: appModel, session: session, { try await submit(newName, newDescription) }) { dismiss() }
    }
}

/// SelectionItem is one choice in a MultiSelectSheet.
struct SelectionItem: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String?
}

/// MultiSelectSheet lets the person tick any number of choices and saves the whole selection at once.
struct MultiSelectSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let emptyMessage: LocalizedStringKey
    let items: [SelectionItem]
    let initiallySelected: Set<String>
    let onSave: (Set<String>) async throws -> Void

    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var actions = ActionState()

    private var shown: [SelectionItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty
            ? items : items.filter { $0.title.localizedCaseInsensitiveContains(text) || ($0.subtitle ?? "").localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    if items.isEmpty {
                        Section { Text(emptyMessage).foregroundStyle(Color.secondary) }
                    }
                    Section {
                        ForEach(shown) { item in
                            Button {
                                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .foregroundStyle(Color.primary)
                                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.footnote)
                                                .foregroundStyle(Color.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selected.contains(item.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityLabel("Chosen")
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("^[\(selected.count) item](inflect: true) chosen")
                    }
                }
            }
            .portalList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(selected == initiallySelected || actions.isWorking)
                }
            }
            .onAppear { selected = initiallySelected }
            .failureAlert(actions)
        }
    }

    private func save() async {
        let chosen = selected
        let save = onSave
        if await actions.run(appModel: appModel, session: session, { try await save(chosen) }) { dismiss() }
    }
}

/// PeopleOrganization names an organization to show the people of in a sheet.
struct PeopleOrganization: Identifiable {
    let id: String
}

/// PeopleSheet shows an organization's people over the screen it was asked from, with a button to go back.
struct PeopleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let organizationId: String

    var body: some View {
        NavigationStack {
            PeopleHubView(organizationId: organizationId)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
