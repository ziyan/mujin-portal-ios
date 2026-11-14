import PortalKit
import SwiftUI

/// OngoingCallStrip shows, under a conversation's, chat's or thread's header, a call going on somewhere else: who it is with,
/// "On a call" and for how long, mute, hang up, and a tap anywhere else to go to the call. A call with the assistant and a call with
/// people both show here. The screen the call is on shows its full stage instead, and the strip stays away.
struct OngoingCallStrip: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    /// Where the screen is, so a call with the assistant in this very place is left to its stage.
    let place: CallPlace?
    /// Whether the screen shows the call with people on its own stage.
    var isPeopleCallStagedHere = false

    /// This strip, in the session's set of strips that show.
    @State private var stripId = UUID()

    var body: some View {
        if let call = session.assistantCall, call.isGoing, call.place != place {
            strip(
                avatar: AnyView(PersonAvatar(name: "", size: 28, isAssistant: true)),
                detail: { now in Text(verbatim: "\(String(localized: "Assistant")) \u{00B7} \(Self.clock(now.timeIntervalSince(call.startedAt)))") },
                isMuted: call.voice.isMuted, canMute: call.voice.isActive, onMute: { call.voice.toggleMute() },
                onHangUp: {
                    call.end()
                    session.assistantCall = nil
                },
                onOpen: { call.open(in: session) })
        } else if let call = appModel.callCenter.session, !call.isEnded, !appModel.callCenter.isScreenShown, !isPeopleCallStagedHere {
            strip(
                avatar: AnyView(
                    Image(systemName: call.isCameraOn ? "video.fill" : "phone.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 28, height: 28)
                        .background(Color.statusSuccess, in: .circle)),
                detail: { _ in Text(verbatim: "\(call.chatTitle) \u{00B7} \(call.statusText)") },
                isMuted: call.isMuted, canMute: true, onMute: { appModel.callCenter.setMuted(!call.isMuted) },
                onHangUp: { appModel.callCenter.hangUp() },
                onOpen: { appModel.callCenter.show() })
        }
    }

    private func strip(
        avatar: AnyView, detail: @escaping (Date) -> Text, isMuted: Bool, canMute: Bool, onMute: @escaping () -> Void,
        onHangUp: @escaping () -> Void, onOpen: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    avatar.accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("On a call").font(.caption.weight(.semibold))
                        // Minutes, read once a minute: a clock that ticks every second keeps every screen under it redrawing.
                        TimelineView(.everyMinute) { context in
                            detail(context.date).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to the call")
            .accessibilityIdentifier("ongoingCallStrip")
            if canMute {
                Button(action: onMute) {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.footnote)
                        .foregroundStyle(isMuted ? Color.statusError : Color.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                .accessibilityIdentifier("ongoingCallStripMute")
            }
            Button(action: onHangUp) {
                Image(systemName: "phone.down.fill")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.statusError, in: .circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End the call")
            .accessibilityIdentifier("ongoingCallStripHangUp")
        }
        // One line of controls: the words stop growing at the largest ordinary size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .onAppear { session.callStripsShown.insert(stripId) }
        .onDisappear { session.callStripsShown.remove(stripId) }
    }

    /// How long a call has run, as minutes and seconds, with hours once it passes one.
    /// How long the call has gone, in whole minutes: "Under a minute", "12 min", "1 h 5 min".
    static func clock(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)) / 60
        if minutes == 0 { return String(localized: "Under a minute") }
        if minutes < 60 { return String(localized: "\(minutes) min") }
        return String(localized: "\(minutes / 60) h \(minutes % 60) min")
    }
}
