import Foundation

/// EarlierMessages is what the row at the top of a chat or conversation says about the history before the messages held, and how
/// far the person pulls past the top before more is read. More is read only on a deliberate pull, as pull to refresh is, never just
/// because the top came into view.
public enum EarlierMessages {
    /// The row's state.
    public enum RowState: Equatable, Sendable {
        /// The server holds earlier messages: pull down to read them.
        case more
        /// A page of earlier messages is being read.
        case loading
        /// The last read failed; the words say why, and the row offers to try again.
        case failed(String)
        /// Nothing is left before the first message held.
        case start

        /// Whether a pull reads more: there is more, or the last try failed.
        public var canLoad: Bool {
            switch self {
            case .more, .failed: true
            case .loading, .start: false
            }
        }

        /// A name for UI tests to read off the row.
        public var name: String {
            switch self {
            case .more: "more"
            case .loading: "loading"
            case .failed: "failed"
            case .start: "start"
            }
        }
    }

    /// How far past the top, in points, a pull has to go before letting go reads more.
    public static let armDistance: Double = 72

    public static func rowState(earlierCount: Int, isLoading: Bool, failure: String?) -> RowState {
        if isLoading { return .loading }
        if let failure { return .failed(failure) }
        return earlierCount > 0 ? .more : .start
    }

    /// How far a pull has gone toward reading more, from 0 to 1.
    public static func pullProgress(overscroll: Double) -> Double { min(max(overscroll / armDistance, 0), 1) }

    /// Whether letting go now reads more.
    public static func isArmed(overscroll: Double, state: RowState) -> Bool { state.canLoad && overscroll >= armDistance }
}
