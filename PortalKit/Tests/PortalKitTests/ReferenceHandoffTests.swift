import Testing

@testable import PortalKit

@Suite struct ReferenceHandoffTests {
    @Test(arguments: ["site", "controller", "virtual_controller", "ticket", "incident", "agent_run"])
    func eachKindIsTakenOnceByTheConversationItWasSetFor(kind: String) {
        var handoff = ReferenceHandoff()
        handoff.set(conversationId: "main01", viewing: Viewing(kind: kind, id: "thing01"), subject: "Example")
        #expect(handoff.conversationId == "main01")
        #expect(handoff.take(for: "other01") == nil)
        #expect(handoff.pending != nil)
        let taken = handoff.take(for: "main01")
        #expect(taken?.viewing == Viewing(kind: kind, id: "thing01"))
        #expect(taken?.subject == "Example")
        #expect(handoff.take(for: "main01") == nil)
    }

    @Test func theChipNamesTheKindAndTheThing() {
        #expect(ReferenceHandoff.chipText(kindName: "Site", subject: "Example Yard") == "Site: Example Yard")
        #expect(ReferenceHandoff.chipText(kindName: "Site", subject: "") == "Site")
    }
}
