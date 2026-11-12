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
    @AppStorage(AssistantDisplay.showWorkingNotesKey) private var showToolCallDetails = false

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
                Section {
                    Toggle(isOn: $showToolCallDetails) {
                        Label("Show tool call details", systemImage: "list.bullet.rectangle").foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("showToolCallDetailsToggle")
                } footer: {
                    Text("Shows a \"What it did\" row under each answer with a short note for every step the assistant took.")
                }
                if let speakFirst { speakFirstSection(speakFirst) }
                if let memory {
                    Section("Memory") {
                        Toggle(
                            isOn: Binding(
                                get: { memory.isFilingEnabledForUser == true },
                                set: { value in change { self.memory = try await connection.setMemoryFiling(isEnabled: value) } })
                        ) { Label("Remember my conversations", systemImage: "brain.head.profile").foregroundStyle(.primary) }
                        if memory.isFilingEnabledForOrganization == false {
                            Text("Your organization has turned remembering off, so nothing is remembered whatever you choose here.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let voice, let voices = voice.speechVoices, !voices.isEmpty {
                    Section("Voice") {
                        Picker(selection: Binding(get: { voice.effectiveVoice }, set: { value in change { self.voice = try await connection.setSpeechVoice(value) } })) {
                            ForEach(voices, id: \.self) { Text($0.capitalized).tag($0) }
                        } label: { Label("Voice of the answers", systemImage: "speaker.wave.2").foregroundStyle(.primary) }
                    }
                }
                // What an organization allows is for its administrators, on a screen of its own.
                if let background, background.canManageOrganization == true {
                    Section {
                        NavigationLink {
                            OrganizationAssistantSettingsView(initial: background)
                        } label: {
                            Label("Your organization", systemImage: "building.2").foregroundStyle(.primary)
                        }
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
            }
        }
        .portalList()
    }

    @ViewBuilder
    private func speakFirstSection(_ setting: AgentSpeakFirstSetting) -> some View {
        Section("Starting conversations") {
            Toggle(
                isOn: Binding(
                    get: { setting.isEnabledForUser == true },
                    set: { value in change { self.speakFirst = try await connection.setSpeakFirst(isEnabled: value) } })
            ) { Label("Let the assistant start a conversation", systemImage: "sparkles").foregroundStyle(.primary) }
            if setting.isOrganizationOff {
                Text("Your organization has turned this off, so the assistant never starts a conversation whatever you choose here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(AgentSpeakFirstSetting.switchableReasons, id: \.self) { reason in
                Toggle(
                    isOn: Binding(
                        get: { setting.isReasonEnabled(reason) },
                        set: { value in change { self.speakFirst = try await connection.setSpeakFirstReason(reason, isEnabled: value) } })
                ) { Label(TurnEndText.speakFirstSwitchTitle(reason), systemImage: "arrow.turn.down.right").foregroundStyle(.primary) }
            }
            Toggle(
                isOn: Binding(
                    get: { setting.isSnoozed },
                    set: { value in change { self.speakFirst = try await connection.snoozeSpeakFirst(isSnoozed: value) } })
            ) { Label("Pause for 24 hours", systemImage: "moon.zzz").foregroundStyle(.primary) }
        }
        .disabled(setting.isOrganizationOff)
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
        case "memory_check": "Memory check-ins"
        case "idea": "Ideas"
        default: LocalizedStringKey(reason)
        }
    }
}

/// OrganizationAssistantSettingsView is what an organization allows its people: goals, found ideas and the assistant starting a conversation.
struct OrganizationAssistantSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let initial: AgentBackgroundSetting
    @State private var setting: AgentBackgroundSetting?
    @State private var errorText: String?

    var body: some View {
        let current = setting ?? initial
        Form {
            PortalRows {
                Section {
                    Toggle(isOn: Binding(get: { current.areGoalsEnabled == true }, set: { value in change { try await $0.setBackgroundSetting(areGoalsEnabled: value) } })) {
                        Label("Goals", systemImage: "scope").foregroundStyle(.primary)
                    }
                    Toggle(isOn: Binding(get: { current.areFoundIdeasEnabled == true }, set: { value in change { try await $0.setBackgroundSetting(areFoundIdeasEnabled: value) } })) {
                        Label("Ideas the assistant finds", systemImage: "lightbulb").foregroundStyle(.primary)
                    }
                    Toggle(isOn: Binding(get: { current.isSpeakFirstEnabled == true }, set: { value in change { try await $0.setBackgroundSetting(isSpeakFirstEnabled: value) } })) {
                        Label("The assistant may start a conversation", systemImage: "sparkles").foregroundStyle(.primary)
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
            }
        }
        .portalList()
        .navigationTitle("Your organization")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func change(_ action: @escaping (Connection) async throws -> AgentBackgroundSetting) {
        Task {
            do {
                setting = try await action(appModel.connection(for: session.account))
                errorText = nil
            } catch {
                errorText = error.userMessage
                appModel.handle(error, account: session.account)
            }
        }
    }
}

/// AssistantDisplay is how much of the assistant's work this device shows. The "What it did" rows are off until the person turns
/// them on, as on the web, where the same switch is called "Show tool call details".
enum AssistantDisplay {
    static let showWorkingNotesKey = "showToolCallDetails"
}
