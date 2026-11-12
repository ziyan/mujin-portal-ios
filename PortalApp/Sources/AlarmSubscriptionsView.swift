import PortalKit
import SwiftUI

/// AlarmSubscriptionsView lists the person's alarm subscriptions, switches one on or off, deletes one, and makes one for this controller.
struct AlarmSubscriptionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    /// The controller or virtual controller the page is for; exactly one is set.
    let controllerId: String?
    let virtualControllerId: String?
    let name: String

    init(controller: ControllerSummary) {
        controllerId = controller.id
        virtualControllerId = nil
        name = controller.displayName
    }

    init(virtual: VirtualControllerSummary) {
        controllerId = nil
        virtualControllerId = virtual.id
        name = virtual.displayName
    }

    private func covers(_ subscription: AlarmSubscription) -> Bool {
        if let controllerId { return subscription.covers(controllerId: controllerId) }
        if let virtualControllerId { return subscription.covers(virtualControllerId: virtualControllerId) }
        return false
    }
    @State private var subscriptions: [AlarmSubscription] = []
    @State private var phase = LoadPhase.loading
    @State private var errorText: String?
    @State private var isCreating = false
    @State private var newLevel = "error"
    @State private var deleting: AlarmSubscription?

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load alarm subscriptions", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                List { PortalRows {
                    if let errorText { Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) } }
                    Section {
                        if subscriptions.isEmpty { Text("You are not subscribed to any alarms.").foregroundStyle(.secondary) }
                        ForEach(subscriptions) { subscription in
                            Toggle(isOn: Binding(get: { subscription.isEnabled ?? true }, set: { value in Task { await set(subscription, isEnabled: value) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subscription.shownName).foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text(LocalizedStringKey((subscription.minimumAlarmLevel ?? "error").capitalized))
                                        if covers(subscription) { Text("This one") }
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions { Button("Delete", role: .destructive) { deleting = subscription } }
                        }
                    }
                    Section {
                        Button { isCreating = true } label: { Label("Subscribe to alarms here", systemImage: "bell.badge") }
                    }
                } }
                .portalList()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Alarm subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenCompact()
        .confirmationDialog("Notify me about alarms from", isPresented: $isCreating, titleVisibility: .visible) {
            ForEach(AlarmSubscription.levels, id: \.self) { level in
                Button(level.capitalized) { Task { await create(level: level) } }
            }
        }
        .confirmationDialog("Delete this subscription?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { subscription in
            Button("Delete", role: .destructive) { Task { await delete(subscription) } }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            subscriptions = try await appModel.connection(for: session.account).alarmSubscriptions()
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if subscriptions.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    private func create(level: String) async {
        await run { try await $0.createAlarmSubscription(name: name, minimumAlarmLevel: level, controllerIds: controllerId.map { [$0] } ?? [], virtualControllerIds: virtualControllerId.map { [$0] } ?? []) }
    }

    private func set(_ subscription: AlarmSubscription, isEnabled: Bool) async {
        await run { try await $0.setAlarmSubscription(id: subscription.id, isEnabled: isEnabled) }
    }

    private func delete(_ subscription: AlarmSubscription) async {
        await run { try await $0.deleteAlarmSubscription(id: subscription.id) }
    }

    private func run(_ change: (Connection) async throws -> Void) async {
        errorText = nil
        do {
            try await change(appModel.connection(for: session.account))
            await load()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}
