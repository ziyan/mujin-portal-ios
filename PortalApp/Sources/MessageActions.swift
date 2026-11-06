import PortalKit
import SwiftUI
import UIKit

/// MessageActions is what can be done with a message that is held: react to
/// it, answer it, and work with its text. A closure that is nil is an action
/// the message does not offer, and its row is not shown.
struct MessageActions {
    /// Names the message for the demo screens that open its actions.
    let messageId: String
    let text: String
    /// Whether the message is on the person's own side, which is the right.
    let isTrailing: Bool
    /// The emoji the person has put on the message, if any.
    let ownReaction: String?
    let onReact: ((String) -> Void)?
    let onReply: (() -> Void)?
    let onEdit: (() -> Void)?
    let onRemoveLinkPreviews: (() -> Void)?
    let onDelete: (() -> Void)?
    /// Set by the bubble that holds the message, which owns the sheet for it.
    var onSelect: () -> Void = {}
    /// Puts the address of the message on the pasteboard. Nil for a message that is not stored yet.
    var onCopyLink: (() -> Void)?
}

/// HoldableMessage is a message bubble that opens its actions on a long press.
/// The actions are also offered to VoiceOver, which has no long press.
struct HoldableMessage<Bubble: View>: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let actions: MessageActions?
    let bubble: Bubble
    @State private var bubbleWidth: CGFloat = 0
    @State private var selectingText: SelectingText?

    init(actions: MessageActions?, @ViewBuilder bubble: () -> Bubble) {
        self.actions = actions
        self.bubble = bubble()
    }

    var body: some View {
        bubble
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in bubbleWidth = width }
            // Simultaneous, so the press never competes with a tap on a link in the text for the same touch.
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in present() })
            .accessibilityActions {
                if let actions {
                    if let onReply = actions.onReply { Button("Reply", action: onReply) }
                    if let onEdit = actions.onEdit { Button("Edit", action: onEdit) }
                    Button("Copy") { UIPasteboard.general.string = actions.text }
                    if let onCopyLink = actions.onCopyLink { Button("Copy link", action: onCopyLink) }
                    Button("Select") { selectingText = SelectingText(text: actions.text) }
                    if let onReact = actions.onReact {
                        ForEach(Reactions.palette, id: \.self) { emoji in
                            Button { onReact(emoji) } label: { Text("React \(emoji)") }
                        }
                    }
                    if let onDelete = actions.onDelete { Button("Delete", action: onDelete) }
                }
            }
            .sheet(item: $selectingText) { selecting in
                SelectTextSheet(text: selecting.text)
            }
            .task {
                guard let actions, appModel.isDemo, let screen = DemoOptions.screen else { return }
                let isOpening = (screen == "message-actions" && actions.messageId == "m04") || (screen == "chat-message-actions" && actions.messageId == "c10")
                if isOpening || (screen == "select-text" && actions.messageId == "m04") {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if isOpening { present() } else { selectingText = SelectingText(text: actions.text) }
                }
            }
    }

    private func present() {
        guard var actions else { return }
        let text = actions.text
        actions.onSelect = { selectingText = SelectingText(text: text) }
        MessageActionsPresenter.present(actions, bubble: AnyView(bubble), bubbleWidth: bubbleWidth, appModel: appModel, session: session)
    }
}

/// MessageActionsPresenter opens a message's actions over the whole screen,
/// as Messages does on a long press: everything else dims and blurs, the
/// message stays readable, and what can be done with it sits around it. It is
/// shown from the top of the window so it covers the bars and the composer.
@MainActor
enum MessageActionsPresenter {
    static func present(_ actions: MessageActions, bubble: AnyView, bubbleWidth: CGFloat, appModel: AppModel, session: SessionModel) {
        guard let top = topViewController() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        weak var shown: UIViewController?
        let controller = UIHostingController(
            rootView: MessageActionsView(actions: actions, bubble: bubble, bubbleWidth: bubbleWidth) { then in
                shown?.dismiss(animated: true) { then?() }
            }
            // A view hosted from UIKit does not carry the screen's environment.
            .environment(appModel)
            .environment(session)
            // The held message is for reading; a link in it is not followed from here.
            .environment(\.openURL, OpenURLAction { _ in .handled }))
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        controller.view.backgroundColor = .clear
        shown = controller
        top.present(controller, animated: true)
    }

    /// The view controller that anything shown over the screen is presented from.
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// MessageActionsView is a message held: the quick reactions above it, the
/// message itself on its own side with its whole text scrolling when it is
/// long, and its actions below as full rows.
struct MessageActionsView: View {
    let actions: MessageActions
    let bubble: AnyView
    let bubbleWidth: CGFloat
    /// Closes the view, then does what was chosen, if anything.
    let onClose: (((() -> Void)?) -> Void)
    @Environment(\.accessibilityReduceMotion) private var isMotionReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShown = false
    /// Whether the emoji keyboard is open to choose a reaction that is not in
    /// the bar. The bar gives way to a line saying so.
    @State private var isChoosingEmoji = false
    @State private var actionsHeight: CGFloat = 300
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    private var side: HorizontalAlignment { actions.isTrailing ? .trailing : .leading }
    private var frameAlignment: Alignment { actions.isTrailing ? .trailing : .leading }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { onClose(nil) }
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
                VStack(alignment: side, spacing: 12) {
                    if actions.onReact != nil {
                        if isChoosingEmoji { emojiChooser } else { reactionBar }
                    }
                    ScrollView {
                        bubble
                            .frame(width: bubbleWidth > 0 ? min(bubbleWidth, proxy.size.width - 32) : nil, alignment: frameAlignment)
                            .frame(maxWidth: .infinity, alignment: frameAlignment)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: max(120, proxy.size.height - actionsHeight - 150))
                    .fixedSize(horizontal: false, vertical: true)
                    if !isChoosingEmoji {
                        // At the accessibility sizes the menu takes the full width, so no title is broken mid-word.
                        let availableWidth = min(proxy.size.width - 32, 560)
                        menu(width: dynamicTypeSize.isAccessibilitySize ? availableWidth : max(240, availableWidth * 0.6))
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal)
                .scaleEffect(isShown || isMotionReduced ? 1 : 0.94, anchor: actions.isTrailing ? .trailing : .leading)
                .opacity(isShown ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            withAnimation(isMotionReduced ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.2)) { isShown = true }
        }
        .accessibilityAction(.escape) { onClose(nil) }
    }

