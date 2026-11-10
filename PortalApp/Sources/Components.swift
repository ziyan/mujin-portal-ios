import PortalKit
import SwiftUI

/// DictationControl is the microphone button of a composer: it starts and stops dictating into the box.
struct DictationControl {
    let isListening: Bool
    let isEnabled: Bool
    let action: () -> Void
}

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
    var dictation: DictationControl?
    var fieldIdentifier = "messageField"
    var sendIdentifier = "sendButton"
    var onEscape: (() -> Bool)?
    let onSend: () -> Void
    @ViewBuilder var accessory: Accessory

    @State private var isFocused = false
    /// The round buttons grow with the text, held where their symbols stay inside them.
    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 36
    private var diameter: CGFloat { min(scaledDiameter, 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Color(.placeholderText))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Paste or a drop of pictures is the card's own: it adds attachments, and any text that came with them is typed in only when it says something (PasteRule). With a hardware keyboard, Return sends and Shift+Return adds a line.
                ComposerTextView(
                    text: $text, isFocused: $isFocused, isEnabled: isEnabled,
                    onReturn: { if canSend { onSend() } }, onEscape: onEscape,
                    onPasteItems: drafts.map { drafts in { providers in await drafts.paste(itemProviders: providers) } }
                )
                .accessibilityLabel(Text(placeholder))
                .accessibilityIdentifier(fieldIdentifier)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            HStack(spacing: 4) {
                if let drafts { AttachMenu(drafts: drafts, systemImage: "plus") }
                accessory
                Spacer(minLength: 0)
                if let dictation {
                    // A plain microphone, apart from the waveform that starts a call and the filled one that records a voice message.
                    // Listening, it is tinted and sits on a soft circle.
                    Button(action: dictation.action) {
                        Image(systemName: "mic")
                            .font(.body.weight(.medium))
                            .foregroundStyle(dictation.isListening ? Color.accentColor : Color.secondary)
                            .frame(width: diameter, height: diameter)
                            .background(dictation.isListening ? Color.accentColor.opacity(0.18) : Color.clear, in: .circle)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .disabled(!dictation.isEnabled)
                    .accessibilityLabel(dictation.isListening ? Text("Stop dictating") : Text("Dictate"))
                    .accessibilityIdentifier("dictateButton")
                }
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

extension ComposerCard {
    /// The card with a view of the screen's own beside the attach button.
    init(
        placeholder: LocalizedStringKey, text: Binding<String>, drafts: AttachmentDrafts? = nil, isEnabled: Bool = true, canSend: Bool,
        isSending: Bool = false, sendSymbol: String = "arrow.up", sendLabel: LocalizedStringKey = "Send", dictation: DictationControl? = nil,
        fieldIdentifier: String = "messageField", sendIdentifier: String = "sendButton", onEscape: (() -> Bool)? = nil, onSend: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            placeholder: placeholder, text: text, drafts: drafts, isEnabled: isEnabled, canSend: canSend, isSending: isSending, sendSymbol: sendSymbol,
            sendLabel: sendLabel, onVoice: nil, onStop: nil, dictation: dictation, fieldIdentifier: fieldIdentifier, sendIdentifier: sendIdentifier, onEscape: onEscape,
            onSend: onSend, accessory: accessory)
    }
}

extension ComposerCard where Accessory == EmptyView {
    init(
        placeholder: LocalizedStringKey, text: Binding<String>, drafts: AttachmentDrafts? = nil, isEnabled: Bool = true, canSend: Bool,
        isSending: Bool = false, sendSymbol: String = "arrow.up", sendLabel: LocalizedStringKey = "Send", onVoice: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil, dictation: DictationControl? = nil, fieldIdentifier: String = "messageField", sendIdentifier: String = "sendButton",
        onEscape: (() -> Bool)? = nil, onSend: @escaping () -> Void
    ) {
        self.init(
            placeholder: placeholder, text: text, drafts: drafts, isEnabled: isEnabled, canSend: canSend, isSending: isSending, sendSymbol: sendSymbol,
            sendLabel: sendLabel, onVoice: onVoice, onStop: onStop, dictation: dictation, fieldIdentifier: fieldIdentifier, sendIdentifier: sendIdentifier, onEscape: onEscape,
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
                    .padding(.horizontal, 4)
                    // The person's own looks like any other, its count in bold, as on the web; no outline.
                    .fontWeight(summary.isMine ? .bold : .regular)
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
    /// pill, the bar itself see-through so messages run under it with the
    /// system's soft edge, and on a phone the tab bar gives way.
    func conversationBar(title: String, onTitleTap: (() -> Void)? = nil, isCallStageShown: Bool = false) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .hidesTabBarWhenCompact()
            .scrollEdgeEffectStyle(.hard, for: .top)
            .modifier(ConversationTitlePill(title: title, onTitleTap: onTitleTap, isCallStageShown: isCallStageShown))
    }
}

/// ConversationTitlePill puts a conversation's title in its bar: in the middle on a phone, and at the leading
/// edge on a wide screen, where the floating tab bar takes the middle of the top row whenever the bar shares it
/// (in landscape, or with the list of conversations hidden).
private struct ConversationTitlePill: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let onTitleTap: (() -> Void)?
    /// On a phone a call's stage takes the middle of the bar, where the title would be.
    let isCallStageShown: Bool

    /// maximumWideWidth keeps a long title clear of the floating tab bar.
    private let maximumWideWidth: CGFloat = 300

    func body(content: Content) -> some View {
        let isWide = horizontalSizeClass == .regular
        content.toolbar {
            if isWide || !isCallStageShown {
                ToolbarItem(placement: isWide ? .topBarLeading : .principal) {
                    pill.frame(maxWidth: isWide ? maximumWideWidth : nil, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private var pill: some View {
        if let onTitleTap {
            Button(action: onTitleTap) { titlePill(title) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows who is in this chat"))
        } else {
            titlePill(title)
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

/// AvatarImageMemory holds the decoded pictures of one session, so a row that scrolls back into view draws its picture at once, with no moment of initials.
final class AvatarImageMemory: @unchecked Sendable {
    private let images = NSCache<NSString, UIImage>()

    init() { images.countLimit = 300 }

    func image(for subject: AvatarSubject) -> UIImage? { images.object(forKey: subject.cacheKey as NSString) }
    func store(_ image: UIImage, for subject: AvatarSubject) { images.setObject(image, forKey: subject.cacheKey as NSString) }
}

/// UserAvatar is a person's picture, or their initials on the same tinted circle when they have none or it has not arrived. Where the list
/// does not say whether the person has a picture (`hasAvatar` nil), it is asked for and the initials stay if there is none.
struct UserAvatar: View {
    @Environment(SessionModel.self) private var session
    let userId: String?
    let name: String
    var hasAvatar: Bool?
    var modifiedAt: String?
    var size: CGFloat = 28
    var isAssistant = false

    @State private var loaded: UIImage?

    private var subject: AvatarSubject? {
        guard let userId, !userId.isEmpty, hasAvatar != false, !isAssistant else { return nil }
        return AvatarSubject(kind: .user, id: userId, modifiedAt: modifiedAt)
    }

    var body: some View {
        AvatarPicture(subject: subject, loaded: $loaded) {
            PersonAvatar(name: name, size: size, isAssistant: isAssistant)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// OrganizationAvatar is an organization's logo on a rounded square, or a building symbol when it has none.
struct OrganizationAvatar: View {
    let organizationId: String
    var hasLogo: Bool?
    var modifiedAt: String?
    var size: CGFloat = 28

    @State private var loaded: UIImage?

    var body: some View {
        AvatarPicture(subject: hasLogo == true ? AvatarSubject(kind: .organization, id: organizationId, modifiedAt: modifiedAt) : nil, loaded: $loaded) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22).fill(Color(.tertiarySystemFill))
                Image(systemName: "building.2").font(.system(size: size * 0.45)).foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}

/// AvatarPicture draws the placeholder, and fades the picture in over it once it is held: the placeholder never goes away first, so nothing flashes.
private struct AvatarPicture<Placeholder: View>: View {
    @Environment(SessionModel.self) private var session
    let subject: AvatarSubject?
    @Binding var loaded: UIImage?
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        let shown = loaded ?? subject.flatMap { session.avatarImages.image(for: $0) }
        ZStack {
            placeholder()
            if let shown {
                Image(uiImage: shown).resizable().scaledToFill().transition(.opacity)
            }
        }
        .task(id: subject?.cacheKey) {
            guard let subject else { loaded = nil; return }
            if let held = session.avatarImages.image(for: subject) { loaded = held; return }
            guard let data = await session.avatars.data(for: subject), let image = UIImage(data: data) else { return }
            session.avatarImages.store(image, for: subject)
            withAnimation(.easeOut(duration: 0.15)) { loaded = image }
        }
    }
}

/// ChatAvatar stands for a chat in a list: the other person's picture for a direct chat, two overlapping for a group.
struct ChatAvatar: View {
    @Environment(SessionModel.self) private var session
    let room: ChatRoom
    var size: CGFloat = 44

    var body: some View {
        let members = room.avatarMembers(excluding: session.account.userId)
        if room.isSite {
            Image(systemName: "building.2.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.16), in: Circle())
        } else if room.isGroup, members.count > 1 {
            AvatarStack(members: members, size: size)
        } else {
            UserAvatar(userId: members.first?.userId, name: room.title, size: size)
        }
    }
}

extension View {
    /// A search field over a list of people, on the screens where the list can be long.
    @ViewBuilder func searchablePeople(isOn: Bool, text: Binding<String>) -> some View {
        if isOn {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search people")
        } else {
            self
        }
    }
}

/// AvatarStack is the two overlapping pictures that stand for a group.
struct AvatarStack: View {
    let members: [ChatMember]
    var size: CGFloat = 44

    var body: some View {
        let smaller = size * 0.68
        ZStack {
            if let first = members.first {
                UserAvatar(userId: first.userId, name: first.shownName, size: smaller)
                    .frame(width: size, height: size, alignment: .topLeading)
            }
            if members.count > 1 {
                UserAvatar(userId: members[1].userId, name: members[1].shownName, size: smaller)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .frame(width: size, height: size, alignment: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
    }
}

/// StableBubble draws its content again only when `key` changes. A message bubble is keyed by the message and what is
/// drawn on it, so an update elsewhere (a presence report, a read marker, another message arriving) does not draw
/// the pressed bubble again while its menu is open, which is what made it flicker.
struct StableBubble<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content

    var body: some View { content() }

    nonisolated static func == (first: StableBubble, second: StableBubble) -> Bool { first.key == second.key }
}

/// StatusValueRow is a title with a status beside it: a symbol and one word. At the large text sizes, where the two do not fit on a
/// line, the status goes under the title, whole; a word is never broken. Its separator starts at the row's edge.
struct StatusValueRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: LocalizedStringKey

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                valueView
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                valueView
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private var valueView: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(value).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.secondary)
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

/// TypingBubble is the assistant's bubble while it works and has not yet said anything: three dots that rise and
/// brighten in turn on a 1.2 second beat. It is the size of a short assistant message, so the answer takes its place
/// without a jump. The web chat box shows the same dots.
struct TypingBubble: View {
    var body: some View {
        HStack(spacing: 0) {
            TypingDots()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 56)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Thinking\u{2026}"))
        .accessibilityIdentifier("typingBubble")
    }
}

/// TypingDots is the one way the app shows the assistant at work: three dots rising in turn. The typing bubble holds them where
/// the answer will appear; a line that points at work happening elsewhere (a thread, the background) holds them smaller.
struct TypingDots: View {
    var dotSize: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var isReducingMotion
    private static let beat = 1.2

    var body: some View {
        TimelineView(.animation(paused: isReducingMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: dotSize * 5 / 8) {
                ForEach(0..<3, id: \.self) { index in
                    // Each dot peaks a sixth of a beat after the one before it.
                    let phase = (time / Self.beat - Double(index) / 6).truncatingRemainder(dividingBy: 1)
                    let level = isReducingMotion ? 0 : (1 - cos(2 * Double.pi * (phase < 0 ? phase + 1 : phase))) / 2
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: dotSize, height: dotSize)
                        .opacity(0.4 + 0.6 * level)
                        .offset(y: -dotSize * 3 / 8 * level)
                }
            }
            .padding(.vertical, dotSize * 3 / 8)
        }
        .accessibilityHidden(true)
    }
}

/// HidesTabBarWhenCompact gives a pushed screen the whole phone. On a wide screen the tab bar stays: a split view
/// shows its detail with no back button to bring the bar back, and on iPad that bar can be the only way to leave.
private struct HidesTabBarWhenCompact: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.toolbarVisibility(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
    }
}

extension View {
    func hidesTabBarWhenCompact() -> some View {
        modifier(HidesTabBarWhenCompact())
    }
}
