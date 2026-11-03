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
        // The call's own text stops growing at the first accessibility size, so the tiles and controls keep their room.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $isRinging) {
            CallPeoplePicker(
                title: "Ring more people", confirmTitle: "Ring", people: call.peopleToRing(among: room?.currentMembers ?? []), showsVideoChoice: false,
                maximumPeople: sessionModel.callMaximumPersonCount
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
                Text(call.chatTitle).font(.headline).lineLimit(3).multilineTextAlignment(.center)
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

/// ParticipantGrid is the stage of a call, laid out as phone video calls are. Alone or while ringing, one's own picture fills it and the people
/// being rung are a compact row of avatars over it. Two people on camera: the other fills the stage and one's own is a small picture that can be
/// dragged to any corner and tapped to swap. Three or more tile the stage, and each tile's picture fills it. A call with nobody's camera on shows
/// pictures of the people instead.
struct ParticipantGrid: View {
    let call: ChatCallSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var corner = CallTiling.Corner.topTrailing
    @State private var drag = CGSize.zero
    @State private var isSwapped = false
    @State private var stripPosition: String?
    @State private var visibleStripIds: Set<String> = []
    @State private var stageSize = CGSize.zero

    var body: some View {
        let people = call.participants
        let present = people.filter { !$0.isRinging }
        let ringing = people.filter(\.isRinging)
        let isVideo = call.hasVideoTiles
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                stage(present: present, isVideo: isVideo, size: proxy.size)
                if !ringing.isEmpty {
                    RingingRow(people: ringing)
                        .padding(.top, 10)
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity, alignment: isVideo && present.count != 2 ? .top : .bottom)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: present.map(\.userId), initial: true) { _, _ in reportVisibility(present) }
            .onChange(of: call.mainUserId) { _, _ in reportVisibility(present) }
            .onChange(of: visibleStripIds) { _, _ in reportVisibility(present) }
            .onChange(of: proxy.size, initial: true) { _, size in
                stageSize = size
                reportVisibility(present)
            }
        }
    }

    private func reportVisibility(_ present: [CallParticipant]) {
        call.reportLayout(isSpeakerView: CallTiling.usesSpeakerView(count: present.count), visibleStripUserIds: visibleStripIds, tileSizes: tileSizes(present))
    }

    /// The size each other person's tile has outside the speaker view, so a tile too small for full video asks for a small one.
    private func tileSizes(_ present: [CallParticipant]) -> [String: CallSubscriptionPlan.TileSize] {
        guard !CallTiling.usesSpeakerView(count: present.count), stageSize.width > 0 else { return [:] }
        var sizes: [String: CallSubscriptionPlan.TileSize] = [:]
        if present.count == 2 {
            // The other person fills the stage.
            for person in present where !person.isSelf { sizes[person.userId] = .init(width: Double(stageSize.width), height: Double(stageSize.height)) }
            return sizes
        }
        let frames = CallTiling.tiles(count: present.count, width: Double(stageSize.width), height: Double(stageSize.height), isWide: horizontalSizeClass == .regular)
        for frame in frames where !present[frame.index].isSelf { sizes[present[frame.index].userId] = .init(width: frame.width, height: frame.height) }
        return sizes
    }

    @ViewBuilder
    private func stage(present: [CallParticipant], isVideo: Bool, size: CGSize) -> some View {
        if CallTiling.usesSpeakerView(count: present.count) {
            speakerLayout(present, size: size)
        } else if !isVideo {
            voiceLayout(present, size: size)
        } else if present.count <= 1 {
            if let only = present.first {
                tile(only, style: .stage)
            }
        } else if present.count == 2, let own = present.first(where: \.isSelf), let other = present.first(where: { !$0.isSelf }) {
            let main = isSwapped ? own : other
            let small = isSwapped ? other : own
            ZStack(alignment: .topLeading) {
                tile(main, style: .stage)
                    .frame(width: size.width, height: size.height)
                pictureInPicture(small, stage: size)
            }
        } else {
            let frames = CallTiling.tiles(count: present.count, width: Double(size.width), height: Double(size.height), isWide: horizontalSizeClass == .regular)
            ZStack(alignment: .topLeading) {
                ForEach(frames, id: \.index) { frame in
                    tile(present[frame.index], style: .tile)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.x, y: frame.y)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    /// Five people or more: one person fills the main stage (the speaker, or whoever the viewer pinned) and everyone else is a small tile in a strip
    /// under it, which scrolls sideways. A tap on a tile pins that person.
    private func speakerLayout(_ present: [CallParticipant], size: CGSize) -> some View {
        let main = present.first { $0.userId == call.mainUserId } ?? present.first { !$0.isSelf } ?? present[0]
        let strip = present.filter { $0.userId != main.userId }
        let stripHeight: CGFloat = 108
        let stageHeight = max(120, size.height - stripHeight - CallTiling.spacing)
        return VStack(spacing: CallTiling.spacing) {
            ZStack(alignment: .bottomTrailing) {
                tile(main, style: .stage)
                if call.pinnedUserId != nil {
                    Button { withAnimation(.snappy) { call.followSpeaker() } } label: {
                        Label("Follow the speaker", systemImage: "pin.slash.fill")
                            .font(.footnote.weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(10)
                    .accessibilityIdentifier("followSpeakerButton")
                }
            }
            .frame(width: size.width, height: stageHeight)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(strip) { person in
                        tile(person, style: .strip)
                            .frame(width: 76, height: stripHeight)
                            .id(person.userId)
                            .onTapGesture { withAnimation(.snappy) { call.pin(person.userId) } }
                            .accessibilityHint(Text("Tap to keep this person on the main stage."))
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $stripPosition)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { ids in visibleStripIds = Set(ids) }
            .frame(width: size.width, height: stripHeight)
            .task {
                // The screenshot run scrolls the strip to its end.
                if DemoOptions.screen == "call-twelve" {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    withAnimation { stripPosition = strip.last?.userId }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// A call nobody's camera is on: the people's pictures, in the same columns the tiles would take.
    private func voiceLayout(_ present: [CallParticipant], size: CGSize) -> some View {
        let frames = CallTiling.tiles(count: present.count, width: Double(size.width), height: Double(size.height), isWide: horizontalSizeClass == .regular)
        return ZStack(alignment: .topLeading) {
            ForEach(frames, id: \.index) { frame in
                tile(present[frame.index], style: .avatarOnly)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.x, y: frame.y)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func tile(_ person: CallParticipant, style: ParticipantTile.Style) -> some View {
        ParticipantTile(person: person, box: call.videoBox(for: person), style: style, isFrontCamera: call.isFrontCamera)
    }

    private func pictureInPicture(_ person: CallParticipant, stage: CGSize) -> some View {
        let size = CallTiling.pictureInPictureSize(stageWidth: Double(stage.width))
        let origin = CallTiling.pictureInPictureOrigin(corner: corner, stageWidth: Double(stage.width), stageHeight: Double(stage.height))
        return tile(person, style: .picture)
            .frame(width: size.width, height: size.height)
            .offset(x: origin.x + drag.width, y: origin.y + drag.height)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .onTapGesture { withAnimation(.snappy) { isSwapped.toggle() } }
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        let centerX = origin.x + size.width / 2 + Double(value.translation.width)
                        let centerY = origin.y + size.height / 2 + Double(value.translation.height)
                        let target = CallTiling.nearestCorner(centerX: centerX, centerY: centerY, stageWidth: Double(stage.width), stageHeight: Double(stage.height))
                        // The picture lets go where it was dropped and slides to the corner from there.
                        let landed = CallTiling.pictureInPictureOrigin(corner: target, stageWidth: Double(stage.width), stageHeight: Double(stage.height))
                        drag = CGSize(width: origin.x + value.translation.width - landed.x, height: origin.y + value.translation.height - landed.y)
                        corner = target
                        withAnimation(.snappy) { drag = .zero }
                    }
            )
            .accessibilityLabel(Text("Your picture"))
            .accessibilityHint(Text("Tap to swap with the main picture. Drag to move it."))
            .accessibilityAddTraits(.isButton)
    }
}

/// RingingRow is the people a call is ringing, as a compact row of small pictures with their names.
struct RingingRow: View {
    let people: [CallParticipant]

    private var avatars: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(people) { person in
                VStack(spacing: 4) {
                    UserAvatar(userId: person.userId, name: person.name, size: 44)
                    Text(person.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 84)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Ringing\u{2026}").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            // A few people sit side by side in a panel that fits them; more scroll sideways.
            ViewThatFits(in: .horizontal) {
                avatars
                ScrollView(.horizontal, showsIndicators: false) { avatars }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Ringing\u{2026}"))
        .accessibilityValue(Text(people.map(\.name).joined(separator: ", ")))
    }
}

/// ParticipantTile is one person: their camera filling the tile (cropped, never letterboxed), or a picture on a quiet ground, with their name,
/// whether they are muted, and a ring while they speak.
struct ParticipantTile: View {
    enum Style {
        /// The whole stage.
        case stage
        /// One of several tiles.
        case tile
        /// The small picture of oneself.
        case picture
        /// A call with no cameras: a picture and a name on no ground.
        case avatarOnly
        /// A small tile in the strip under the main stage.
        case strip
    }

    let person: CallParticipant
    let box: VideoTrackBox?
    let style: Style
    let isFrontCamera: Bool

    private var radius: CGFloat {
        switch style {
        case .stage: 28
        case .tile: 22
        case .picture: 16
        case .avatarOnly: 0
        case .strip: 14
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let shortSide = min(proxy.size.width, proxy.size.height)
            let avatarSize: CGFloat = {
                switch style {
                case .stage: return min(max(shortSide * 0.4, 72), 180)
                case .tile: return min(max(shortSide * 0.42, 44), 120)
                case .picture: return min(max(shortSide * 0.5, 32), 56)
                case .strip: return 40
                case .avatarOnly: return min(max(shortSide * 0.6, 56), 150)
                }
            }()
            ZStack {
                if style == .avatarOnly {
                    UserAvatar(userId: person.userId, name: person.name, size: avatarSize)
                        .overlay {
                            Circle().strokeBorder(person.isSpeaking ? Color.statusSuccess : Color.white.opacity(0.15), lineWidth: person.isSpeaking ? 4 : 1)
                                .padding(-6)
                        }
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(placeholderGradient)
                    if person.isVideoOn, let box {
                        CallVideoView(box: box, isMirrored: person.isSelf && isFrontCamera)
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    } else {
                        UserAvatar(userId: person.userId, name: person.name, size: avatarSize)
                    }
                }
                if style == .strip { stripLabel } else if style != .picture { label(isFramed: style != .avatarOnly) } else if person.isMuted { mutedBadge }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay {
                if style != .avatarOnly {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(person.isSpeaking ? Color.statusSuccess : Color.clear, lineWidth: style == .picture || style == .strip ? 3 : 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(person.name))
        .accessibilityValue(Text(person.isMuted ? "Muted" : (person.isSpeaking ? "Speaking" : "")))
    }

    private func label(isFramed: Bool) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if person.isMuted { Image(systemName: "mic.slash.fill").font(.caption) }
                Text(person.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(isFramed ? .leading : .center)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(isFramed ? 0.45 : 0), in: .capsule)
            .frame(maxWidth: .infinity, alignment: isFramed ? .leading : .center)
            .padding(isFramed ? 10 : 0)
        }
    }

    private var stripLabel: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                if person.isMuted { Image(systemName: "mic.slash.fill").font(.system(size: 9)) }
                Text(person.name).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .dynamicTypeSize(...DynamicTypeSize.large)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45), in: .capsule)
            .padding(4)
        }
    }

    private var mutedBadge: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Image(systemName: "mic.slash.fill").font(.caption2).padding(5).background(.black.opacity(0.5), in: .circle)
                Spacer(minLength: 0)
            }
            .padding(6)
        }
    }

    private var placeholderGradient: LinearGradient {
        let hue = Double(person.userId.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.35, brightness: 0.35), Color(hue: hue, saturation: 0.5, brightness: 0.18)], startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}
