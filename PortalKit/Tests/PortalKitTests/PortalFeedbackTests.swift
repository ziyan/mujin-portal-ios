import Foundation
import Testing

@testable import PortalKit

@Suite struct PortalFeedbackTests {
    static func sentQuery(_ request: URLRequest) -> String {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return body["query"] as? String ?? ""
    }

    // MARK: - The request

    @Test func theRequestCarriesOnlyThePersonsWordsAndTheFactsAboutTheApp() {
        let request = PortalFeedbackRequest(
            feedbackText: "  The filter menu is hard to find.\n", attachmentIds: ["att01", "att02"], clientVersion: "1.0 (42)",
            deviceName: "iPhone17,1", systemVersion: "26.0", screenName: "tickets")
        let variables = request.variables
        #expect(variables["feedbackText"] == .string("The filter menu is hard to find."))
        #expect(variables["attachmentIds"] == .array([.string("att01"), .string("att02")]))
        #expect(variables["clientSurface"] == .string("ios"))
        #expect(variables["clientVersion"] == .string("1.0 (42)"))
        #expect(variables["deviceName"] == .string("iPhone17,1"))
        #expect(variables["systemVersion"] == .string("26.0"))
        #expect(variables["screenName"] == .string("tickets"))
        #expect(variables["title"] == nil && variables["description"] == nil)
    }

    @Test func aFactThatIsNotKnownIsLeftOut() {
        let variables = PortalFeedbackRequest(feedbackText: "Words", screenName: "").variables
        #expect(Set(variables.keys) == ["feedbackText", "clientSurface"])
        #expect(variables["clientSurface"] == .string("ios"))
    }

    @Test func sendStaysOffUntilThereAreWords() {
        #expect(!PortalFeedback.canSend(feedbackText: "", isSending: false))
        #expect(!PortalFeedback.canSend(feedbackText: "  \n ", isSending: false))
        #expect(PortalFeedback.canSend(feedbackText: "Words", isSending: false))
        #expect(!PortalFeedback.canSend(feedbackText: "Words", isSending: true))
    }

    @Test func aRowShowsTheWordsWithoutThePrefixTheServerAdded() {
        #expect(PortalFeedback.shownWords(title: "Portal feedback: The filter menu is hard to find") == "The filter menu is hard to find")
        #expect(PortalFeedback.shownWords(title: "The filter menu is hard to find") == "The filter menu is hard to find")
        #expect(PortalFeedback.shownWords(title: nil) == "")
        #expect(PortalFeedback.maximumAttachmentCount == 10)
    }

    // MARK: - Sending

