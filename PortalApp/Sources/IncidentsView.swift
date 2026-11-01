import Observation
import PortalKit
import SwiftUI

/// IncidentsModel is the recent incidents across the organizations a Mujin user can see.
@MainActor
@Observable
final class IncidentsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var incidents: [IncidentSummary] = []

    init(connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.onError = onError
    }

    func load() async {
        do {
            incidents = Array(SiteData.incidents(try await connection.incidents(first: 50), siteId: nil).prefix(30))
            phase = .loaded
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// IncidentsView is the list of recent incidents under More, for Mujin users. Each opens its detail.
struct IncidentsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var model: IncidentsModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Incidents")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let incidents = model ?? IncidentsModel(
                connection: appModel.connection(for: session.account),
                onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            model = incidents
            await incidents.load()
        }
    }

    @ViewBuilder
    private func content(_ model: IncidentsModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load incidents", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            List { PortalRows {
                if model.incidents.isEmpty {
                    Label("No incidents", systemImage: "checkmark.shield").foregroundStyle(.secondary)
                }
                ForEach(model.incidents) { incident in
                    NavigationLink(value: PortalRoute.incident(incident)) {
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
            } }
            .portalList()
            .refreshable { await model.load() }
        }
    }
}
