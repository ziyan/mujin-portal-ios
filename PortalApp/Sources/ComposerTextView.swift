import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// PasteAwareTextView is the text view behind the composer. Like Messages, a
/// Paste that holds one or more pictures attaches them to the draft, whatever
/// text came with them (an address, a file name); the text is typed in only
/// when it says something of its own (see PasteRule). Pictures dropped onto the
/// field are attached the same way. A Paste with no picture is the system's.
/// With a hardware keyboard, Return sends and Shift+Return adds a line.
final class PasteAwareTextView: UITextView {
    /// Takes the item providers of a Paste or drop that holds pictures, and returns the text to type with them.
    var onPasteItems: (@MainActor ([NSItemProvider]) async -> String?)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Bool)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.paste(_:)), onPasteItems != nil, UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if onPasteItems != nil {
            let providers = UIPasteboard.general.itemProviders
            if providers.contains(where: PastedPictures.isPicture) {
                attach(providers)
                return
            }
        }
        super.paste(sender)
    }

    override func paste(itemProviders: [NSItemProvider]) {
        if onPasteItems != nil, itemProviders.contains(where: PastedPictures.isPicture) {
            attach(itemProviders)
            return
        }
        super.paste(itemProviders: itemProviders)
    }

    private func attach(_ providers: [NSItemProvider]) {
        guard let onPasteItems else { return }
        Task { @MainActor [weak self] in
            if let text = await onPasteItems(providers) { self?.insertText(text) }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if markedTextRange == nil {
            for press in presses {
                guard let key = press.key else { continue }
                let hasModifier = !key.modifierFlags.isDisjoint(with: [.shift, .alternate, .command, .control])
                if key.keyCode == .keyboardReturnOrEnter, !hasModifier, let onReturn {
                    onReturn()
                    return
                }
                if key.keyCode == .keyboardEscape, let onEscape, onEscape() { return }
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

/// ComposerTextView is the composer's field: body text that grows from one
/// line to eight and then scrolls. It stands in for a SwiftUI TextField
/// because only a text view can take a picture from the system Paste menu
/// or from a drop.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var isEnabled = true
    var maximumLineCount = 8
    var onReturn: (() -> Void)?
    var onEscape: (() -> Bool)?
    var onPasteItems: (@MainActor ([NSItemProvider]) async -> String?)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PasteAwareTextView {
        let view = PasteAwareTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Accepting pictures as well as text is what lets one be dropped on the field.
        if onPasteItems != nil {
            view.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.image.identifier, UTType.text.identifier])
        }
        return view
    }

    func updateUIView(_ view: PasteAwareTextView, context: Context) {
        context.coordinator.parent = self
        view.onPasteItems = onPasteItems
        view.onReturn = onReturn
        view.onEscape = onEscape
        view.isEditable = isEnabled
        if view.text != text, view.markedTextRange == nil { view.text = text }
        if isFocused, isEnabled, !view.isFirstResponder {
            Task { @MainActor in _ = view.becomeFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: PasteAwareTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let lineHeight = (view.font ?? UIFont.preferredFont(forTextStyle: .body)).lineHeight
        let fittingHeight = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let tallest = (lineHeight * CGFloat(maximumLineCount)).rounded(.up)
        let height = min(max(fittingHeight, lineHeight.rounded(.up)), tallest)
        let shouldScroll = fittingHeight > tallest
        if view.isScrollEnabled != shouldScroll { view.isScrollEnabled = shouldScroll }
        return CGSize(width: width, height: height)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }
    }
}
