import PortalKit
import SwiftUI

/// AssistantCall is a call with the assistant: its conversation, which hears the answers, and the voice that carries the call. The
/// session holds it while it goes, so the call outlives the screen it started on.
@MainActor
final class AssistantCall {
    let conversationId: String
    let model: ConversationModel
    let voice: VoiceCallController

    init(conversationId: String, model: ConversationModel, voice: VoiceCallController) {
        self.conversationId = conversationId
        self.model = model
        self.voice = voice
    }

    /// Whether the call is still going or being set up.
    var isGoing: Bool { voice.isActive || voice.phase != .idle }

    /// Hangs up from the bar, where no screen is left to stop the conversation's live feed.
    func end() {
        voice.end()
        model.stop()
    }
}

/// AssistantCallBar is the call with the assistant while its conversation is not on screen: what it is doing, mute, hang up, and a tap
/// anywhere else to go back to the conversation. It sits where the bar of a call with people does.
struct AssistantCallBar: View {
    @Environment(SessionModel.self) private var session
    let call: AssistantCall

    var body: some View {
        HStack(spacing: 10) {
            Button { session.open(.conversation(id: call.conversationId)) } label: {
                HStack(spacing: 10) {
                    PersonAvatar(name: "", size: 32, isAssistant: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Assistant").font(.subheadline.weight(.semibold))
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to the call")
            .accessibilityIdentifier("assistantCallBar")
            if call.voice.isActive {
                Button { call.voice.toggleMute() } label: {
                    Image(systemName: call.voice.isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(call.voice.isMuted ? Color.statusError : Color.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(call.voice.isMuted ? "Unmute" : "Mute")
            }
            Button {
                call.end()
                session.assistantCall = nil
            } label: {
                Image(systemName: "phone.down.fill")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.statusError, in: .circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End the call")
            .accessibilityIdentifier("assistantCallBarLeave")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var status: String {
        switch call.voice.phase {
        case .idle: ""
        case .connecting: String(localized: "Connecting\u{2026}")
        case .failed(let message): message
        case .speaking: String(localized: "Speaking")
        case .listening: call.voice.isMuted ? String(localized: "Muted") : String(localized: "Listening")
        }
    }
}
