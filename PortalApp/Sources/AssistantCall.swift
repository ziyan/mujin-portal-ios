import PortalKit
import SwiftUI

/// CallPlace is where a call with the assistant is: a conversation, or one thread of it.
struct CallPlace: Equatable {
    let conversationId: String
    let threadRootMessageId: String?
}

/// AssistantCall is a call with the assistant: its conversation or thread, which hears the answers, and the voice that carries the
/// call. The session holds it while it goes, so the call outlives the screen it started on.
@MainActor
final class AssistantCall {
    let conversationId: String
    /// The thread the call is in: each spoken turn is a reply in it, and only its runs are read aloud. Nil for the main history.
    let threadRootMessageId: String?
    let model: ConversationModel
    let voice: VoiceCallController
    let startedAt = Date()

    init(conversationId: String, threadRootMessageId: String?, model: ConversationModel, voice: VoiceCallController) {
        self.conversationId = conversationId
        self.threadRootMessageId = threadRootMessageId
        self.model = model
        self.voice = voice
    }

    var place: CallPlace { CallPlace(conversationId: conversationId, threadRootMessageId: threadRootMessageId) }

    /// Opens the call's own conversation or thread, where its stage shows.
    func open(in session: SessionModel) {
        if let threadRootMessageId {
            session.open(.conversationThread(id: conversationId, threadRootMessageId: threadRootMessageId))
        } else {
            session.open(.conversation(id: conversationId))
        }
    }

    /// Whether the call is still going or being set up. A call that failed is over: it leaves no bar behind.
    var isGoing: Bool {
        if case .failed = voice.phase { return false }
        return voice.isActive || voice.phase != .idle
    }

    /// Hangs up from the bar, where no screen is left to stop the conversation's live feed.
    func end() {
        print("CALLDIAG call-end \(conversationId)")
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
            Button { call.open(in: session) } label: {
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