    @Test func submittingSendsTheMutationAndReadsTheTicketBack() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            guard operation == "SubmitPortalFeedback" else { return [:] }
            return ["SubmitPortalFeedback": ["ticket": ["id": "ticket-x", "sequence": 41, "title": "Portal feedback: Words", "status": "new", "isPortalFeedback": true]]]
        }
        let ticket = try await connection.submitPortalFeedback(PortalFeedbackRequest(feedbackText: "Words", attachmentIds: ["att01"], screenName: "chat"))
        #expect(ticket.id == "ticket-x" && ticket.sequence == 41 && ticket.status == "new" && ticket.isPortalFeedback == true)
        let request = try #require(transport.requests.last)
        #expect(Self.sentQuery(request).contains("SubmitPortalFeedback("))
        let variables = sentVariables(request)
        #expect(variables["feedbackText"] as? String == "Words")
        #expect(variables["attachmentIds"] as? [String] == ["att01"])
        #expect(variables["clientSurface"] as? String == "ios")
        #expect(variables["screenName"] as? String == "chat")
    }

    @Test func aFailureIsPassedOnSoTheWordsAreKept() async {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["errors": [["message": "feedback is not enabled"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        await #expect(throws: (any Error).self) {
            _ = try await connection.submitPortalFeedback(PortalFeedbackRequest(feedbackText: "Words"))
        }
    }

    // MARK: - Progress

    @Test func myFeedbackAsksForThePersonsOwnFeedbackTickets() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            guard operation == "ListPortalFeedback" else { return [:] }
            return [
                "ListTickets": [
                    "tickets": [
                        ["id": "a", "sequence": 1, "title": "Portal feedback: Older words", "status": "solved", "requesterUserId": "user01", "modifiedAt": "2026-03-01T10:00:00Z", "isPortalFeedback": true],
                        ["id": "b", "sequence": 2, "title": "Portal feedback: Newer words", "status": "open", "requesterUserId": "user01", "modifiedAt": "2026-03-03T10:00:00Z", "isPortalFeedback": true],
                        ["id": "c", "sequence": 3, "title": "Portal feedback: Someone else", "status": "open", "requesterUserId": "user02", "modifiedAt": "2026-03-04T10:00:00Z", "isPortalFeedback": true],
                    ]
                ]
            ]
        }
        let tickets = try await connection.portalFeedback(requesterUserId: "user01")
        #expect(tickets.map(\.id) == ["b", "a"])
        let request = try #require(transport.requests.last)
        #expect(Self.sentQuery(request).contains("isPortalFeedback: true"))
        #expect(sentVariables(request)["requesterUserId"] as? String == "user01")
    }

    // MARK: - Older servers

    @Test func onlyAServerWithTheMutationAndTheTicketListOffersFeedback() {
        #expect(!ServerCapabilities().offersPortalFeedback)
        #expect(!ServerCapabilities(queryNames: ["ListTickets"]).offersPortalFeedback)
        #expect(!ServerCapabilities(mutationNames: ["SubmitPortalFeedback"]).offersPortalFeedback)
        #expect(ServerCapabilities(queryNames: ["ListTickets"], mutationNames: ["SubmitPortalFeedback"]).offersPortalFeedback)
        #expect(ServerCapabilities(queryNames: ["listTickets"], mutationNames: ["submitPortalFeedback"]).offersPortalFeedback)
    }

    @Test func theCapabilitiesAreReadFromTheSchemaOfTheServer() async {
        let (newer, _) = scriptedConnection { _, _ in
            [
                "__schema": [
                    "queryType": ["fields": [["name": "listTickets", "args": [["name": "isPortalFeedback"]]]]],
                    "mutationType": ["fields": [["name": "submitPortalFeedback", "args": []]]],
                    "subscriptionType": NSNull(),
                ]
            ]
        }
        #expect(await newer.capabilities().offersPortalFeedback)
        let (older, _) = scriptedConnection { _, _ in
            ["__schema": ["queryType": ["fields": [["name": "listTickets", "args": []]]], "mutationType": ["fields": []], "subscriptionType": NSNull()]]
        }
        #expect(!(await older.capabilities().offersPortalFeedback))
    }

    @Test func anOlderServerIsNotAskedForTheFlag() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ListTickets": ["tickets": []], "GetTicket": ["id": "t1"]] }
        _ = try await connection.tickets()
        #expect(!Self.sentQuery(try #require(transport.requests.last)).contains("isPortalFeedback"))
        _ = try await connection.ticket(id: "t1")
        #expect(!Self.sentQuery(try #require(transport.requests.last)).contains("isPortalFeedback"))
        _ = try await connection.tickets(includesPortalFeedbackFlag: true)
        #expect(Self.sentQuery(try #require(transport.requests.last)).contains("viewerCapabilities isPortalFeedback"))
        _ = try await connection.ticket(id: "t1", includesPortalFeedbackFlag: true)
        #expect(Self.sentQuery(try #require(transport.requests.last)).contains("viewerCapabilities isPortalFeedback"))
    }

    @Test func aTicketDecodesWithAndWithoutTheFlag() throws {
        let marked = try JSONDecoder().decode(Ticket.self, from: Data(#"{"id":"t1","title":"Portal feedback: Words","isPortalFeedback":true}"#.utf8))
        #expect(marked.isPortalFeedback == true)
        let plain = try JSONDecoder().decode(Ticket.self, from: Data(#"{"id":"t2","title":"Gripper drops boxes"}"#.utf8))
        #expect(plain.isPortalFeedback == nil)
    }
}
