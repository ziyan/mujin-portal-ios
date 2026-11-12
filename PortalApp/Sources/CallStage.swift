import SwiftUI
import UIKit

/// CallStage is a conversation while a call in it is going: who the call is with, large at the top over the messages with their name
/// on a glass capsule across the picture's lower edge, and the call's two controls, leave and mute, in a column of glass at the top
/// right, where the bar's own buttons stand when there is no call. The messages keep scrolling behind it.
///
/// It is laid over the conversation's content, which starts below the navigation bar; the controls and, on a phone, the picture
/// reach up into the bar's row, whose buttons and title the conversation hides while the stage is up.
struct CallStage<Avatar: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let name: String
    /// What the call is doing, under the name: how long it has run, or connecting, or a problem.
    let status: String
    /// Whether the call is being recorded, said beside its status with a red dot.
    var isRecording = false
    let isSpeaking: Bool
    let isMuted: Bool
    /// Nil while there is nothing to mute yet, such as while connecting.
    let onMute: (() -> Void)?
    let leaveSymbol: String
    let leaveLabel: LocalizedStringKey
    let onLeave: () -> Void
    /// Told where the stage ends on screen (in the global coordinate space), so the messages can start below it.
    var onStageBottom: ((CGFloat) -> Void)?
    /// A tap on the picture, such as to bring back the full call screen; nil leaves the picture still.
    var onAvatarTap: (() -> Void)?
    var avatarTapLabel: LocalizedStringKey = ""
    @ViewBuilder let avatar: (CGFloat) -> Avatar

    /// The bar's buttons are this tall; the column of controls is as wide as one.
    static var controlSize: CGFloat { 44 }

    var body: some View {
        ZStack(alignment: .top) {
            fade
            // The picture and the controls sit below the navigation bar, inside the conversation's own area: drawn in the bar's
            // row, the bar takes their touches and the buttons do nothing.
            GeometryReader { proxy in
                let isWide = horizontalSizeClass == .regular
                // About a quarter of the chat's column on a phone, less on a wide screen, and never so large it hides the conversation.
                let avatarSize = min(proxy.size.width * (isWide ? 0.2 : 0.26), isWide ? 160 : 110)
                // The capsule may be as wide as the room beside the call's controls on either side.
                let nameWidth = max(proxy.size.width - 2 * (16 + Self.controlSize + 12), avatarSize)
                ZStack(alignment: .top) {
                    stage(size: avatarSize, nameWidth: nameWidth)
                        .padding(.top, isWide ? 24 : 4)
                        .frame(maxWidth: .infinity)
                    controls
                        .padding(.top, 4)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .onChange(of: capsuleBottom, initial: true) { _, bottom in
            if let bottom { onStageBottom?(bottom + 8) }
        }
    }

    /// Messages scrolled up under the stage fade into the chat's own background behind it, with no edge. It reaches from the top of
    /// the screen, behind the bar, to just below the name capsule, and takes no touches.
    private var fade: some View {
        let stageBottom = capsuleBottom ?? 0
        return VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: Color.portalPage, location: 0),
                    .init(color: Color.portalPage, location: stageBottom / max(stageBottom + Self.fadeHeight, 1)),
                    .init(color: Color.portalPage.opacity(0), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: stageBottom + Self.fadeHeight)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// How far the name capsule hangs below the picture: half of two short lines of text and their padding.
    private static var nameCapsuleOverhang: CGFloat { 28 }
    /// How far below the name capsule the fade into the chat's background runs.
    private static var fadeHeight: CGFloat { 36 }
    /// Where the name capsule ends, measured: its height follows the text size and the line under the name.
    @State private var capsuleBottom: CGFloat?

    private func stage(size: CGFloat, nameWidth: CGFloat) -> some View {
        picture(size: size)
            .overlay(alignment: .bottom) {
                // Offered the room beside the picture, not only the picture's own width, so a name shows whole when it fits.
                nameCapsule
                    .frame(width: nameWidth)
                    .alignmentGuide(.bottom) { dimensions in dimensions[VerticalAlignment.center] }
            }
            // The name capsule hangs half below the picture.
            .padding(.bottom, Self.nameCapsuleOverhang)
    }

    /// The picture, a button only when a tap does something: a disabled button would draw it dimmed.
    @ViewBuilder private func picture(size: CGFloat) -> some View {
        if let onAvatarTap {
            Button(action: onAvatarTap) { framedAvatar(size: size) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(avatarTapLabel))
        } else {
            framedAvatar(size: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(name))
        }
    }

    private func framedAvatar(size: CGFloat) -> some View {
        avatar(size)
            .frame(width: size, height: size)
            // The picture is solid: the messages scroll behind it, not through it.
            .background(Color(.systemBackground))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.accentColor.opacity(isSpeaking ? 0.9 : 0), lineWidth: 4))
            .padding(4)
            .background(Circle().fill(Color.accentColor.opacity(isSpeaking ? 0.25 : 0)).scaleEffect(isSpeaking ? 1.08 : 1))
            .animation(.easeInOut(duration: 0.35), value: isSpeaking)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var nameCapsule: some View {
        VStack(spacing: 0) {
            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
            if !status.isEmpty || isRecording {
                // One line: the capsule grows wider rather than breaking "Recording".
                HStack(spacing: 6) {
                    if !status.isEmpty { Text(status).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) }
                    if isRecording { RecordingMark() }
                }
                .fixedSize()
            }
        }
        // The capsule keeps to two short lines over the picture: its text stops growing at the largest ordinary size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { capsuleBottom = $0 }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            Button(action: onLeave) {
                Image(systemName: leaveSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.statusError)
                    .frame(width: Self.controlSize, height: Self.controlSize)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(leaveLabel)
            .accessibilityIdentifier("callStageLeave")
            if let onMute {
                Button(action: onMute) {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isMuted ? Color.statusError : Color.primary)
                        .frame(width: Self.controlSize, height: Self.controlSize)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                .accessibilityIdentifier("callStageMute")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .glassEffect(.regular, in: .capsule)
    }
}

/// AssistantCallAvatar is the assistant's picture on the call stage: its mark on the app's tint, large.
struct AssistantCallAvatar: View {
    let size: CGFloat

    var body: some View {
        PersonAvatar(name: "", size: size, isAssistant: true)
    }
}
