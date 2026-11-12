import Foundation
import Testing

@testable import PortalKit

@Suite struct GoalTests {
    @Test func goalsNeedingThePersonComeFirstThenWorkingThenEnded() {
        let goals = [
            Goal(id: "g1", title: "Stopped", goalState: "stopped"),
            Goal(id: "g2", title: "Working", goalState: "working"),
            Goal(id: "g3", title: "Needs you", goalState: "waiting"),
            Goal(id: "g4", title: "Met", goalState: "met"),
        ]
        #expect(goals.sortedForList.map(\.id) == ["g3", "g2", "g4", "g1"])
        #expect(goals[2].state == .waiting)
        #expect(goals[1].isOpen && !goals[0].isOpen)
    }

    @Test func aGoalIsReadFromTheServersFields() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            ["ListGoals": ["goals": [["id": "g1", "title": "Keep the pick rate up", "goalState": "waiting", "waitingQuestion": "Stop the night reports?", "turnCount": 4]], "meta": ["totalCount": 1]]]
        }
        let goals = try await connection.goals(includeOthers: true)
        #expect(goals.first?.waitingQuestion == "Stop the night reports?")
        #expect(goals.first?.turnCount == 4)
        #expect(sentVariables(try #require(transport.requests.last))["shouldIncludeOthers"] as? Bool == true)
    }

    @Test func tellingAGoalSendsItsIDAndText() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["TellGoal": ["id": "g1", "goalState": "working"]] }
        let goal = try await connection.tellGoal(id: "g1", text: "Yes, stop them.")
        #expect(goal.state == .working)
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["goalId"] as? String == "g1")
        #expect(variables["text"] as? String == "Yes, stop them.")
    }

    @Test func onlySitesControllersVirtualControllersAndConversationsAreLinkable() {
        func evidence(_ kind: String) -> Idea.Evidence { Idea.Evidence(evidenceKind: kind, evidenceId: "x1", evidenceLabel: "Label") }
        #expect(["site", "controller", "virtual_controller", "conversation"].allSatisfy { evidence($0).isLinkable })
        #expect(["ticket", "memory_page", "cell"].allSatisfy { !evidence($0).isLinkable })
        #expect(!Idea.Evidence(evidenceKind: "site", evidenceId: "", evidenceLabel: nil).isLinkable)
    }

    @Test func startingAnIdeaGivesTheDraftAndSendsNothing() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            ["StartIdea": ["draftRequest": "Look at the dock door alarms.", "idea": ["id": "i1"]]]
        }
        let draft = try await connection.startIdea(id: "catalog:dock")
        #expect(draft == "Look at the dock door alarms.")
        #expect(transport.requests.count == 1)
    }

    @Test func ideasAreOrderedByRank() async throws {
        let (connection, _) = scriptedConnection { _, _ in ["ListIdeas": ["ideas": [["id": "b", "rank": 2], ["id": "a", "rank": 1]]]] }
        #expect(try await connection.ideas().map(\.id) == ["a", "b"])
    }
}

@Suite struct KnowledgeTests {
    @Test func aCitationBecomesALinkAndCodeIsLeftAlone() {
        let text = "You prefer short answers [[user/preferences#3]].\n```\n[[not/a#1]]\n```\nAnd `[[nor/this#2]]` stays."
        let linked = MemoryCitation.linking(text)
        #expect(linked.contains("[Preferences](portal-memory:user/preferences#3)"))
        #expect(!linked.contains("[user/preferences#3]"))
        #expect(linked.contains("[[not/a#1]]"))
        #expect(linked.contains("`[[nor/this#2]]`"))
    }

    @Test func aLinkWithTheNumberSignEncodedReadsBackToo() throws {
        let citation = try #require(MemoryCitation(url: URL(string: "portal-memory:site/dock-3/doors%2312")!))
        #expect(citation.path == "site/dock-3/doors")
        #expect(citation.number == 12)
    }

    @Test func aLinkReadsBackAsThePathAndFactNumber() throws {
        let citation = try #require(MemoryCitation(url: URL(string: "portal-memory:site/dock-3/doors#12")!))
        #expect(citation.path == "site/dock-3/doors")
        #expect(citation.number == 12)
        #expect(citation.label == "site/dock-3/doors#12")
        #expect(citation.displayName == "Doors")
        #expect(MemoryCitation(path: "user/dock-door_notes", number: 1).displayName == "Dock door notes")
        #expect(MemoryCitation(url: URL(string: "https://example.test/a#1")!) == nil)
    }

