import PortalKit
import SwiftUI

/// ComposerCard is where the person writes, on every screen that has a box:
/// one rounded card with the words on top and the buttons inside it, adding
/// files at the bottom left, then voice, stop and send at the bottom right.
/// Send is a filled accent circle when there is something to send and quiet
/// gray when there is not. Nothing around it is glass of its own.
struct ComposerCard<Accessory: View>: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var drafts: AttachmentDrafts?
    var isEnabled = true
    let canSend: Bool
    var isSending = false
    var sendSymbol = "arrow.up"
    var sendLabel: LocalizedStringKey = "Send"
    var onVoice: (() -> Void)?
    var onStop: (() -> Void)?
    var fieldIdentifier = "messageField"
    var sendIdentifier = "sendButton"
    var onEscape: (() -> Bool)?
    let onSend: () -> Void
    @ViewBuilder var accessory: Accessory

    @FocusState private var isFocused: Bool
    /// The round buttons grow with the text, held where their symbols stay inside them.
    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 36
    private var diameter: CGFloat { min(scaledDiameter, 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($isFocused)
                .disabled(!isEnabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .accessibilityIdentifier(fieldIdentifier)
                .onKeyPress(.escape, phases: .down) { _ in (onEscape?() ?? false) ? .handled : .ignored }
                // With a hardware keyboard, Return sends and Shift+Return adds a line.
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    if canSend { onSend() }
                    return .handled
                }
            HStack(spacing: 4) {
                if let drafts { AttachMenu(drafts: drafts, systemImage: "plus") }
                accessory
                Spacer(minLength: 0)
                if let onVoice, !canSend {
                    Button(action: onVoice) {
                        Image(systemName: "waveform")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: diameter, height: diameter)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Talk to the assistant")
                    .accessibilityIdentifier("voiceButton")
                }
                if let onStop {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.footnote)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: diameter, height: diameter)
                            .background(Color.primary, in: .circle)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Stop")
                }
                Button(action: onSend) {
                    Group {
                        if isSending {
                            ProgressView().tint(Color.onAccent)
                        } else {
                            Image(systemName: sendSymbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.onAccent)
                        }
                    }
                    .frame(width: diameter, height: diameter)
                    .background(canSend || isSending ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiaryLabel)), in: .circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                }
                .disabled(!canSend)
                .accessibilityLabel(sendLabel)
                .accessibilityIdentifier(sendIdentifier)
            }
            // Past a point the buttons stop growing with the text.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        // A tap on the card outside its buttons starts typing.
        .background {
            Color.clear
                .contentShape(.rect(cornerRadius: 26, style: .continuous))
                .onTapGesture { isFocused = true }
        }
        .background(Color.portalCard.opacity(0.92), in: .rect(cornerRadius: 26, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 720 + 32)
        .frame(maxWidth: .infinity)
    }
}

extension ComposerCard where Accessory == EmptyView {
    init(
        placeholder: LocalizedStringKey, text: Binding<String>, drafts: AttachmentDrafts? = nil, isEnabled: Bool = true, canSend: Bool,
        isSending: Bool = false, sendSymbol: String = "arrow.up", sendLabel: LocalizedStringKey = "Send", onVoice: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil, fieldIdentifier: String = "messageField", sendIdentifier: String = "sendButton", onEscape: (() -> Bool)? = nil,
        onSend: @escaping () -> Void
    ) {
        self.init(
            placeholder: placeholder, text: text, drafts: drafts, isEnabled: isEnabled, canSend: canSend, isSending: isSending, sendSymbol: sendSymbol,
            sendLabel: sendLabel, onVoice: onVoice, onStop: onStop, fieldIdentifier: fieldIdentifier, sendIdentifier: sendIdentifier, onEscape: onEscape,
            onSend: onSend, accessory: { EmptyView() })
    }
}

/// ReactionBadges draw the emoji on a message in a small capsule on the
/// bubble's lower corner, as Messages draws a tapback. A tap toggles the
/// person's own; the target is 44 points though the capsule is small.
struct ReactionBadges: View {
    let reactions: [Reaction]
    let currentUserId: String
    let onTap: ((String) -> Void)?

