import Observation
import PortalKit
import SwiftUI

/// TicketsModel loads the tickets of one list: the person's own, or for a
/// Mujin user the queue across organizations, or one organization's.
@MainActor
@Observable
final class TicketsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let organizationId: String?
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var tickets: [Ticket] = []

    init(connection: Connection, organizationId: String?, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.organizationId = organizationId
        self.onError = onError
    }

    func load() async {
        do {
            tickets = try await connection.tickets(organizationId: organizationId)
            phase = .loaded
        } catch {
            onError(error)
            if tickets.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

/// TicketsView is a list of tickets with the person's choice of scope and
/// status, and a way to open one. It is the Tickets tab, and the tickets of
/// one organization for a Mujin user.
struct TicketsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    /// Limits the list to one organization; nil is everything the person may see.
    var organizationId: String?
    var embedsNavigation = true

    @State private var model: TicketsModel?
    @State private var scope = TicketScope.mine
    @State private var tab = TicketTab.open
    @State private var path: [String] = DemoOptions.screen == "ticket" ? ["ticket01"] : []
    @State private var isCreating = false

    var body: some View {
        if embedsNavigation {
            NavigationStack(path: $path) { screen }
        } else {
            screen
        }
    }

    private var screen: some View {
        VStack(spacing: 0) {
            controls
            if let model {
                content(model)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .navigationTitle("Tickets")
        .notificationsBell()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreating = true
                } label: {
                    Label("New ticket", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("newTicketButton")
            }
        }
        .navigationDestination(for: String.self) { ticketId in
            TicketDetailView(ticketId: ticketId)
        }
        .onChange(of: session.ticketToOpen, initial: true) { _, ticketId in
            guard let ticketId else { return }
            session.ticketToOpen = nil
            path.append(ticketId)
        }
        .sheet(isPresented: $isCreating) {
            TicketCreateView { ticketId in path.append(ticketId) }
        }
        .task(id: organizationId) {
            let ticketsModel = TicketsModel(
                connection: appModel.connection(for: session.account), organizationId: organizationId,
                onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            model = ticketsModel
            if session.isStaff && organizationId == nil { scope = .everyone }
            if appModel.isDemo, let screen = DemoOptions.screen, screen.hasPrefix("tickets") {
                if screen.hasSuffix("solved") { tab = .solved }
                if screen.hasSuffix("everyone") { scope = .everyone }
            }
            await ticketsModel.load()
            await session.loadPeople(ticketsModel.tickets.flatMap { [$0.requesterUserId, $0.authorUserId].compactMap { $0 } })
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Whose tickets", selection: $scope) {
                Text("Mine").tag(TicketScope.mine)
                Text(session.isStaff ? LocalizedStringKey("Queue") : LocalizedStringKey("My organization")).tag(TicketScope.everyone)
            }
            .pickerStyle(.segmented)
            Picker("Status", selection: $tab) {
                Text("Open").tag(TicketTab.open)
                Text("Solved").tag(TicketTab.solved)
                Text("Closed").tag(TicketTab.closed)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func content(_ model: TicketsModel) -> some View {
        switch model.phase {
        case .loading:
            Spacer()
            ProgressView()
            Spacer()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load tickets", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            let shown = TicketFilter.apply(model.tickets, tab: tab, scope: scope, userId: session.userId)
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("No tickets here", systemImage: "tray")
                } description: {
                    Text(tab == .open ? LocalizedStringKey("Nothing is waiting. Tap the pencil to open a ticket.") : LocalizedStringKey("Nothing in this list."))
                }
            } else {
                List(shown) { ticket in
                    NavigationLink(value: ticket.id) {
                        TicketRow(ticket: ticket)
                    }
                }
                .refreshable { await model.load() }
            }
        }
    }
}

private struct TicketRow: View {
    @Environment(SessionModel.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let sequence = ticket.sequence {
                    Text("#\(sequence)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let date = ticket.lastActivity {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(ticket.title ?? "")
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if ticket.priority == "high" || ticket.priority == "urgent" {
                Label(ticket.priority == "urgent" ? LocalizedStringKey("Urgent") : LocalizedStringKey("High priority"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    /// Who asked, where, and what stage it is at.
    private var subtitle: String {
        var parts = [session.name(ofPerson: ticket.requesterUserId ?? ticket.authorUserId)]
        if session.isStaff, let name = session.organizationNames[ticket.organizationId ?? ""], !name.isEmpty { parts.append(name) }
        if let name = session.siteNames[ticket.siteId ?? ""], !name.isEmpty { parts.append(name) }
        if let status = ticket.status, status != "open" { parts.append(TicketText.status(status)) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// TicketText words the fixed vocabularies of a ticket.
enum TicketText {
    static func status(_ status: String) -> String {
        switch status {
        case "new": String(localized: "New")
        case "open": String(localized: "Open")
        case "pending": String(localized: "Pending")
        case "hold": String(localized: "On hold")
        case "solved": String(localized: "Solved")
        case "closed": String(localized: "Closed")
        default: status
        }
    }

    static func priority(_ priority: String) -> String {
        switch priority {
        case "low": String(localized: "Low")
        case "normal": String(localized: "Normal")
        case "high": String(localized: "High")
        case "urgent": String(localized: "Urgent")
        default: priority
        }
    }
}
