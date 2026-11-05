import Testing

@testable import PortalKit

struct SplitSelectionTests {
    @Test func nothingIsDrawnBeforeAnythingIsChosen() {
        let selection = SplitSelection()
        #expect(selection.detailId(isCompact: true) == nil)
        #expect(selection.detailId(isCompact: false) == nil)
    }

    @Test func aPhoneKeepsTheConversationWhenTheListClearsItsSelection() {
        var selection = SplitSelection()
        selection.selectedId = "conversation01"
        selection.selectedId = nil
        #expect(selection.detailId(isCompact: true) == "conversation01")
    }

    @Test func goingBackLetsGoOfTheConversation() {
        var selection = SplitSelection()
        selection.selectedId = "conversation01"
        selection.selectedId = nil
        selection.isDetailOnTop = false
        #expect(selection.detailId(isCompact: true) == nil)
    }

    @Test func choosingTheSameConversationAgainShowsIt() {
        var selection = SplitSelection()
        selection.selectedId = "conversation01"
        selection.selectedId = nil
        selection.isDetailOnTop = false
        selection.selectedId = "conversation01"
        #expect(selection.detailId(isCompact: true) == "conversation01")
    }

    @Test func sideBySideTheDetailFollowsTheList() {
        var selection = SplitSelection()
        selection.selectedId = "conversation01"
        #expect(selection.detailId(isCompact: false) == "conversation01")
        selection.selectedId = "conversation02"
        #expect(selection.detailId(isCompact: false) == "conversation02")
    }

    @Test func aPhoneTurnedOnItsSideKeepsTheConversationOnTop() {
        var selection = SplitSelection()
        selection.selectedId = "conversation01"
        selection.selectedId = nil
        #expect(selection.detailId(isCompact: false) == "conversation01")
        selection.isDetailOnTop = false
        #expect(selection.detailId(isCompact: false) == nil)
    }

    @Test func anotherConversationReplacesTheOneKept() {
        var selection = SplitSelection()
        selection.selectedId = "conversation01"
        selection.selectedId = nil
        selection.selectedId = "conversation02"
        #expect(selection.detailId(isCompact: true) == "conversation02")
    }
}