    var body: some View {
        let summaries = Reactions.summaries(reactions, currentUserId: currentUserId)
        if !summaries.isEmpty {
            HStack(spacing: 2) {
                ForEach(summaries) { summary in
                    let label = HStack(spacing: 2) {
                        Text(summary.emoji)
                        if summary.count > 1 { Text("\(summary.count)").font(.caption2) }
                    }
                    .padding(.horizontal, 3)
                    .background(summary.isMine ? Color.accentColor.opacity(0.25) : Color.clear, in: .capsule)
                    if let onTap {
                        Button { onTap(summary.emoji) } label: { label.contentShape(Rectangle().inset(by: -12)) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Reacted with \(summary.emoji)"))
                    } else {
                        label
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
        }
    }
}

extension View {
    /// Puts a message's reactions on the bubble's lower corner, with room below for them.
    func reactionCorner(_ reactions: [Reaction], currentUserId: String, isLeading: Bool, onTap: ((String) -> Void)?) -> some View {
        overlay(alignment: isLeading ? .bottomLeading : .bottomTrailing) {
            ReactionBadges(reactions: reactions, currentUserId: currentUserId, onTap: onTap)
                .offset(x: isLeading ? -8 : 8, y: 16)
        }
        .padding(.bottom, reactions.isEmpty ? 0 : 16)
    }

    /// The bar of a screen whose bottom is a composer: the title is a glass
    /// pill in the middle, the bar itself see-through so messages run under
    /// it with the system's soft edge, and the tab bar gives way.
    func conversationBar(title: String, onTitleTap: (() -> Void)? = nil) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbarVisibility(.hidden, for: .tabBar)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let onTitleTap {
                        Button(action: onTitleTap) { titlePill(title) }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Shows who is in this chat"))
                    } else {
                        titlePill(title)
                    }
                }
            }
    }
}

private func titlePill(_ title: String) -> some View {
    Text(title)
        .font(.headline)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
}

/// PersonAvatar is a small round picture of someone's initials.
struct PersonAvatar: View {
    let name: String
    var size: CGFloat = 28
    var isAssistant = false

    var body: some View {
        ZStack {
            Circle().fill(isAssistant ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(Color(.tertiarySystemFill)))
            if isAssistant {
                Image(systemName: "sparkles").font(.system(size: size * 0.45)).foregroundStyle(Color.accentColor)
            } else {
                Text(Self.initials(name)).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

/// DayLabel names a day between messages: Today, Yesterday, or the date.
enum DayLabel {
    static func isNewDay(_ previous: Date?, _ current: Date?) -> Bool {
        guard let current else { return false }
        guard let previous else { return true }
        return !Calendar.current.isDate(previous, inSameDayAs: current)
    }

    static func text(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}

extension SiteTelemetry {
    /// Numbers of the right shape for the redacted tiles shown while the real ones load.
    static var placeholder: SiteTelemetry {
        SiteTelemetry(
            summaries: [TelemetrySummary(controllerId: "placeholder", totals: .init(pickOperationCount: 1_480, pickedPartCount: 1_392, humanInterventionCount: 21, directRobotThroughputPartsPerHour: 58))],
            machinesTotal: 2)
    }
}

/// PlaceholderShimmer shows its content as a redacted placeholder with a gentle pulse while it loads,
/// in the layout the real content will have, so nothing jumps in later.
private struct PlaceholderShimmer: ViewModifier {
    let isActive: Bool
    @State private var isDimmed = false
    @Environment(\.accessibilityReduceMotion) private var isReducingMotion

    func body(content: Content) -> some View {
        content
            .redacted(reason: isActive ? .placeholder : [])
            .opacity(isActive && isDimmed && !isReducingMotion ? 0.55 : 1)
            .animation(isActive && !isReducingMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: isDimmed)
            .onAppear { isDimmed = true }
            .allowsHitTesting(!isActive)
    }
}

extension View {
    func placeholderWhileLoading(_ isLoading: Bool) -> some View { modifier(PlaceholderShimmer(isActive: isLoading)) }
}
