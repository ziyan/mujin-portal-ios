import PortalKit
import SwiftUI
import UIKit

/// ProfileSettingsView is the person's own name, job and preferences.
struct ProfileSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var phase = LoadPhase.loading
    @State private var profile: UserProfile?
    @State private var name = ""
    @State private var jobRole = ""
    @State private var activities: [String] = []
    @State private var customActivity = ""
    @State private var actions = ActionState()

    private var wantedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var wantedJobRole: String { jobRole.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasNameChange: Bool { !wantedName.isEmpty && wantedName != (profile?.name ?? "") }
    private var hasJobChange: Bool {
        wantedJobRole != (profile?.jobRole ?? "") || activities != (profile?.jobActivities ?? [])
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load your profile", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                form
            }
        }
        .navigationTitle("Profile and preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if phase == .loaded {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled((!hasNameChange && !hasJobChange) || wantedJobRole.count > ProfessionalProfile.maximumJobRoleLength || actions.isWorking)
                }
            }
        }
        .task { await load() }
        .failureAlert(actions)
    }

    private var form: some View {
        List {
            PortalRows {
                Section("Name") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    LabeledContent("Email") { Text(profile?.email ?? "").foregroundStyle(Color.secondary) }
                    if let organization = session.organizationName(for: profile?.organizationId ?? "") {
                        LabeledContent("Organization") { Text(organization).foregroundStyle(Color.secondary) }
                    }
                }
                Section {
                    TextField("Job title", text: $jobRole)
                } header: {
                    Text("Job title")
                } footer: {
                    Text("Shown next to your name. Up to \(ProfessionalProfile.maximumJobRoleLength) characters.")
                }
                Section {
                    ForEach(ProfessionalProfile.activityCodes, id: \.self) { code in activityRow(code, title: Self.title(of: code)) }
                    ForEach(activities.filter { !ProfessionalProfile.activityCodes.contains($0) }, id: \.self) { custom in activityRow(custom, title: custom) }
                    TextField("Add your own", text: $customActivity)
                        .submitLabel(.done)
                        .onSubmit(addCustomActivity)
                } header: {
                    Text("Main responsibilities")
                } footer: {
                    Text("Private to you. Choose up to \(ProfessionalProfile.maximumActivityCount).")
                }
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        HStack {
                            Text("Language and appearance")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Portal on iPhone and iPad follows the language and the light or dark appearance of this device.")
                }
            }
        }
        .portalList()
    }

    private func activityRow(_ activity: String, title: String) -> some View {
        let isChosen = activities.contains(activity)
        return Button {
            activities = ProfessionalProfile.toggling(activities, activity)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Chosen")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isChosen && !ProfessionalProfile.canAddActivity(to: activities))
    }

    private func addCustomActivity() {
        let text = customActivity.trimmingCharacters(in: .whitespacesAndNewlines)
        customActivity = ""
        guard !text.isEmpty, !activities.contains(text), ProfessionalProfile.canAddActivity(to: activities) else { return }
        activities.append(text)
    }

    private func load() async {
        do {
            let loaded = try await appModel.connection(for: session.account).userProfile(id: session.userId)
            profile = loaded
            name = loaded.name ?? ""
            jobRole = loaded.jobRole ?? ""
            activities = loaded.jobActivities ?? []
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    private func save() async {
        let connection = appModel.connection(for: session.account)
        let userId = session.userId
        let newName = wantedName
        let newJobRole = wantedJobRole
        let newActivities = activities
        let changesName = hasNameChange
        let changesJob = hasJobChange
        let succeeded = await actions.run(appModel: appModel, session: session) {
            if changesName { try await connection.renameUser(id: userId, name: newName) }
            if changesJob { try await connection.saveProfessionalProfile(jobRole: newJobRole, jobActivities: newActivities) }
        }
        if succeeded { dismiss() }
    }

    private static func title(of code: String) -> String {
        switch code {
        case "operations": String(localized: "Production operations")
        case "troubleshooting": String(localized: "Troubleshooting and error recovery")
        case "maintenance": String(localized: "Robot maintenance and repair")
        case "automation": String(localized: "Controls and automation engineering")
        case "commissioning": String(localized: "Commissioning and startup")
        case "integration": String(localized: "WMS and WES integration")
        case "fleet": String(localized: "Mobile robot fleet operations")
        case "fulfillment": String(localized: "Order fulfillment and accuracy")
        case "it": String(localized: "IT infrastructure and security")
        case "safety": String(localized: "Safety and compliance")
        case "improvement": String(localized: "Performance and continuous improvement")
        case "project": String(localized: "Project and rollout management")
        default: code
        }
    }
}
