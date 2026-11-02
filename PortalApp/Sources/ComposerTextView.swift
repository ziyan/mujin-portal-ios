import SwiftUI
import UIKit

/// PasteAwareTextView is the text view behind the composer. A picture on the
/// clipboard is handed to the composer as an attachment instead of being
/// refused, so the system Paste menu offers it; text on the clipboard still
/// pastes as text, even when a picture came with it. With a hardware keyboard,
/// Return sends and Shift+Return adds a line.
final class PasteAwareTextView: UITextView {
    var onPastePicture: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Bool)?

    private var isPastingPicture: Bool {
        onPastePicture != nil && UIPasteboard.general.hasImages && !UIPasteboard.general.hasStrings
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.paste(_:)), isPastingPicture { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if isPastingPicture {
            onPastePicture?()
            return
        }
        super.paste(sender)
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
/// because only a text view can take a picture from the system Paste menu.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var isEnabled = true
    var maximumLineCount = 8
    var onReturn: (() -> Void)?
    var onEscape: (() -> Bool)?
    var onPastePicture: (() -> Void)?

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
        return view
    }

    func updateUIView(_ view: PasteAwareTextView, context: Context) {
        context.coordinator.parent = self
        view.onPastePicture = onPastePicture
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
