import PortalKit
import SwiftUI

/// ControllerSettingsView sets how often a controller is copied to Portal and backed up, for those who may edit it.
struct ControllerSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let controller: ControllerSummary

    @State private var settings = ControllerSettings()
    @State private var phase = LoadPhase.loading
    @State private var errorText: String?

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load settings", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                List { PortalRows {
                    if let errorText { Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) } }
                    Section("Copy to Portal") {
                        Toggle("Copy to Portal", isOn: Binding(get: { settings.isSyncEnabled ?? false }, set: { value in
                            settings.isSyncEnabled = value
                            Task { await saveSync() }
                        }))
                        intervalPicker(seconds: settings.syncIntervalSeconds) { value in
                            settings.syncIntervalSeconds = value
                            Task { await saveSync() }
                        }
                    }
                    Section("Backups") {
                        Toggle("Back up", isOn: Binding(get: { settings.isBackupEnabled ?? false }, set: { value in
                            settings.isBackupEnabled = value
                            Task { await saveBackup() }
                        }))
                        intervalPicker(seconds: settings.backupIntervalSeconds) { value in
                            settings.backupIntervalSeconds = value
                            Task { await saveBackup() }
                        }
                    }
                } }
                .portalList()
                .disabled(!controller.canEdit)
            }
        }
        .navigationTitle("Controller settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await load() }
    }

    private func intervalPicker(seconds: Int64?, set: @escaping (Int64) -> Void) -> some View {
        Picker("Every", selection: Binding(get: { ControllerSettings.nearestChoice(to: seconds) }, set: set)) {
            ForEach(ControllerSettings.intervalChoices, id: \.self) { value in
                Text(Duration.seconds(value).formatted(.units(allowed: [.weeks, .days, .hours, .minutes], width: .wide, maximumUnitCount: 1))).tag(value)
            }
        }
    }

    private func load() async {
        do {
            settings = try await appModel.connection(for: session.account).controllerSettings(id: controller.id)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    private func saveSync() async {
        await save { try await $0.setSyncSettings(id: controller.id, isEnabled: settings.isSyncEnabled ?? false, intervalSeconds: ControllerSettings.nearestChoice(to: settings.syncIntervalSeconds)) }
    }

    private func saveBackup() async {
        await save { try await $0.setBackupSettings(id: controller.id, isEnabled: settings.isBackupEnabled ?? false, intervalSeconds: ControllerSettings.nearestChoice(to: settings.backupIntervalSeconds)) }
    }

    private func save(_ change: (Connection) async throws -> Void) async {
        errorText = nil
        do {
            try await change(appModel.connection(for: session.account))
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
            await load()
        }
    }
}
