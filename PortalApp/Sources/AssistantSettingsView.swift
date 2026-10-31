import PortalKit
import SwiftUI

/// AssistantSettingsView holds the person's choices about the assistant: when
/// it may start a conversation, what it files into memory, and its voice.
/// An organization's administrators also see the switches for everyone.
struct AssistantSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var speakFirst: AgentSpeakFirstSetting?
    @State private var memory: AgentMemorySetting?
    @State private var voice: AgentVoiceSetting?
    @State private var background: AgentBackgroundSetting?
    @State private var phase = LoadPhase.loading
    @State private var errorText: String?

    private var connection: Connection { appModel.connection(for: session.account) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load settings", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                form
            }
        }
        .navigationTitle("Assistant settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var form: some View {
        Form {
            PortalRows {
                if let speakFirst { speakFirstSection(speakFirst) }
                if let memory {
                    Section("Memory") {
                        Toggle(
                            "Remember my conversations",
                            isOn: Binding(
                                get: { memory.isFilingEnabledForUser == true },
                                set: { value in change { self.memory = try await connection.setMemoryFiling(isEnabled: value) } }))
                        if memory.isFilingEnabledForOrganization == false {
                            Text("Your organization has turned remembering off, so nothing is remembered whatever you choose here.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("After a conversation has been quiet for five minutes, the assistant files what matters into what it knows.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let voice, let voices = voice.speechVoices, !voices.isEmpty {
                    Section("Voice") {
                        Picker("Voice of the answers", selection: Binding(get: { voice.effectiveVoice }, set: { value in change { self.voice = try await connection.setSpeechVoice(value) } })) {
                            ForEach(voices, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    }
                }
                if let background, background.canManageOrganization == true { organizationSection(background) }
                if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
            }
        }
        .portalList()
    }

    @ViewBuilder
    private func speakFirstSection(_ setting: AgentSpeakFirstSetting) -> some View {
        Section("Starting conversations") {
            Toggle(
                "Let the assistant start a conversation",
                isOn: Binding(
                    get: { setting.isEnabledForUser == true },
                    set: { value in change { self.speakFirst = try await connection.setSpeakFirst(isEnabled: value) } }))
            if setting.isOrganizationOff {
                Text("Your organization has turned this off, so the assistant never starts a conversation whatever you choose here.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("It does this rarely, at most once a day, and only when you are using the app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(AgentSpeakFirstSetting.switchableReasons, id: \.self) { reason in
                Toggle(
                    TurnEndText.speakFirstSwitchTitle(reason),
                    isOn: Binding(
                        get: { setting.isReasonEnabled(reason) },
                        set: { value in change { self.speakFirst = try await connection.setSpeakFirstReason(reason, isEnabled: value) } }))
            }
            Toggle(
                "Pause for 24 hours",
                isOn: Binding(
                    get: { setting.isSnoozed },
                    set: { value in change { self.speakFirst = try await connection.snoozeSpeakFirst(isSnoozed: value) } }))
        }
        .disabled(setting.isOrganizationOff)
    }

    @ViewBuilder
    private func organizationSection(_ setting: AgentBackgroundSetting) -> some View {
        Section("Your organization") {
            Toggle(
                "Goals",
                isOn: Binding(get: { setting.areGoalsEnabled == true }, set: { value in change { self.background = try await connection.setBackgroundSetting(areGoalsEnabled: value) } }))
            Toggle(
                "Ideas the assistant finds",
                isOn: Binding(
                    get: { setting.areFoundIdeasEnabled == true }, set: { value in change { self.background = try await connection.setBackgroundSetting(areFoundIdeasEnabled: value) } }))
            Toggle(
                "The assistant may start a conversation",
                isOn: Binding(
                    get: { setting.isSpeakFirstEnabled == true }, set: { value in change { self.background = try await connection.setBackgroundSetting(isSpeakFirstEnabled: value) } }))
        }
    }

    private func load() async {
        let connection = connection
        do {
            speakFirst = try? await connection.speakFirstSetting()
            memory = try? await connection.memorySetting()
            voice = try? await connection.voiceSetting()
            background = try? await connection.backgroundSetting()
            if speakFirst == nil, memory == nil, voice == nil {
                // None of them answered: say so rather than show an empty form.
                _ = try await connection.me()
            }
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            phase = .failed(error.userMessage)
        }
    }

    private func change(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                errorText = nil
            } catch {
                errorText = error.userMessage
                appModel.handle(error, account: session.account)
            }
        }
    }
}

extension TurnEndText {
    static func speakFirstSwitchTitle(_ reason: String) -> LocalizedStringKey {
        switch reason {
        case "goal_needs_you": "When a goal needs me"
        case "memory_check": "To check what it remembers"
        case "idea": "To share an idea"
        default: LocalizedStringKey(reason)
        }
    }
}
