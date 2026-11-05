import Testing

@testable import PortalKit

struct SplitSelectionTests {
    @Test func nothingIsDrawnBeforeAnythingIsChosen() {
        #expect(SplitSelection().detailId == nil)
    }

    @Test func theDetailFollowsTheList() {
        var selection = SplitSelection()
        selection.selectedId = "conversation01"
        #expect(selection.detailId == "conversation01")
        selection.selectedId = "conversation02"
        #expect(selection.detailId == "conversation02")
    }

    @Test func aConversationOnTopStaysWhenTheListClearsItsSelection() {
        var selection = SplitSelection()
        selection.open("conversation01")
        selection.selectedId = nil
        #expect(selection.detailId == "conversation01")
    }

    @Test func goingBackLetsGoOfTheConversation() {
        var selection = SplitSelection()
        selection.open("conversation01")
        selection.selectedId = nil
        selection.isDetailOnTop = false
        #expect(selection.detailId == nil)
    }

    @Test func aWriteFromTheListNeverPutsTheDetailOnTop() {
        var selection = SplitSelection()
        selection.open("conversation01")
        selection.isDetailOnTop = false
        selection.selectedId = "conversation01"
        #expect(!selection.isDetailOnTop)
    }

    @Test func openingTheSameConversationAgainShowsIt() {
        var selection = SplitSelection()
        selection.open("conversation01")
        selection.selectedId = nil
        selection.isDetailOnTop = false
        selection.open("conversation01")
        #expect(selection.isDetailOnTop)
        #expect(selection.detailId == "conversation01")
    }

    @Test func anotherConversationReplacesTheOneKept() {
        var selection = SplitSelection()
        selection.open("conversation01")
        selection.selectedId = nil
        selection.open("conversation02")
        selection.selectedId = nil
        #expect(selection.detailId == "conversation02")
    }
}
