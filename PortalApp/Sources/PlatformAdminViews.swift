import PortalKit
import SwiftUI

// MARK: registrations

/// RegistrationsView is the queue of requests to start an organization. A platform administrator reads it here; approving one
/// creates the organization, which the app is not allowed to do, so that part opens on the web.
struct RegistrationsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var filter = RegistrationFilter.pending
    @State private var phase = LoadPhase.loading
    @State private var registrations: [OrganizationRegistration] = []

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load registrations", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Registrations")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: filter) { await load() }
        .onChange(of: appModel.presentedWeb == nil) { _, isClosed in
            if isClosed { Task { await load() } }
        }
    }

    private var list: some View {
        List {
            PortalRows {
                Section {
                    Picker("Show", selection: $filter) {
                        Text("Waiting").tag(RegistrationFilter.pending)
                        Text("Approved").tag(RegistrationFilter.approved)
                        Text("Rejected").tag(RegistrationFilter.rejected)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("registrationFilter")
                }
                if registrations.isEmpty {
                    Section { Text(emptyMessage).foregroundStyle(Color.secondary) }
                } else {
                    Section {
                        ForEach(registrations) { registration in
                            NavigationLink {
                                RegistrationView(registration: registration) { await load() }
                            } label: {
                                RegistrationRow(registration: registration)
                            }
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private var emptyMessage: LocalizedStringKey {
        switch filter {
        case .pending: return "No one is waiting for approval."
        case .approved: return "No registration has been approved yet."
        case .rejected: return "No registration has been rejected."
        }
    }

    private func load() async {
        do {
            registrations = try await appModel.connection(for: session.account).organizationRegistrations(status: filter)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

private struct RegistrationRow: View {
    let registration: OrganizationRegistration

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(registration.shownName)
                .foregroundStyle(Color.primary)
            if let email = registration.email, !email.isEmpty {
                Text(email)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if let when = AccountText.relative(registration.createdAt) {
                Text("Asked \(when)")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// RegistrationView is one request: who asked, and the two ways to decide it.
struct RegistrationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let registration: OrganizationRegistration
    let onChanged: () async -> Void

    @State private var isConfirmingRejection = false
    @State private var actions = ActionState()

    var body: some View {
        List {
            PortalRows {
                Section {
                    fact("Organization", registration.shownName)
                    if let email = registration.email, !email.isEmpty { fact("Email", email) }
                    if let country = registration.country, !country.isEmpty { fact("Country", country) }
                    if let when = registration.createdDate { fact("Asked", when.formatted(date: .abbreviated, time: .shortened)) }
                    fact("Status", localizedWords(registration.statusName))
                }
                if registration.isPending {
                    Section {
                        PlatformWebRow(title: "Approve on the web", path: "/settings/registrations")
                    } footer: {
                        Text("Approving creates the organization, which the app is not allowed to do. It opens in Portal on the web, signed in as you.")
                    }
                    Section {
                        Button(role: .destructive) {
                            isConfirmingRejection = true
                        } label: {
                            Text("Reject")
                                .foregroundStyle(Color.statusError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Reject this request?", isPresented: $isConfirmingRejection, titleVisibility: .visible) {
                            Button("Reject", role: .destructive) { Task { await reject() } }
                        } message: {
                            Text("\(registration.shownName) will not get an organization.")
                        }
                    }
                }
            }
        }
        .portalList()
        .navigationTitle(registration.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .failureAlert(actions)
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            Text(value)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func reject() async {
        let connection = appModel.connection(for: session.account)
        let identifier = registration.id
        if await actions.run(appModel: appModel, session: session, { try await connection.rejectOrganizationRegistration(id: identifier, reason: "") }) {
            await onChanged()
            dismiss()
        }
    }
}

// MARK: incident alerts

struct IncidentAlertsSnapshot: Sendable {
    let alerts: [IncidentAlert]
    let sites: [SiteSummary]
}

/// IncidentAlertsView is the sites whose incidents the person is told about, and from what detector confidence.
struct IncidentAlertsView: View {
    var body: some View {
        PlatformPage(
            title: "Incident alerts", failureTitle: "Could not load incident alerts",
            load: { (connection: Connection) -> IncidentAlertsSnapshot in
                async let alerts = connection.incidentAlerts()
                async let sites = connection.sites()
                return IncidentAlertsSnapshot(alerts: try await alerts, sites: try await sites)
            }
        ) { snapshot, reload in
            IncidentAlertsList(snapshot: snapshot, reload: reload)
        }
    }
}

private struct IncidentAlertsList: View {
    @Environment(SessionModel.self) private var session
    let snapshot: IncidentAlertsSnapshot
    let reload: PageReload

    @State private var editing: IncidentAlertEdit?

    private func siteName(_ alert: IncidentAlert) -> String {
        let name = snapshot.sites.first { $0.id == alert.siteId }?.name ?? session.siteNames[alert.siteId ?? ""]
        return (name ?? "").isEmpty ? String(localized: "Unknown site") : name!
    }

    private func floorWords(_ alert: IncidentAlert) -> String {
        alert.minimumConfidence == nil ? String(localized: "Every incident") : alert.floorText
    }

    private var sitesWithoutAlert: [SiteSummary] {
        let taken = Set(snapshot.alerts.compactMap(\.siteId))
        return snapshot.sites.filter { !taken.contains($0.id) }
    }

    var body: some View {
        List {
            PortalRows {
                if snapshot.alerts.isEmpty {
                    Section {
                        Text("You are not told about the incidents of any site.").foregroundStyle(Color.secondary)
                    } footer: {
                        Text("Add a site to be notified when an incident is detected there.")
                    }
                } else {
                    Section {
                        ForEach(snapshot.alerts) { alert in
                            Button {
                                editing = IncidentAlertEdit(alert: alert, siteName: siteName(alert))
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(siteName(alert))
                                            .foregroundStyle(Color.primary)
                                        Text(alert.isEnabled == false ? String(localized: "Paused") : String(localized: "From \(floorWords(alert))"))
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color(.tertiaryLabel))
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("A site is watched from the confidence shown. Paused sites tell you nothing.")
                    }
                }
            }
        }
        .portalList()
        .refreshable { await reload() }
        .toolbar {
            if !sitesWithoutAlert.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = IncidentAlertEdit(alert: nil, siteName: "") } label: { Label("Add a site", systemImage: "plus") }
                }
            }
        }
        .sheet(item: $editing) { edit in
            IncidentAlertSheet(edit: edit, siteChoices: sitesWithoutAlert) { await reload() }
        }
    }
}

private struct IncidentAlertEdit: Identifiable {
    let alert: IncidentAlert?
    let siteName: String
    var id: String { alert?.id ?? "new" }
}

private struct IncidentAlertSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let edit: IncidentAlertEdit
    let siteChoices: [SiteSummary]
    let onSaved: () async -> Void

    @State private var siteId = ""
    @State private var percentText = ""
    @State private var isEnabled = true
    @State private var isConfirmingRemoval = false
    @State private var actions = ActionState()

    private var isNew: Bool { edit.alert == nil }
    private var canSave: Bool { IncidentAlerts.isValid(percentText: percentText) && !(isNew && siteId.isEmpty) && !actions.isWorking }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section {
                        if isNew {
                            Picker("Site", selection: $siteId) {
                                ForEach(siteChoices) { site in Text(site.name ?? site.id).tag(site.id) }
                            }
                        } else {
                            LabeledContent("Site") { Text(edit.siteName).foregroundStyle(Color.secondary) }
                        }
                        Toggle("Tell me", isOn: $isEnabled)
                    }
                    Section {
                        TextField("Every incident", text: $percentText)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Lowest confidence, in percent")
                    } footer: {
                        Text("The detector rates each incident from 0 to 100. Leave empty to hear about every one.")
                    }
                    if !isNew {
                        Section {
                            Button(role: .destructive) {
                                isConfirmingRemoval = true
                            } label: {
                                Text("Stop alerts for this site")
                                    .foregroundStyle(Color.statusError)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("Stop these alerts?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                                Button("Stop alerts", role: .destructive) { Task { await remove() } }
                            }
                        }
                    }
                }
            }
            .portalList()
            .navigationTitle(isNew ? LocalizedStringKey("Add a site") : LocalizedStringKey("Incident alert"))
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
                siteId = edit.alert?.siteId ?? siteChoices.first?.id ?? ""
                percentText = IncidentAlerts.percentText(edit.alert?.minimumConfidence)
                isEnabled = edit.alert?.isEnabled != false
            }
            .failureAlert(actions)
        }
    }

    private func save() async {
        let connection = appModel.connection(for: session.account)
        let site = edit.alert?.siteId ?? siteId
        let floor = IncidentAlerts.floor(fromPercentText: percentText)
        let enabled = isEnabled
        if await actions.run(appModel: appModel, session: session, { try await connection.setIncidentAlert(siteId: site, minimumConfidence: floor, isEnabled: enabled) }) {
            await onSaved()
            dismiss()
        }
    }

    private func remove() async {
        let connection = appModel.connection(for: session.account)
        guard let site = edit.alert?.siteId else { return }
        if await actions.run(appModel: appModel, session: session, { try await connection.removeIncidentAlert(siteId: site) }) {
            await onSaved()
            dismiss()
        }
    }
}
