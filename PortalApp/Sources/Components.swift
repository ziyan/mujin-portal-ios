import PortalKit
import SwiftUI

/// DictationControl is the microphone button of a composer: it starts and stops dictating into the box.
struct DictationControl {
    let isListening: Bool
    let isEnabled: Bool
    let action: () -> Void
}

/// ComposerCard is where the person writes, on every screen that has a box. At rest it is one pill: [+], the prompt, the microphone and
/// send. While the person types, has something attached or has written more than one line, it is a card: what is attached on top,
/// the words across the full width, and [+] at the bottom left with the microphone and send at the bottom right. Every button sits
/// inside the box, which is the only bordered shape: [+] and the microphone are tonal circles, send is a filled accent circle (quiet
/// gray with nothing to send) and becomes a square Stop while a turn runs.
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

    /// More for the [+] menu than attaching files: talking, and the screen's own choices.
    var menuItems: [ComposerMenuItem] = []
    /// Whether the next send is an internal note: the box turns amber.
    var isInternalNote = false
    /// The Staff only switch, for staff in a chat a customer reads: a chip beside [+] in the card, a lock in the pill.
    var internalNoteSwitch: InternalNoteSwitch?

    @State private var isFocused = false
    /// The round buttons grow with the text, held where their symbols stay inside them.
    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 36
    private var diameter: CGFloat { min(scaledDiameter, 60) }
    private static var cornerRadius: CGFloat { 24 }
    private static var inset: CGFloat { 8 }

    /// How wide the words are while the composer is a pill, measured, so the pill knows when the words would need a second line.
    @State private var pillFieldWidth: CGFloat = 0

    /// The card: words across its whole width with the buttons on a row beneath, while the person types, has something attached or has
    /// written more than one line. Otherwise one pill: [+], the words, the microphone and send in a row.
    private var isExpanded: Bool {
        isFocused || !(drafts?.items.isEmpty ?? true) || text.contains("\n") || wrapsInPill
    }

    /// Whether the words need a second line at the pill's width, in the text view's own font and at the current text size.
    private var wrapsInPill: Bool {
        guard !text.isEmpty, pillFieldWidth > 0 else { return false }
        return ComposerMeasure.needsSecondLine(text, width: pillFieldWidth)
    }

    var body: some View {
        // One layout for both shapes, so the text view stays the same view: the keyboard, the caret and marked text survive the change.
        ComposerLayout(isExpanded: isExpanded, spacing: Self.inset) {
            Group {
                if let drafts, !drafts.items.isEmpty { AttachmentStrip(drafts: drafts) } else { Color.clear.frame(width: 0, height: 0) }
            }
            HStack(spacing: 4) {
                plusMenu
                accessory
                if let internalNoteSwitch {
                    if isExpanded {
                        StaffOnlyChip(internalNoteSwitch: internalNoteSwitch)
                    } else {
                        StaffOnlyLockButton(internalNoteSwitch: internalNoteSwitch, diameter: diameter)
                    }
                }
            }
            field
            trailingButtons
        }
        .padding(Self.inset)
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        // A tap on the box outside its buttons starts typing.
        .background {
            Color.clear
                .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
                .onTapGesture { isFocused = true }
        }
        .background(isInternalNote ? AnyShapeStyle(Color.statusWarning.opacity(0.16)) : AnyShapeStyle(Color.portalCard.opacity(0.92)), in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 720 + 32)
        .frame(maxWidth: .infinity)
    }

    /// The words, with the prompt drawn over the empty box on one line that ends in an ellipsis: the prompt never makes the box taller.
    private var field: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Color(.placeholderText))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        // The width the words have in the pill: measured only while it is one, since the card's is wider.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if !isExpanded { pillFieldWidth = width }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    /// [+]: attach a photo or a file, talk, and the screen's own choices. Hidden when there is nothing in it.
    @ViewBuilder private var plusMenu: some View {
        let items = menuItems + (onVoice.map { [ComposerMenuItem(title: "Talk", systemImage: "waveform", identifier: "voiceButton", action: $0)] } ?? [])
        if drafts != nil || !items.isEmpty {
            ComposerPlusMenu(drafts: drafts, items: items, diameter: diameter)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    /// The microphone and send, at the right of the pill or of the card's last row. While a turn runs, send is a square Stop.
    private var trailingButtons: some View {
        HStack(spacing: 4) {
            if let dictation {
                // Listening, it is tinted.
                Button(action: dictation.action) {
                    Image(systemName: "mic")
                        .font(.body.weight(.medium))
                        .foregroundStyle(dictation.isListening ? Color.accentColor : Color.secondary)
                        .frame(width: diameter, height: diameter)
                        .background(dictation.isListening ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .disabled(!dictation.isEnabled)
                .accessibilityLabel(dictation.isListening ? Text("Stop dictating") : Text("Dictate"))
                .accessibilityIdentifier("dictateButton")
            }
            if let onStop {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.onAccent)
                        .frame(width: diameter, height: diameter)
                        .background(Color.accentColor, in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Stop")
            } else {
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
        }
        // Past a point the buttons stop growing with the text.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// InternalNoteSwitch is whether the next send is an internal note only Mujin staff read, and whether the person may change it: inside an
/// internal thread, or replying to an internal note, it is held on.
struct InternalNoteSwitch {
    let isOn: Bool
    let isLocked: Bool
    let onToggle: () -> Void
}

/// StaffOnlyChip is the Staff only switch in the composer's card beside [+]: outlined while off, amber while on, and held on with its
/// lock where the thread or the message replied to is internal.
struct StaffOnlyChip: View {
    let internalNoteSwitch: InternalNoteSwitch

    var body: some View {
        Button(action: internalNoteSwitch.onToggle) {
            Label("Staff only", systemImage: internalNoteSwitch.isOn ? "lock.fill" : "lock.open")
                .font(.caption.weight(.semibold))
                .foregroundStyle(internalNoteSwitch.isOn ? Color.statusWarning : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(internalNoteSwitch.isOn ? Color.statusWarning.opacity(0.16) : Color.clear, in: Capsule())
                .overlay {
                    if !internalNoteSwitch.isOn { Capsule().strokeBorder(Color.gray.opacity(0.4), lineWidth: 1) }
                }
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(internalNoteSwitch.isLocked)
        .accessibilityLabel(Text("Staff only"))
        .accessibilityValue(internalNoteSwitch.isOn ? Text("On") : Text("Off"))
        .accessibilityHint(internalNoteSwitch.isLocked ? Text("This thread is internal") : Text("Only Mujin staff read what you send"))
        .accessibilityAddTraits(internalNoteSwitch.isOn ? .isSelected : [])
        .accessibilityIdentifier("staffOnlyChip")
    }
}

/// StaffOnlyLockButton is the Staff only switch while the composer is a pill: a small lock beside [+], amber while on.
struct StaffOnlyLockButton: View {
    let internalNoteSwitch: InternalNoteSwitch
    let diameter: CGFloat

    var body: some View {
        Button(action: internalNoteSwitch.onToggle) {
            Image(systemName: internalNoteSwitch.isOn ? "lock.fill" : "lock.open")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(internalNoteSwitch.isOn ? Color.statusWarning : Color.secondary)
                .frame(width: diameter, height: diameter)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(internalNoteSwitch.isLocked)
        .accessibilityLabel(Text("Staff only"))
        .accessibilityValue(internalNoteSwitch.isOn ? Text("On") : Text("Off"))
        .accessibilityAddTraits(internalNoteSwitch.isOn ? .isSelected : [])
        .accessibilityIdentifier("staffOnlyLock")
    }
}

/// InternalNoteLabel marks an internal note in a chat: a lock and the word Internal.
struct InternalNoteLabel: View {
    var body: some View {
        Label("Internal", systemImage: "lock.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.statusWarning)
            .labelStyle(.titleAndIcon)
            .accessibilityIdentifier("internalNoteLabel")
    }
}

/// ComposerMeasure tells whether words fit one line of the composer's text view, which sets them in the body font with no insets.
enum ComposerMeasure {
    static func needsSecondLine(_ text: String, width: CGFloat, font: UIFont = UIFont.preferredFont(forTextStyle: .body)) -> Bool {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        return bounds.height > font.lineHeight * 1.5
    }
}

/// ComposerMenuItem is one choice of the composer's [+] menu beyond attaching: talking, or a choice of the screen's own. One with
/// `isOn` set is a check item.
struct ComposerMenuItem: Identifiable {
    let title: LocalizedStringKey
    let systemImage: String
    var identifier: String
    var isOn: Bool?
    var isDisabled = false
    let action: () -> Void
    var id: String { identifier }

    init(title: LocalizedStringKey, systemImage: String, identifier: String, isOn: Bool? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.identifier = identifier
        self.isOn = isOn
        self.isDisabled = isDisabled
        self.action = action
    }
}

/// ComposerPlusMenu is the [+] of the composer: a filled tonal circle that opens the ways to attach, then the composer's other choices.
private struct ComposerPlusMenu: View {
    let drafts: AttachmentDrafts?
    let items: [ComposerMenuItem]
    let diameter: CGFloat

    var body: some View {
        Menu {
            if let drafts { AttachMenuItems(drafts: drafts) }
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        if let isOn = item.isOn {
                            Toggle(isOn: Binding(get: { isOn }, set: { _ in item.action() })) { Label(item.title, systemImage: item.systemImage) }
                                .disabled(item.isDisabled)
                                .accessibilityIdentifier(item.identifier)
                        } else {
                            Button(action: item.action) { Label(item.title, systemImage: item.systemImage) }
                                .disabled(item.isDisabled)
                                .accessibilityIdentifier(item.identifier)
                        }
                    }
                }
            }
        } label: {
            Label("More", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: diameter, height: diameter)
                .background(Color(.tertiarySystemFill), in: .circle)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityIdentifier("attachMenu")
    }
}

/// ComposerLayout places the composer's parts as one pill or as a card. Its subviews come in a fixed order: what is attached, the
/// leading buttons, the words, and the trailing buttons. The pill is a single row with the words between the buttons and nothing
/// attached; the card puts what is attached on top, the words across the full width, and the buttons on a row beneath.
struct ComposerLayout: Layout {
    var isExpanded: Bool
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let leading = subviews[1].sizeThatFits(.unspecified)
        let trailing = subviews[3].sizeThatFits(.unspecified)
        if isExpanded {
            let attached = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let field = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let attachedHeight = attached.height > 0 ? attached.height + spacing : 0
            return CGSize(width: width, height: attachedHeight + field.height + spacing / 2 + max(leading.height, trailing.height))
        }
        let field = subviews[2].sizeThatFits(ProposedViewSize(width: fieldWidth(width, leading, trailing), height: nil))
        return CGSize(width: width, height: max(leading.height, trailing.height, field.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let leading = subviews[1].sizeThatFits(.unspecified)
        let trailing = subviews[3].sizeThatFits(.unspecified)
        if isExpanded {
            var y = bounds.minY
            let attached = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: attached.height))
            if attached.height > 0 { y += attached.height + spacing }
            let field = subviews[2].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[2].place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: field.height))
            y += field.height + spacing / 2
            let rowHeight = max(leading.height, trailing.height)
            subviews[1].place(at: CGPoint(x: bounds.minX, y: y + rowHeight / 2), anchor: .leading, proposal: .unspecified)
            subviews[3].place(at: CGPoint(x: bounds.maxX, y: y + rowHeight / 2), anchor: .trailing, proposal: .unspecified)
            return
        }
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: .zero)
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        let width = fieldWidth(bounds.width, leading, trailing)
        let field = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: nil))
        subviews[2].place(
            at: CGPoint(x: bounds.minX + leading.width + (leading.width > 0 ? spacing : 0), y: bounds.midY), anchor: .leading,
            proposal: ProposedViewSize(width: width, height: field.height))
        subviews[3].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
    }

    private func fieldWidth(_ width: CGFloat, _ leading: CGSize, _ trailing: CGSize) -> CGFloat {
        max(width - leading.width - trailing.width - (leading.width > 0 ? spacing : 0) - spacing, 0)
    }
}

extension ComposerCard {
    /// The card with a view of the screen's own beside the attach button.
    init(
        placeholder: LocalizedStringKey, text: Binding<String>, drafts: AttachmentDrafts? = nil, isEnabled: Bool = true, canSend: Bool,
        isSending: Bool = false, sendSymbol: String = "arrow.up", sendLabel: LocalizedStringKey = "Send", dictation: DictationControl? = nil,
        fieldIdentifier: String = "messageField", sendIdentifier: String = "sendButton", onEscape: (() -> Bool)? = nil,
        isInternalNote: Bool = false, internalNoteSwitch: InternalNoteSwitch? = nil, menuItems: [ComposerMenuItem] = [], onSend: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            placeholder: placeholder, text: text, drafts: drafts, isEnabled: isEnabled, canSend: canSend, isSending: isSending, sendSymbol: sendSymbol,
            sendLabel: sendLabel, onVoice: nil, onStop: nil, dictation: dictation, fieldIdentifier: fieldIdentifier, sendIdentifier: sendIdentifier, onEscape: onEscape,
            onSend: onSend, accessory: accessory, menuItems: menuItems, isInternalNote: isInternalNote, internalNoteSwitch: internalNoteSwitch)
    }
}

extension ComposerCard where Accessory == EmptyView {
    init(
        placeholder: LocalizedStringKey, text: Binding<String>, drafts: AttachmentDrafts? = nil, isEnabled: Bool = true, canSend: Bool,
        isSending: Bool = false, sendSymbol: String = "arrow.up", sendLabel: LocalizedStringKey = "Send", onVoice: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil, dictation: DictationControl? = nil, fieldIdentifier: String = "messageField", sendIdentifier: String = "sendButton",
        onEscape: (() -> Bool)? = nil, isInternalNote: Bool = false, internalNoteSwitch: InternalNoteSwitch? = nil, menuItems: [ComposerMenuItem] = [],
        onSend: @escaping () -> Void
    ) {
        self.init(
            placeholder: placeholder, text: text, drafts: drafts, isEnabled: isEnabled, canSend: canSend, isSending: isSending, sendSymbol: sendSymbol,
            sendLabel: sendLabel, onVoice: onVoice, onStop: onStop, dictation: dictation, fieldIdentifier: fieldIdentifier, sendIdentifier: sendIdentifier, onEscape: onEscape,
            onSend: onSend, accessory: { EmptyView() }, menuItems: menuItems, isInternalNote: isInternalNote, internalNoteSwitch: internalNoteSwitch)
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
        // During a call the stage names who it is with; the bar shows no title of its own.
        navigationTitle(isCallStageShown ? "" : title)
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
    /// A call's stage names who the call is with, so the pill steps aside while it shows.
    let isCallStageShown: Bool

    /// maximumWideWidth keeps a long title clear of the floating tab bar.
    private let maximumWideWidth: CGFloat = 300

    func body(content: Content) -> some View {
        let isWide = horizontalSizeClass == .regular
        content
            // On a wide screen the pill stands at the leading edge, so the bar's own title in the middle would say it twice.
            .toolbar(removing: isWide ? .title : nil)
            .toolbar {
                if !isCallStageShown {
                    ToolbarItem(placement: isWide ? .topBarLeading : .principal) {
                        // As wide as the title, up to the limit: a leading item is otherwise squeezed into a round button.
                        pill.frame(maxWidth: isWide ? maximumWideWidth : nil, alignment: .leading)
                            .fixedSize(horizontal: isWide, vertical: false)
                    }
                    // The pill is its own glass; the bar's shared glass around it would draw a second shape.
                    .sharedBackgroundVisibility(.hidden)
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
    /// Whether the person is Mujin staff, which puts the staff mark on the avatar's corner.
    var isStaff = false
    /// The surface the avatar sits on, which the staff mark's ring takes.
    var surfaceColor = Color.portalCard

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
        .overlay(alignment: .bottomTrailing) {
            if isStaff { StaffMark(avatarSize: size, ringColor: surfaceColor) }
        }
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
