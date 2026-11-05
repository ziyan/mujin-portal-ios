/// SplitSelection is which conversation a list and detail layout shows. On a phone the two columns are one stack, and the list
/// clears its selection whenever it appears: a sheet closing over it, or a swipe back that is cancelled. The conversation stays
/// on top of the stack all the same, so on a phone the detail keeps the last one rather than falling back to its empty pane.
public struct SplitSelection: Equatable, Sendable {
    /// What the list has selected, which is nil again once it clears it.
    public var selectedId: String? {
        didSet { if let selectedId { lastSelectedId = selectedId } }
    }

    private var lastSelectedId: String?

    public init() {}

    /// The conversation the detail column draws. Side by side the list's selection is plain to see, so it alone decides.
    public func detailId(isCompact: Bool) -> String? {
        isCompact ? lastSelectedId : selectedId
    }
}
