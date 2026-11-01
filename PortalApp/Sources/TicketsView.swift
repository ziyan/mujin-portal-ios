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

    let cache: ResponseCache?
    let accountKey: String

    init(connection: Connection, organizationId: String?, cache: ResponseCache? = nil, accountKey: String = "", onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.organizationId = organizationId
        self.cache = cache
        self.accountKey = accountKey
        self.onError = onError
    }

    private var cacheKey: CacheKey { CacheKey(accountKey: accountKey, name: "tickets", variables: organizationId ?? "") }

    /// Shows what is held at once and reads again only when it is old, or when pulled to refresh (`force`).
    func load(force: Bool = false) async {
        if let cache, let held = cache.hit(cacheKey, as: [Ticket].self) {
            tickets = held.value
            phase = .loaded
            if held.isFresh && !force { return }
        }
        do {
            tickets = try await connection.tickets(organizationId: organizationId)
            cache?.store(tickets, for: cacheKey)
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
    @State private var path: [PortalRoute] = ["ticket", "attachment-viewer"].contains(DemoOptions.screen ?? "") ? [.ticket(id: "ticket01")] : []
    @State private var isCreating = false

    var body: some View {
        if embedsNavigation {
            NavigationStack(path: $path) { screen.portalDestinations() }
        } else {
            screen
        }
    }

    private var screen: some View {
        VStack(spacing: 0) {
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
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreating = true
                } label: {
                    Label("New ticket", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("newTicketButton")
            }
        }
        .onChange(of: session.ticketToOpen, initial: true) { _, ticketId in
            guard let ticketId else { return }
            session.ticketToOpen = nil
            path.append(.ticket(id: ticketId))
        }
        .sheet(isPresented: $isCreating) {
            TicketCreateView { ticketId in
                // The new ticket joins the cached list from its own result; the list is not read again.
                session.cache.remove(CacheKey(accountKey: session.account.accountKey, name: "tickets", variables: organizationId ?? ""))
                path.append(.ticket(id: ticketId))
                Task { await model?.load(force: true) }
            }
        }
        .task(id: organizationId) {
            let ticketsModel = session.ticketsModel(for: organizationId)
            model = ticketsModel
            if session.isStaff { scope = .everyone }
            if appModel.isDemo, let screen = DemoOptions.screen, screen.hasPrefix("tickets") {
                if screen.hasSuffix("solved") { tab = .solved }
                if screen.hasSuffix("everyone") { scope = .everyone }
            }
            await ticketsModel.load()
            await session.loadPeople(ticketsModel.tickets.flatMap { [$0.requesterUserId, $0.authorUserId].compactMap { $0 } })
        }
    }

    /// The filter: whose tickets and which status, as lists with checkmarks.
    /// The default is the useful view: the person's own, and open.
    private var filterMenu: some View {
        Menu {
            Picker("Whose tickets", selection: $scope) {
                Text("Mine").tag(TicketScope.mine)
                Text(session.isStaff ? LocalizedStringKey("Queue") : LocalizedStringKey("My organization")).tag(TicketScope.everyone)
            }
            .pickerStyle(.inline)
            Picker("Status", selection: $tab) {
                Text("Open").tag(TicketTab.open)
                Text("Solved").tag(TicketTab.solved)
                Text("Closed").tag(TicketTab.closed)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: (scope == .mine && tab == .open) ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("ticketFilterButton")
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
                    NavigationLink(value: PortalRoute.ticket(id: ticket.id)) {
                        TicketRow(ticket: ticket)
                    }
.listRowBackground(Color.portalCard)
}
.portalRootList()
                .refreshable { await model.load(force: true) }
            }
        }
    }
}

struct TicketRow: View {
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
                    .foregroundStyle(Color.statusWarning)
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
