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
    let isSpeaking: Bool
    let isMuted: Bool
    /// Nil while there is nothing to mute yet, such as while connecting.
    let onMute: (() -> Void)?
    let leaveSymbol: String
    let leaveLabel: LocalizedStringKey
    let onLeave: () -> Void
    /// A tap on the picture, such as to bring back the full call screen; nil leaves the picture still.
    var onAvatarTap: (() -> Void)?
    var avatarTapLabel: LocalizedStringKey = ""
    @ViewBuilder let avatar: (CGFloat) -> Avatar

    /// The bar's buttons are this tall; the column of controls is as wide as one.
    static var controlSize: CGFloat { 44 }

    var body: some View {
        GeometryReader { proxy in
            let barTop = Self.windowTopInset
            let contentTop = max(proxy.safeAreaInsets.top, barTop)
            let barHeight = max(contentTop - barTop, Self.controlSize)
            let isWide = horizontalSizeClass == .regular
            // A third of the chat's column on a phone, a little less on a wide screen, and never so large it hides the conversation.
            let avatarSize = min(proxy.size.width * (isWide ? 0.3 : 0.4), isWide ? 220 : 180)
            // On a phone the picture takes the middle of the bar, where the title was. On a wide screen the floating tab bar may share
            // the bar's row, so the picture starts below it.
            let avatarTop = isWide ? contentTop + 12 : barTop + (barHeight - Self.controlSize) / 2
            ZStack(alignment: .top) {
                stage(size: avatarSize)
                    .padding(.top, avatarTop)
                    .frame(maxWidth: .infinity)
                controls
                    .padding(.top, barTop + (barHeight - Self.controlSize) / 2)
                    .padding(.trailing, 16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private func stage(size: CGFloat) -> some View {
        Button {
            onAvatarTap?()
        } label: {
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
        .buttonStyle(.plain)
        .disabled(onAvatarTap == nil)
        .accessibilityLabel(onAvatarTap == nil ? Text(name) : Text(avatarTapLabel))
        .overlay(alignment: .bottom) {
            nameCapsule
                .alignmentGuide(.bottom) { dimensions in dimensions[VerticalAlignment.center] }
        }
        // The name capsule hangs half below the picture.
        .padding(.bottom, 24)
    }

    private var nameCapsule: some View {
        VStack(spacing: 0) {
            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
            if !status.isEmpty {
                Text(status).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        // The capsule keeps to two short lines over the picture: its text stops growing at the largest ordinary size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
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

    /// The status bar's height: the window's own top inset, under which the navigation bar's row begins.
    private static var windowTopInset: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return window?.safeAreaInsets.top ?? 0
    }
}

/// AssistantCallAvatar is the assistant's picture on the call stage: its mark on the app's tint, large.
struct AssistantCallAvatar: View {
    let size: CGFloat

    var body: some View {
        PersonAvatar(name: "", size: size, isAssistant: true)
    }
}
