import Foundation
import Testing

@testable import PortalKit

@Suite struct AuditLogTests {
    static func event(_ json: String) throws -> AuditEvent {
        try JSONDecoder().decode(AuditEvent.self, from: Data(json.utf8))
    }

    @Test func anEventNamesItsActorItsActionAndItsResource() throws {
        let event = try Self.event(
            #"{"id":"e1","createdAt":"2026-03-01T10:00:00Z","actorType":"user","actorLabel":"alex@example.test","action":"update","resourceType":"virtual_controller","resourceId":"01HZZZZZZZZZZZZZZZZZZZZZ","before":{"name":"Old","size":2},"after":{"name":"New","size":2}}"#)
        #expect(event.actorName == "alex@example.test")
        #expect(event.actionName == "Update")
        #expect(event.resourceKindName == "Virtual controller")
        #expect(event.resourceName == "New")
    }

    @Test func anEventWithoutNamesFallsBackToWhatIsKnown() throws {
        let event = try Self.event(#"{"id":"e2","actorType":"system","resourceType":"ticket","resourceId":"01HZZZZZZZZZZZZZZZZZZZZZ"}"#)
        #expect(event.actorName == "System")
        #expect(event.actionName == "Change")
        #expect(event.resourceName == "…ZZZZZZZZ")
        let anonymous = try Self.event(#"{"id":"e3"}"#)
        #expect(anonymous.actorName == "Unknown")
        #expect(anonymous.resourceKindName == "Resource")
    }

    @Test func theChangesAreTheFieldsThatDifferWithoutBookkeeping() throws {
        let event = try Self.event(
            #"{"id":"e1","before":{"name":"Old","isActive":true,"modifiedAt":"2026-01-01T00:00:00Z","tags":["a"]},"after":{"name":"New","isActive":true,"modifiedAt":"2026-02-01T00:00:00Z","tags":["a","b"],"size":3}}"#)
        let changes = event.changes
        #expect(changes.map(\.field) == ["name", "size", "tags"])
        #expect(changes[0].beforeText == "Old")
        #expect(changes[0].afterText == "New")
        #expect(changes[1].beforeText == "")
        #expect(changes[1].afterText == "3")
        #expect(changes[2].afterText == #"["a","b"]"#)
    }

    @Test func aCreateListsWhatItSetAndADeleteWhatItRemoved() {
        let created = AuditChanges.diff(before: nil, after: .object(["name": .string("Line 1")]))
        #expect(created == [AuditFieldChange(field: "name", beforeText: "", afterText: "Line 1")])
        let deleted = AuditChanges.diff(before: .object(["name": .string("Line 1")]), after: .null)
        #expect(deleted == [AuditFieldChange(field: "name", beforeText: "Line 1", afterText: "")])
    }

    @Test func noFilterOnlySortsNewestFirst() throws {
        let stages = AuditFilter().aggregations()
        #expect(stages == .array([.object(["sort": .array([.object(["field": .array([.string("createdAt")]), "isDescending": .bool(true)])])])]))
        #expect(!AuditFilter().isFiltering)
    }

    @Test func aSingleFilterIsNotWrappedAndSeveralAreAnded() throws {
        let now = PortalDate.parse("2026-03-10T00:00:00Z")!
        let one = AuditFilter(range: .lastWeek).aggregations(now: now)
        guard case .array(let oneStages) = one, oneStages.count == 2 else { Issue.record("two stages expected"); return }
        #expect(oneStages[0]["filter"]?["operation"]?.stringValue == "greaterEqual")
        #expect(oneStages[0]["filter"]?["value"]?.stringValue == "2026-03-03T00:00:00Z")

        let many = AuditFilter(actions: ["update", "create"], range: .lastDay, searchText: " 203.0.113 ").aggregations(now: now)
        guard case .array(let manyStages) = many, case .array(let operands)? = manyStages[0]["filter"]?["operands"] else { Issue.record("operands expected"); return }
        #expect(manyStages[0]["filter"]?["operation"]?.stringValue == "and")
        #expect(operands.count == 3)
        #expect(operands[1]["value"] == .array([.string("create"), .string("update")]))
        #expect(operands[2]["operation"]?.stringValue == "or")
        guard case .array(let matches)? = operands[2]["operands"] else { Issue.record("matches expected"); return }
        #expect(matches.map { $0["field"] } == [.array([.string("sourceIp")]), .array([.string("requestId")]), .array([.string("resourceId")])])
        #expect(matches[0]["value"]?.stringValue == "203.0.113")
    }

    @Test func aPageIsAskedForByOffsetAndKeepsTheTotal() async throws {
        let transport = ScriptedTransport { _ in
            (
                200,
                ScriptedTransport.json([
                    "data": ["ListAuditEvents": ["events": [["id": "e1", "action": "create"], NSNull()], "meta": ["totalCount": 120]]]
                ])
            )
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        let page = try await connection.auditEvents(organizationId: "org1", filter: AuditFilter(actions: ["create"]), offset: 50)
        #expect(page.events.map(\.id) == ["e1"])
        #expect(page.totalCount == 120)
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any]
        let variables = body?["variables"] as? [String: Any]
        #expect(variables?["organizationId"] as? String == "org1")
        let options = variables?["options"] as? [String: Any]
        #expect(options?["after"] as? Int == 50)
        #expect(options?["first"] as? Int == 50)
    }
}
