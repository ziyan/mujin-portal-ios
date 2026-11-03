import AVKit
import PortalKit
import SwiftUI
import UIKit

/// RoutePickerTrigger opens the system's list of places the sound can go (iPhone, Speaker, headphones, AirPods) from a button of the app's own.
@MainActor
final class RoutePickerTrigger {
    fileprivate weak var picker: AVRoutePickerView?

    func present() {
        guard let picker else { return }
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                return
            }
        }
    }
}

/// RoutePickerHost holds the system's picker, nearly see-through, behind the app's own glass button.
struct RoutePickerHost: UIViewRepresentable {
    let trigger: RoutePickerTrigger

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.alpha = 0.02
        picker.prioritizesVideoDevices = false
        trigger.picker = picker
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) { trigger.picker = picker }
}

/// CallScreen is the full screen of a call: who is on it, what each camera shows, and the controls.
struct CallScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var sessionModel
    let center: CallCenter

    @State private var trigger = RoutePickerTrigger()
    @State private var isRinging = DemoOptions.screen == "call-ring-more"
    @State private var room: ChatRoom?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let call = center.session {
            screen(call)
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    private func screen(_ call: ChatCallSession) -> some View {
        VStack(spacing: 12) {
            topBar(call)
            if let notice = call.transcriptionNotice {
                TranscriptionNotice(text: notice) { call.dismissTranscriptionNotice() }
            }
            if let error = call.errorText {
                HStack(spacing: 8) {
                    Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { call.dismissError() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
            }
            ParticipantGrid(call: call)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls(call)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CallBackground().ignoresSafeArea())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $isRinging) {
            CallPeoplePicker(
                title: "Ring more people", confirmTitle: "Ring", people: call.peopleToRing(among: room?.currentMembers ?? []), showsVideoChoice: false
            ) { userIds, _ in
                Task { _ = await call.ring(userIds) }
            }
        }
        .task(id: call.chatId) {
            if let loaded = try? await appModel.connection(for: sessionModel.account).chat(id: call.chatId) { room = loaded }
        }
    }

    private func topBar(_ call: ChatCallSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GlassIconButton(symbol: "chevron.down", label: "Minimize") { center.minimize() }
            VStack(spacing: 2) {
                Text(call.chatTitle).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                Text(call.statusText).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            GlassIconButton(symbol: "person.badge.plus", label: "Ring more people") { isRinging = true }
                .disabled(call.call == nil)
        }
        .padding(.top, 8)
    }

    private func controls(_ call: ChatCallSession) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                GlassIconButton(symbol: call.isMuted ? "mic.slash.fill" : "mic.fill", label: call.isMuted ? "Unmute" : "Mute", isOn: call.isMuted, size: 56) {
                    center.setMuted(!call.isMuted)
                }
                GlassIconButton(symbol: call.isCameraOn ? "video.fill" : "video.slash.fill", label: call.isCameraOn ? "Turn the camera off" : "Turn the camera on", isOn: call.isCameraOn, size: 56) {
                    call.toggleCamera()
                }
                GlassIconButton(symbol: "arrow.triangle.2.circlepath.camera", label: "Switch camera", size: 56) { call.switchCamera() }
                    .disabled(!call.isCameraOn)
                    .opacity(call.isCameraOn ? 1 : 0.4)
                GlassIconButton(symbol: call.routeSymbol, label: "Audio output", size: 56) { trigger.present() }
                    .background { RoutePickerHost(trigger: trigger).frame(width: 56, height: 56) }
                GlassIconButton(symbol: call.isTranscriptionOn ? "captions.bubble.fill" : "captions.bubble", label: call.isTranscriptionOn ? "Turn transcription off" : "Turn transcription on", isOn: call.isTranscriptionOn, size: 56) {
                    call.setTranscription(!call.isTranscriptionOn)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Button { center.hangUp() } label: {
                Label("Leave call", systemImage: "phone.down.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.statusError, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("leaveCallButton")
        }
    }
}

/// CallBackground is the quiet dark ground behind a call.
struct CallBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.14), Color(red: 0.03, green: 0.04, blue: 0.07)], startPoint: .top, endPoint: .bottom)
    }
}

/// GlassIconButton is a round glass button with a symbol, for the call's controls.
struct GlassIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var isOn = false
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(isOn ? Color.white : Color.clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// TranscriptionNotice names who turned transcription on. The person may dismiss it; nobody is asked first.
struct TranscriptionNotice: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "captions.bubble.fill").accessibilityHidden(true)
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) { Image(systemName: "xmark.circle.fill").font(.body) }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("transcriptionNotice")
    }
}

/// ParticipantGrid lays the people of a call out: big pictures with a speaking ring for a voice call, tiles for a video call.
struct ParticipantGrid: View {
    let call: ChatCallSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let people = call.participants
        let isVideo = call.hasVideoTiles
        GeometryReader { proxy in
            let count = max(people.count, 1)
            let columns = count <= 2 && !isVideo ? 1 : (count == 1 ? 1 : 2)
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            let spacing: CGFloat = 10
            let tileWidth = (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let tileHeight = max(60, (proxy.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(people.dropFirst(row * columns).prefix(columns)) { person in
                            ParticipantTile(person: person, box: call.videoBox(for: person), isVideo: isVideo, isFrontCamera: call.isFrontCamera)
                                .frame(width: tileWidth, height: tileHeight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// ParticipantTile is one person: a picture (or their camera) with their name, whether they are muted, and a ring while they speak.
struct ParticipantTile: View {
    let person: CallParticipant
    let box: VideoTrackBox?
    let isVideo: Bool
    let isFrontCamera: Bool

    var body: some View {
        GeometryReader { proxy in
            let avatarSize = min(proxy.size.width, proxy.size.height) * (isVideo ? 0.42 : 0.6)
            ZStack {
                if isVideo {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(placeholderGradient)
                    if person.isVideoOn, let box {
                        CallVideoView(box: box, isMirrored: person.isSelf && isFrontCamera)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        UserAvatar(userId: person.userId, name: person.name, size: min(max(avatarSize, 44), 120))
                    }
                } else {
                    UserAvatar(userId: person.userId, name: person.name, size: min(max(avatarSize, 56), 150))
                        .overlay {
                            Circle().strokeBorder(person.isSpeaking ? Color.statusSuccess : Color.white.opacity(0.15), lineWidth: person.isSpeaking ? 4 : 1)
                                .padding(-6)
                        }
                }
                VStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if person.isMuted { Image(systemName: "mic.slash.fill").font(.caption) }
                        Text(person.isRinging ? String(localized: "\(person.name), ringing\u{2026}") : person.name)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(isVideo ? .leading : .center)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(isVideo ? 0.45 : 0), in: .capsule)
                    .frame(maxWidth: .infinity, alignment: isVideo ? .leading : .center)
                    .padding(isVideo ? 8 : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay {
                if isVideo {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(person.isSpeaking ? Color.statusSuccess : Color.clear, lineWidth: 4)
                }
            }
            .opacity(person.isRinging ? 0.6 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(person.name))
        .accessibilityValue(Text(person.isMuted ? "Muted" : (person.isSpeaking ? "Speaking" : "")))
    }

    private var placeholderGradient: LinearGradient {
        let hue = Double(person.userId.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.35, brightness: 0.35), Color(hue: hue, saturation: 0.5, brightness: 0.18)], startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}
