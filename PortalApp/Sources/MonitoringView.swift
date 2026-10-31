import Observation
import PortalKit
import SwiftUI

/// MonitoringModel is the first version of Monitoring for Mujin users: the
/// tickets that need a person across every organization, and the incidents
/// detected lately. The Active Monitoring board takes this place when the
/// server offers it.
@MainActor
@Observable
final class MonitoringModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var attention: [Ticket] = []
    private(set) var openCount = 0
    private(set) var incidents: [IncidentSummary] = []

    init(connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.onError = onError
    }

    func load() async {
        do {
            async let tickets = connection.tickets()
            async let recent = connection.incidents(first: 30)
            let (loadedTickets, loadedIncidents) = try await (tickets, recent)
            attention = TicketQueue.needingAttention(loadedTickets, limit: 8)
            openCount = loadedTickets.filter(\.isOpenForWork).count
            incidents = Array(SiteData.incidents(loadedIncidents, siteId: nil).prefix(10))
            phase = .loaded
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// MonitoringView is the Monitoring tab.
struct MonitoringView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var model: MonitoringModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Monitoring")
            .notificationsBell()
            .navigationDestination(for: IncidentSummary.self) { incident in
                IncidentDetailView(incident: incident)
            }
            .task {
                let monitoring = MonitoringModel(
                    connection: appModel.connection(for: session.account),
                    onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
                model = monitoring
                await monitoring.load()
                await session.loadPeople(monitoring.attention.compactMap { $0.requesterUserId ?? $0.authorUserId })
            }
        }
    }

    @ViewBuilder
    private func content(_ model: MonitoringModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load monitoring", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            List { PortalRows {
                if !session.capabilities.offersMonitoringBoard {
                    Section {
                        Label("The Active Monitoring board is not on this server yet. This is the ticket queue and recent incidents.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if model.attention.isEmpty {
                        Label("The queue is clear", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.attention) { ticket in
                        Button {
                            session.ticketToOpen = ticket.id
                            session.selectedSection = .tickets
                        } label: {
                            QueueRow(ticket: ticket)
                        }
                        .buttonStyle(.plain)
                    }
                    if model.openCount > model.attention.count {
                        Button {
                            session.selectedSection = .tickets
                        } label: {
                            Text("See all \(model.openCount) open tickets")
                        }
                    }
                } header: {
                    Text("Ticket queue")
                }
                Section("Recent incidents") {
                    if model.incidents.isEmpty {
                        Label("No incidents", systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.incidents) { incident in
                        NavigationLink(value: incident) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(incident.title ?? incident.kind ?? "")
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                VStack(alignment: .leading, spacing: 2) {
                                    if incident.needsReview {
                                        Label("Needs review", systemImage: "eye").foregroundStyle(Color.statusWarning)
                                    }
                                    HStack(spacing: 6) {
                                        if let name = session.organizationNames[incident.organizationId ?? ""] {
                                            Text(name)
                                        }
                                        if let date = incident.detectedDate {
                                            Text(date, format: .relative(presentation: .named))
                                        }
                                    }
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } }
.portalRootList()
            .refreshable { await model.load() }
        }
    }
}

private struct QueueRow: View {
    @Environment(SessionModel.self) private var session
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ticket.displayName)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if ticket.priority == "urgent" || ticket.priority == "high" {
                    Label(ticket.priority == "urgent" ? LocalizedStringKey("Urgent") : LocalizedStringKey("High priority"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusWarning)
                }
                if let name = session.organizationNames[ticket.organizationId ?? ""] { Text(name) }
                if let date = ticket.lastActivity { Text(date, format: .relative(presentation: .named)) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
