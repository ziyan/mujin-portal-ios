import Testing

@testable import PortalKit

/// The row at the top of a chat: what it says, and how far a pull goes before it reads more.
@Suite struct EarlierMessagesTests {
    @Test func theRowSaysWhetherThereIsMoreWhileItLoadsAndWhenItFailed() {
        #expect(EarlierMessages.rowState(earlierCount: 12, isLoading: false, failure: nil) == .more)
        #expect(EarlierMessages.rowState(earlierCount: 0, isLoading: false, failure: nil) == .start)
        #expect(EarlierMessages.rowState(earlierCount: 12, isLoading: true, failure: nil) == .loading)
        #expect(EarlierMessages.rowState(earlierCount: 12, isLoading: false, failure: "Offline") == .failed("Offline"))
        #expect(EarlierMessages.RowState.failed("Offline").canLoad)
        #expect(!EarlierMessages.RowState.start.canLoad && !EarlierMessages.RowState.loading.canLoad)
    }

    @Test func onlyAPullPastTheSetDistanceReadsMore() {
        #expect(!EarlierMessages.isArmed(overscroll: 0, state: .more), "Reaching the top reads nothing.")
        #expect(!EarlierMessages.isArmed(overscroll: EarlierMessages.armDistance - 1, state: .more))
        #expect(EarlierMessages.isArmed(overscroll: EarlierMessages.armDistance, state: .more))
        #expect(EarlierMessages.isArmed(overscroll: 200, state: .failed("Offline")), "A pull tries a failed read again.")
        #expect(!EarlierMessages.isArmed(overscroll: 200, state: .start), "Nothing is left to read.")
        #expect(!EarlierMessages.isArmed(overscroll: 200, state: .loading))
        #expect(EarlierMessages.pullProgress(overscroll: EarlierMessages.armDistance / 2) == 0.5)
        #expect(EarlierMessages.pullProgress(overscroll: -10) == 0)
        #expect(EarlierMessages.pullProgress(overscroll: 500) == 1)
    }

    @Test func anArmedPullStaysArmedUntilItComesWellBack() {
        let wavering = EarlierMessages.armDistance - 4
        #expect(!EarlierMessages.isArmed(overscroll: wavering, state: .more, wasArmed: false), "Short of the distance, a pull is not armed.")
        #expect(EarlierMessages.isArmed(overscroll: wavering, state: .more, wasArmed: true), "A finger wavering at the distance stays armed.")
        #expect(!EarlierMessages.isArmed(overscroll: EarlierMessages.disarmDistance - 1, state: .more, wasArmed: true))
    }
}
