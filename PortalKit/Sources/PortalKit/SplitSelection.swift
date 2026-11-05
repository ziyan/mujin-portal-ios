/// SplitSelection is which conversation a list and detail layout shows. On a phone the two columns are one stack, and the list
/// clears its selection whenever it appears: a sheet closing over it, or a swipe back that is cancelled. The conversation stays
/// on top of the stack all the same, so while it does the detail keeps it rather than falling back to its empty pane.
public struct SplitSelection: Equatable, Sendable {
    /// What the list has selected. The list writes this itself, at any moment and with the value it already has, so a write says
    /// nothing about what is on top: taking one for "show the detail" would push a conversation back while the person leaves it.
    public var selectedId: String? {
        didSet { if let selectedId { lastSelectedId = selectedId } }
    }

    /// Whether the phone shows the detail. Only the split view and `open` set this.
    public var isDetailOnTop = false

    private var lastSelectedId: String?

    public init() {}

    /// Shows a conversation the app chose, such as one a notification named.
    public mutating func open(_ conversationId: String) {
        selectedId = conversationId
        isDetailOnTop = true
    }

    /// The conversation the detail column draws: the list's selection, or the last one while it is still on top. Nothing is kept
    /// once the person has gone back, since what the detail draws still sets the bars, such as hiding the tab bar.
    public var detailId: String? {
        selectedId ?? (isDetailOnTop ? lastSelectedId : nil)
    }
}