    @Test func aFactIsLiveUnlessReplacedOrFaded() {
        #expect(MemoryFact(id: "f1").isLive)
        #expect(!MemoryFact(id: "f2", supersededByFactId: "f3").isLive)
        #expect(!MemoryFact(id: "f4", dormantAt: "2026-01-01T00:00:00Z").isLive)
    }

    @Test func aPageIsReadWithItsFactsAndLinks() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            [
                "GetMemoryPage": [
                    "id": "p1", "path": "user/preferences", "memoryScope": "user", "name": "Preferences", "isWritableByReader": true,
                    "facts": [["id": "f1", "number": 1, "sentence": "Prefers short answers.", "isInferred": true]],
                    "links": [["fromMemoryPageId": "p1", "toMemoryPageId": "p2", "relation": "related", "linkStatus": "stated"]],
                ]
            ]
        }
        let page = try await connection.memoryPage(path: "user/preferences")
        #expect(page.facts?.first?.isInferred == true)
        #expect(page.links?.count == 1)
        #expect(sentVariables(try #require(transport.requests.last))["path"] as? String == "user/preferences")
    }

    @Test func forgettingAFactIsByItsID() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ForgetMemoryFact": ["memoryFactId": "f1"]] }
        try await connection.forgetMemoryFact(id: "f1")
        #expect(sentVariables(try #require(transport.requests.last))["memoryFactId"] as? String == "f1")
    }
}

@Suite struct DreamAndArtifactTests {
    @Test func theDreamSettingIsReadAndWrittenWholeWithBoundedNumbers() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["SetAgentDreamSetting": ["isDreamEnabled": true, "dreamBudgetSharePercent": 100, "canManageOrganization": true]]
        }
        let setting = try await connection.setDreamSetting(isEnabled: true, budgetSharePercent: 250, tokenCap: -5)
        #expect(setting.isDreamEnabled == true)
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["dreamBudgetSharePercent"] as? Int == 100)
        #expect(variables["dreamTokenCap"] as? Int == 0)
    }

    @Test func aDreamRunKeepsItsPhases() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListMemoryDreams": ["memoryDreams": [["id": "d1", "dreamStatus": "running", "phaseReports": [["dreamPhase": "decay", "phaseOutcome": "done", "doneItemCount": 3]]]]]]
        }
        let dreams = try await connection.memoryDreams()
        #expect(dreams.first?.isRunning == true)
        #expect(dreams.first?.phaseReports?.first?.doneItemCount == 3)
    }

    @Test func aConversationsArtifactsKeepOnlyKindsTheAppDraws() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListConversationArtifacts": [["id": "a1", "title": "Weekly chart", "artifactKind": "html", "sizeBytes": 2048], ["id": "a2", "title": "Odd", "artifactKind": "flash"]]]
        }
        let artifacts = try await connection.conversationArtifacts(conversationId: "c1")
        #expect(artifacts.map(\.id) == ["a1"])
        #expect(artifacts.first?.sizeBytes == 2048)
    }
}

@Suite struct MemoryFilingTests {
    @Test func theNoteComesFromTheLatestFilingThatStillHasFacts() {
        let fact = MemoryFact(id: "f1", number: 1, sentence: "Prefers short answers.", pagePath: "user/preferences")
        let filings = [
            MemoryFiling(id: "newest", createdAt: "2026-10-31T12:00:00Z", facts: []),
            MemoryFiling(id: "middle", createdAt: "2026-10-31T11:00:00Z", facts: [fact]),
            MemoryFiling(id: "oldest", createdAt: "2026-10-31T10:00:00Z", facts: [fact, fact]),
        ]
        #expect(MemoryFilingNote.latestWithFacts(filings)?.id == "middle")
        #expect(MemoryFilingNote.latestWithFacts([MemoryFiling(id: "x", facts: [])]) == nil)
    }

    @Test func filingIsActiveOnlyWhenThePersonAndTheOrganizationBothAllowIt() async throws {
        let (connection, _) = scriptedConnection { _, _ in ["GetAgentMemorySetting": ["isFilingEnabledForUser": true, "isFilingEnabledForOrganization": false]] }
        let setting = try await connection.memorySetting()
        #expect(!setting.isFilingActive)
    }
}
