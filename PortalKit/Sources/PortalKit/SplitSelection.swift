/// SplitSelection is which conversation a list and detail layout shows. On a phone the two columns are one stack, and the list
/// clears its selection whenever it appears: a sheet closing over it, or a swipe back that is cancelled. The conversation stays
/// on top of the stack all the same, so while it does the detail keeps it rather than falling back to its empty pane.
public struct SplitSelection: Equatable, Sendable {
    /// What the list has selected, which is nil again once it clears it.
    public var selectedId: String? {
        didSet {
            guard let selectedId else { return }
            lastSelectedId = selectedId
            isDetailOnTop = true
        }
    }

    /// Whether the phone shows the detail, which the split view says when the person goes back to the list.
    public var isDetailOnTop = false

    private var lastSelectedId: String?

    public init() {}

    /// The conversation the detail column draws. Side by side the list's selection is plain to see, so it alone decides. On a
    /// phone nothing is kept once the person has gone back: what the detail draws still sets the bars, such as hiding the tab bar.
    public func detailId(isCompact: Bool) -> String? {
        guard isCompact else { return selectedId }
        return isDetailOnTop ? lastSelectedId : nil
    }
}
