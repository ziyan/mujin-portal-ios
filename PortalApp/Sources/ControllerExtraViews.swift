import PortalKit
import SwiftUI

/// The sections of a controller's page below its status: its alarms, orchestrators, robots, last 24 hours, incidents and the
/// progress of copying it to Portal, then what the viewer may change, each shown only when allowed. They are built here as part
/// of the page's own list, not as a view of their own: a list draws a custom view as one row, which left a blank row behind.
extension ControllerDetailView {
    @ViewBuilder
    var extraSections: some View {
        Group {
            if let telemetry, telemetry.machinesTotal > 0 {
                Section("Last 24 hours") {
                    StatGrid {
                        StatTile(label: "Picked parts", value: telemetry.pickedParts.formatted(), detail: "\(telemetry.pickOperations) pick operations", symbol: "shippingbox")
                        StatTile(label: "Error rate", value: telemetry.errorRateText(), detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            if !alarms.isEmpty {
                Section("Active alarms") { ForEach(alarms) { SiteRows.alarm($0) } }
            }
            if let rows = orchestrators?.list, !rows.isEmpty {
                Section("Orchestrators") {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.orchestratorId ?? "").foregroundStyle(.primary)
                            Text([row.runStatus, row.processStatus].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                .font(.footnote).foregroundStyle(row.hasError == true ? Color.statusError : Color.secondary)
                        }
                    }
                }
            }
            if !robots.isEmpty {
                Section("Mobile robots") {
                    ForEach(robots) { robot in
                        HStack {
                            Label(robot.name, systemImage: robot.isOnline ? "checkmark.circle" : "circle.slash").foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            if let power = robot.powerLevel {
                                Text(power, format: .percent.precision(.fractionLength(0))).font(.footnote).foregroundStyle(.secondary)
                            }
                            if robot.isCharging { Image(systemName: "bolt.fill").font(.footnote).foregroundStyle(.secondary).accessibilityLabel(Text("Charging")) }
                        }
                    }
                }
            }
            if !incidents.isEmpty {
                Section("Incidents") {
                    ForEach(incidents.prefix(5)) { incident in
                        NavigationLink(value: PortalRoute.incident(incident)) { SiteRows.incident(incident) }
                    }
                }
            }
            if !tickets.isEmpty {
                Section("Tickets") {
                    ForEach(tickets.prefix(5)) { ticket in
                        NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) }
                    }
                }
            }
            if !syncProgress.isEmpty {
                Section("Copying to Portal") {
                    ForEach(syncProgress) { progress in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(progress.resourceType ?? "").foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if let pushed = progress.pushedCount, let total = progress.totalCount {
                                    Text("\(pushed.formatted()) of \(total.formatted())").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            if let fraction = progress.fraction { ProgressView(value: fraction) }
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: PortalRoute.alarmSubscriptions(controller)) {
                    Label("Alarm subscriptions", systemImage: "bell.badge").foregroundStyle(.primary)
                }
            }
            if controller.canEdit || controller.canDeleteBackups || canMove {
                Section {
                    if controller.canEdit {
                        Button { commentDraft = editedComment ?? controller.detail ?? ""; isEditingComment = true } label: { Label("Edit comment", systemImage: "pencil") }
                            .alert("Edit comment", isPresented: $isEditingComment) {
                                TextField("Comment", text: $commentDraft)
                                Button("Save") { Task { await saveComment() } }
                                Button("Cancel", role: .cancel) {}
                            }
                    }
                    if canMove {
                        Button { isMoving = true } label: { Label("Move to another site", systemImage: "arrow.right.square") }
                            .sheet(isPresented: $isMoving) { MoveControllerView(controller: controller) }
                    }
                    if controller.canEdit {
                        NavigationLink(value: PortalRoute.controllerSettings(controller)) {
                            Label("Controller settings", systemImage: "gearshape").foregroundStyle(.primary)
                        }
                    }
                    if controller.canEdit || controller.canDeleteBackups {
                        NavigationLink(value: PortalRoute.controllerBackups(controller)) {
                            Label("Backups", systemImage: "externaldrive").foregroundStyle(.primary)
                        }
                    }
                    if let errorText { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) }
                }
            }
        }
    }

    var canMove: Bool { ControllerMoveAccess.canOffer(permissions: session.profile?.me.permissions ?? []) }

    func loadExtras() async {
        let connection = appModel.connection(for: session.account)
        if let siteId = controller.siteId, !siteId.isEmpty {
            if let result = try? await connection.siteAlarms(siteId: siteId) { alarms = ControllerLive.alarms(result.alarms, controllerId: controller.id) }
            if let rows = try? await connection.siteOrchestrators(siteId: siteId) { orchestrators = ControllerLive.orchestrators(rows, controllerId: controller.id) }
            if let all = try? await connection.siteRobots(siteId: siteId) { robots = ControllerLive.robots(all, controllerId: controller.id) }
        }
        if let all = try? await connection.incidents(organizationId: controller.organizationId) { incidents = ControllerLive.incidents(all, controllerId: controller.id) }
        telemetry = try? await connection.siteTelemetry(controllerIds: [controller.id])
        tickets = (try? await connection.tickets(controllerId: controller.id, first: 20)) ?? []
        syncProgress = (try? await connection.syncProgress(controllerId: controller.id)) ?? []
    }

    func saveComment() async {
        errorText = nil
        do {
            try await appModel.connection(for: session.account).setControllerComment(id: controller.id, comment: commentDraft)
            editedComment = commentDraft
            session.cache.clear(accountKey: session.account.accountKey)
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}

/// MoveControllerView picks the site a controller is moved to, from the sites the person can see, by organization.
struct MoveControllerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let controller: ControllerSummary
    @State private var sites: [SiteSummary] = []
    @State private var organizationNames: [String: String] = [:]
    @State private var searchText = ""
    @State private var errorText: String?
    @State private var pending: SiteSummary?

    var body: some View {
        NavigationStack {
            List { PortalRows {
                if let errorText { Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) } }
                ForEach(SiteGroups.group(sites, organizationNames: organizationNames, query: searchText)) { group in
                    Section(group.organizationName ?? String(localized: "Unknown organization")) {
                        ForEach(group.sites) { site in
                            Button { pending = site } label: {
                                HStack {
                                    Text(site.name ?? site.id).foregroundStyle(Color.primary)
                                    Spacer()
                                    if site.id == controller.siteId { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } }
            .portalList()
            .navigationTitle("Move to another site")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sites")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Move this controller?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { site in
                Button("Move to \(site.name ?? site.id)") { Task { await move(to: site) } }
            }
            .task {
                let connection = appModel.connection(for: session.account)
                sites = ControllerMoveAccess.destinations((try? await connection.allSites()) ?? [], controller: controller)
                organizationNames = session.isStaff ? session.staffSites.organizationNames : session.organizationNames
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func move(to site: SiteSummary) async {
        errorText = nil
        do {
            try await appModel.connection(for: session.account).moveController(id: controller.id, toSite: site.id)
            session.cache.clear(accountKey: session.account.accountKey)
            dismiss()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}

/// ControllerBackupsView lists a controller's backups, newest first, and deletes one when the viewer may.
struct ControllerBackupsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let controller: ControllerSummary
    @State private var backups: [BackupEntry] = []
    @State private var phase = LoadPhase.loading
    @State private var deleting: BackupEntry?
    @State private var errorText: String?

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load backups", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                List { PortalRows {
                    if let errorText { Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) } }
                    if backups.isEmpty { Section { Text("No backups yet.").foregroundStyle(.secondary) } }
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(backup.shownName).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if let date = backup.date { Text(date, format: .dateTime.month().day().year().hour().minute()) }
                                if let size = backup.sizeBytes { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                                if let version = backup.sourceVersion, !version.isEmpty { Text(version) }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if controller.canDeleteBackups {
                                Button("Delete", role: .destructive) { deleting = backup }
                            }
                        }
                    }
                } }
                .portalList()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .confirmationDialog("Delete this backup?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { backup in
            Button("Delete", role: .destructive) { Task { await delete(backup) } }
        } message: { _ in
            Text("This cannot be undone.")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            backups = try await appModel.connection(for: session.account).backups(controllerId: controller.id)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if backups.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    private func delete(_ backup: BackupEntry) async {
        errorText = nil
        do {
            try await appModel.connection(for: session.account).deleteBackup(controllerId: controller.id, backupId: backup.id)
            await load()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}
