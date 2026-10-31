import Observation
import PortalKit
import SwiftUI

/// NotificationsBell is the bell in a tab's navigation bar, with the number
/// of entries not read yet.
struct NotificationsBell: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        Button {
            session.isShowingNotifications = true
        } label: {
            Label("Notifications", systemImage: session.unreadCount > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityValue(session.unreadCount > 0 ? Text("\(session.unreadCount) unread") : Text(""))
        .accessibilityIdentifier("notificationsBell")
    }
}

extension View {
    /// Puts the bell in the leading corner of the navigation bar.
    func notificationsBell() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { NotificationsBell() }
        }
    }
}

/// NotificationsModel loads the inbox.
@MainActor
@Observable
final class NotificationsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var items: [PortalNotification] = []

    init(connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.onError = onError
    }

    func load() async {
        do {
            items = try await connection.notifications()
            phase = .loaded
        } catch {
            onError(error)
            if items.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    func markRead(_ item: PortalNotification) async {
        guard item.isUnread else { return }
        do {
            try await connection.markNotificationRead(id: item.id)
            await load()
        } catch {
            onError(error)
        }
    }

    func markAllRead() async {
        do {
            try await connection.markAllNotificationsRead()
            await load()
        } catch {
            onError(error)
        }
    }
}

/// NotificationsView is the inbox, as a sheet over whichever tab is in front.
struct NotificationsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: NotificationsModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                await model?.markAllRead()
                                await session.refreshUnreadCount()
                            }
                        } label: {
                            Label("Mark all as read", systemImage: "checkmark.circle")
                        }
                        NavigationLink {
                            NotificationPreferencesView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            let inbox = NotificationsModel(
                connection: appModel.connection(for: session.account),
                onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            model = inbox
            await inbox.load()
        }
    }

    @ViewBuilder
    private func content(_ model: NotificationsModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load notifications", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing new", systemImage: "bell")
                } description: {
                    Text("Tickets, alarms and incidents that need you show up here.")
                }
            } else {
                List(model.items) { item in
                    Button {
                        open(item, model: model)
                    } label: {
                        NotificationRow(item: item)
                    }
                    .buttonStyle(.plain)
.listRowBackground(Color.portalCard)
}
.portalList()
                .refreshable { await model.load() }
            }
        }
    }

    private func open(_ item: PortalNotification, model: NotificationsModel) {
        Task {
            await model.markRead(item)
            await session.refreshUnreadCount()
        }
        switch item.target {
        case .ticket(let id):
            session.ticketToOpen = id
            session.selectedSection = .tickets
        case .incident, .site:
            session.selectedSection = session.isStaff ? .monitoring : .site
        case .chat(let conversationId):
            session.chatToOpen = conversationId
            session.assistantPart = .chats
            session.selectedSection = session.isStaff ? .assistant : .chats
        case .automations:
            session.automationsRequested = true
            session.selectedSection = .more
        case .none:
            return
        }
        dismiss()
    }
}

private struct NotificationRow: View {
    let item: PortalNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.isUnread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                sentence
                    .font(.body.weight(item.isUnread ? .semibold : .regular))
                    .foregroundStyle(.primary)
                if let detail = item.detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                if let date = item.date {
                    Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.isUnread ? Text("Not read yet") : Text(""))
    }

    @ViewBuilder
    private var sentence: some View {
        switch item.kind {
        case "ticket_comment": Text("New comment on \(item.subject)")
        case "ticket_assigned": Text("Assigned to you: \(item.subject)")
        case "ticket_mentioned": Text("You were mentioned on \(item.subject)")
        case "ticket_lifecycle": Text("Status changed on \(item.subject)")
        case "ticket_activity": Text("Activity on \(item.subject)")
        case "incident": Text("Incident: \(item.subject)")
        case "alarm": Text("Alarm: \(item.subject)")
        case "chat_message": Text(item.subject)
        case "budget_alert": Text("Your budget needs attention")
        case "agent_job_failed":
            if item.isAgentJobPaused == true {
                Text("Your job \(item.subject) was paused after repeated failures.")
            } else {
                Text("A run of your job \(item.subject) failed.")
            }
        default: Text(item.subject)
        }
    }
}

/// NotificationPreferencesView chooses which kinds of notification reach
/// the phone and the inbox box, and which are mailed.
struct NotificationPreferencesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var preferences = NotificationPreferences()
    @State private var isLoaded = false
    @State private var errorText: String?

    var body: some View {
        Form { PortalRows {
            Section {
                Text("Notifications always show in the app. Choose which ones also reach this phone, and which are mailed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(NotificationPreferences.kinds, id: \.self) { kind in
                Section(Self.title(kind)) {
                    Toggle("Push", isOn: binding(kind: kind, channel: "push"))
                    Toggle("Email", isOn: binding(kind: kind, channel: "email"))
                    if kind == "agent_job_failed" {
                        Text("Push is not delivered for this one yet.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(Color.statusError) }
            }
        } }
.portalList()
        .navigationTitle("Notification settings")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(!isLoaded)
        .task {
            do {
                preferences = try await appModel.connection(for: session.account).notificationPreferences()
            } catch {
                errorText = error.userMessage
            }
            isLoaded = true
        }
    }

    private func binding(kind: String, channel: String) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(kind: kind, channel: channel) },
            set: { newValue in
                let before = preferences
                preferences.set(kind: kind, channel: channel, isEnabled: newValue)
                Task {
                    do {
                        try await appModel.connection(for: session.account).setNotificationPreference(kind: kind, channel: channel, isEnabled: newValue)
                        errorText = nil
                    } catch {
                        preferences = before
                        errorText = error.userMessage
                    }
                }
            })
    }

    static func title(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case "ticket_comment": "Comments on tickets"
        case "ticket_assigned": "Tickets assigned to me"
        case "ticket_mentioned": "Mentions"
        case "ticket_lifecycle": "Ticket status changes"
        case "ticket_activity": "Other ticket activity"
        case "incident": "Incidents"
        case "alarm": "Alarms"
        case "budget_alert": "Budget alerts"
        case "agent_job_failed": "Failed assistant jobs"
        case "chat_message": "Chat messages"
        default: LocalizedStringKey(kind)
        }
    }
}