    /// The quick reactions in one evenly spaced row, then a button for any
    /// other emoji. The person's current one is marked, and shown at the end
    /// when it is not one of the quick ones; choosing it again takes it away.
    private var reactionBar: some View {
        var choices = Reactions.palette
        if let current = actions.ownReaction, !choices.contains(current) { choices.append(current) }
        return HStack(spacing: 0) {
            ForEach(choices, id: \.self) { emoji in
                Button {
                    onClose { actions.onReact?(emoji) }
                } label: {
                    Text(verbatim: emoji)
                        .font(.system(size: 24))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(actions.ownReaction == emoji ? Color.accentColor.opacity(0.3) : .clear, in: .circle)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actions.ownReaction == emoji ? Text("Take away \(emoji)") : Text("React \(emoji)"))
            }
            Button {
                isChoosingEmoji = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: .circle)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More emoji")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }

    /// What the bar becomes while the emoji keyboard is open: a line saying
    /// to choose, and a way back. The field that takes the keyboard's emoji
    /// is behind it, one point across and drawn with nothing.
    private var emojiChooser: some View {
        HStack(spacing: 8) {
            Image(systemName: "face.smiling")
                .foregroundStyle(.secondary)
            Text("Choose any emoji")
                .font(.callout)
            Button {
                isChoosingEmoji = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .glassEffect(.regular, in: .capsule)
        .background {
            EmojiKeyboardField { emoji in
                onClose { actions.onReact?(emoji) }
            }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func menu(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let onReply = actions.onReply {
                row("Reply", systemImage: "arrowshape.turn.up.left") { onClose { onReply() } }
                Divider()
            }
            if let onEdit = actions.onEdit {
                row("Edit", systemImage: "pencil") { onClose { onEdit() } }
                Divider()
            }
            row("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = actions.text
                onClose(nil)
            }
            if let onCopyLink = actions.onCopyLink {
                Divider()
                row("Copy link", systemImage: "link") { onClose { onCopyLink() } }
            }
            Divider()
            row("Select", systemImage: "selection.pin.in.out") { onClose { actions.onSelect() } }
            Divider()
            ShareLink(item: actions.text) {
                rowLabel("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            if let onRemoveLinkPreviews = actions.onRemoveLinkPreviews {
                Divider()
                row("Remove link previews", systemImage: "link.badge.plus") { onClose { onRemoveLinkPreviews() } }
            }
            if let onDelete = actions.onDelete {
                Divider()
                Button {
                    onClose { onDelete() }
                } label: {
                    rowLabel("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: width)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height in actionsHeight = height }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: iconWidth)
            Text(title)
                .lineLimit(1).minimumScaleFactor(0.5)
            Spacer()
        }
        .font(.body)
        .padding(.horizontal, 18)
        .frame(minHeight: 50)
        .contentShape(.rect)
    }
}

/// SelectingText is a message opened to select from.
struct SelectingText: Identifiable {
    let text: String
    var id: String { text }
}

/// SelectTextSheet shows a message's words to select part of them, which a
/// bubble cannot do while a long press opens its actions.
struct SelectTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableText(text: text)
                .navigationTitle("Select text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// SelectableText is text to select but not change. SwiftUI's text
/// selection takes a whole Text at once, so a UITextView does it.
struct SelectableText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}

/// EmojiTextField is a text field that opens on the emoji keyboard, which the
/// system has no call to open, by answering which input mode it takes. A
/// person with no emoji keyboard gets the ordinary one, and anything typed on
/// it that is not an emoji is ignored. It takes the keyboard as soon as it is
/// on screen.
final class EmojiTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }
}

/// EmojiKeyboardField is the emoji keyboard for choosing one emoji: an
/// invisible field takes it, and the first emoji typed is handed to
/// `onEmoji`, once.
struct EmojiKeyboardField: UIViewRepresentable {
    let onEmoji: (String) -> Void

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.textColor = .clear
        field.tintColor = .clear
        field.backgroundColor = .clear
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.onEmoji = onEmoji
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEmoji: onEmoji)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var onEmoji: (String) -> Void
        private var hasChosen = false

        init(onEmoji: @escaping (String) -> Void) {
            self.onEmoji = onEmoji
        }

        @objc func textChanged(_ field: UITextField) {
            guard !hasChosen, let emoji = Reactions.firstEmoji(in: field.text ?? "") else { return }
            hasChosen = true
            field.text = ""
            onEmoji(emoji)
        }
    }
}
