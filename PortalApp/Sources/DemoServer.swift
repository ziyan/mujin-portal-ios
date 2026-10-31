import Foundation
import PortalKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// DemoServer is a fake Portal for screenshots, previews and UI tests. It
/// answers the GraphQL documents the app sends from invented data and plays a
/// scripted turn through the subscription feed. Launch the app with `-demo`.
/// Every name here is made up.
@MainActor
enum DemoServer {
    static let server = try! ServerAddress("https://demo.example.test")

    static func makeModel(isSignedIn: Bool = true) -> AppModel {
        let account = Account(
            server: server, clientId: PortalClient.builtInClientId, userId: "user01", displayName: "Alex Example", email: "alex@example.test",
            accessToken: "demo-access", refreshToken: "demo-refresh", accessTokenExpiresAt: Date().addingTimeInterval(365 * 24 * 3600))
        let store = MemoryAccountStore(ring: isSignedIn ? AccountRing(accounts: [account], activeAccountKey: account.accountKey) : AccountRing())
        let state = DemoState()
        return AppModel(
            store: store, transport: DemoTransport(state: state),
            socketFactory: { _, _ in DemoSocket(state: state) }, isDemo: true)
    }
}

/// DemoState is the fake server's data.
final class DemoState: @unchecked Sendable {
    struct Data {
        var conversations: [[String: Any]] = []
        var messages: [String: [[String: Any]]] = [:]
        var questions: [String: [[String: Any]]] = [:]
        var approvals: [String: [[String: Any]]] = [:]
        var tickets: [[String: Any]] = []
        var comments: [String: [[String: Any]]] = [:]
        var sockets: [DemoSocket] = []
        var nextNumber = 1
    }

    private let lock = NSLock()
    private var data = Data()

    init() {
        let now = Date()
        func stamp(_ secondsAgo: TimeInterval) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-secondsAgo)) }
        func conversation(_ id: String, _ title: String, _ summary: String, _ secondsAgo: TimeInterval, running: Bool = false) -> [String: Any] {
            [
                "id": id, "agentId": "agent01", "title": title, "summary": summary, "lastMessageAt": stamp(secondsAgo),
                "activeRunId": running ? "run01" : NSNull(), "archivedAt": NSNull(), "createdAt": stamp(secondsAgo + 600), "modifiedAt": stamp(secondsAgo),
            ]
        }
        data.conversations = [
            conversation("conversation02", "Restart the planner on controller01", "Waiting for your approval.", 120, running: true),
            conversation("conversation01", "Weekly status summary", "Three sites are healthy, one needs attention.", 3_600),
            conversation("conversation03", "Questions about site01", "Pallet counts match the last shift.", 90_000),
            conversation("conversation04", "Throughput by site", "Site01 leads this week.", 1_800),
            conversation("conversation05", "Overnight checks", "No alarms overnight.", 7_200),
        ]
        data.messages["conversation01"] = [
            ["id": "m01", "role": "user", "content": "Give me a status summary for this week.", "createdAt": stamp(3_700)],
            [
                "id": "m02", "role": "assistant", "createdAt": stamp(3_650),
                "content": """
                    Here is the summary for this week.

                    ## Sites

                    - **site01** is healthy, with no alarms.
                    - **site02** is healthy.
                    - **site03** had two short network drops on `controller02`.

                    ## Next steps

                    1. Check the cabling at site03.
                    2. Review the alarm thresholds.

                    > Nothing needs your action today.
                    """,
            ],
        ]
        data.messages["conversation02"] = [
            ["id": "m10", "role": "user", "content": "Restart the planner on controller01.", "createdAt": stamp(200)],
            [
                "id": "m11", "role": "assistant", "content": "I will check the planner status first.", "createdAt": stamp(190),
                "toolCalls": [["id": "call01", "function": ["name": "controllers", "arguments": "{\"action\":\"status\",\"controller\":\"controller01\"}"]]],
            ],
            ["id": "m12", "role": "tool", "toolCallId": "call01", "toolName": "controllers", "content": "planner: running, uptime 12 days", "createdAt": stamp(185)],
        ]
        data.questions["conversation02"] = [
            [
                "id": "question01", "question": "Which environment should I restart it in?", "choices": ["Production", "Staging"], "allowOther": true,
                "askedAt": stamp(150), "answeredAt": NSNull(), "cancelledAt": NSNull(),
            ]
        ]
        data.approvals["conversation02"] = [
            [
                "id": "approval01", "toolCallId": "call02", "toolName": "shell", "policyReason": "This command changes a running service.", "risk": "high",
                "arguments": "{\"command\":\"systemctl restart planner\"}", "requestedAt": stamp(140), "decidedAt": NSNull(), "cancelledAt": NSNull(),
            ]
        ]
        func toolMessage(_ id: String, _ callId: String, _ name: String, _ content: String, note: String?, durationMS: Int?, _ secondsAgo: TimeInterval) -> [String: Any] {
            var metadata: [String: Any] = [:]
            if let note { metadata["toolNote"] = note }
            if let durationMS { metadata["durationMS"] = durationMS }
            return ["id": id, "role": "tool", "toolCallId": callId, "toolName": name, "content": content, "metadata": metadata, "createdAt": stamp(secondsAgo)]
        }
        func call(_ id: String, _ name: String, _ arguments: String) -> [String: Any] { ["id": id, "function": ["name": name, "arguments": arguments]] }
        func ticket(_ id: String, _ sequence: Int, _ title: String, _ status: String, _ priority: String, requester: String, organization: String, secondsAgo: TimeInterval) -> [String: Any] {
            [
                "id": id, "sequence": sequence, "title": title, "status": status, "priority": priority, "siteId": "site01", "organizationId": organization,
                "authorUserId": requester, "requesterUserId": requester, "assigneeUserId": status == "new" ? NSNull() : "user02", "assigneeUserIds": status == "new" ? [] : ["user02"],
                "isInternal": false, "createdAt": stamp(secondsAgo + 3_600), "modifiedAt": stamp(secondsAgo), "description": "The gripper drops about one box in twenty at pick station 3.",
                "viewerCapabilities": [],
            ]
        }
        data.tickets = [
            ticket("ticket01", 1, "Gripper drops boxes at pick station 3", "open", "high", requester: "user01", organization: "organization01", secondsAgo: 7_200),
            ticket("ticket02", 2, "Network drops on controller02", "pending", "normal", requester: "user03", organization: "organization02", secondsAgo: 20_000),
            ticket("ticket03", 3, "Label printer jams on the packing line", "new", "normal", requester: "user01", organization: "organization01", secondsAgo: 900),
            ticket("ticket04", 4, "Camera view is rotated", "solved", "low", requester: "user01", organization: "organization01", secondsAgo: 200_000),
            ticket("ticket05", 5, "Planner restart request", "closed", "normal", requester: "user03", organization: "organization02", secondsAgo: 900_000),
        ]
        data.comments["ticket01"] = [
            [
                "id": "comment01", "authorUserId": "user01", "isOriginalRequest": true, "isInternal": false, "createdAt": stamp(10_800),
                "body": "The gripper drops about one box in twenty at pick station 3.\n\n![Photo 1.jpg](attachment:attachment01)",
            ],
            [
                "id": "comment02", "authorUserId": "user02", "isInternal": false, "createdAt": stamp(7_200),
                "body": "Thanks Alex. I looked at the last two hours of logs and the suction pressure dips before each drop. Can you check the hose at the gripper?",
            ],
        ]
        data.messages["conversation04"] = [
            [
                "id": "m30", "role": "user", "content": "Show me throughput by site this week.", "createdAt": stamp(1_900),
                "viewingKind": "site", "viewingId": "site01", "viewingLabel": "site01",
                "reactions": [["id": "r30", "messageId": "m30", "reactorKind": "assistant", "reactorUserId": NSNull(), "emoji": "\u{1F440}", "isAcknowledgment": true]],
            ],
            [
                "id": "m31", "role": "assistant", "content": "Let me pull the numbers.", "createdAt": stamp(1_880),
                "toolCalls": [call("call10", "controllers", "{\"action\":\"list\"}"), call("call11", "metrics", "{\"days\":7}")],
            ],
            toolMessage("m32", "call10", "controllers", "3 controllers", note: "3 controllers", durationMS: 850, 1_870),
            toolMessage("m33", "call11", "metrics", "ok", note: "7 days of throughput", durationMS: 2_400, 1_860),
            [
                "id": "m34", "role": "assistant", "content": "", "createdAt": stamp(1_850),
                "toolCalls": [call("call12", "think_harder", "{\"switchReason\":\"Needs a closer comparison\"}"), call("call13", "artifact", "{\"title\":\"Throughput by site\"}")],
            ],
            toolMessage("m35", "call12", "think_harder", "", note: nil, durationMS: nil, 1_845),
            toolMessage(
                "m36", "call13", "artifact",
                "{\"artifactId\":\"artifact01\",\"attachmentId\":\"attachment01\",\"title\":\"Throughput by site\",\"artifactKind\":\"html\",\"sizeBytes\":2048,\"url\":\"/api/v1/artifact/artifact01\"}",
                note: "1 chart", durationMS: 600, 1_840),
            [
                "id": "m37", "role": "assistant", "content": "Site01 leads this week with 1,240 pallets, ahead of site02 and site03.", "createdAt": stamp(1_800),
                "reactions": [["id": "r31", "messageId": "m37", "reactorKind": "user", "reactorUserId": "user01", "emoji": "\u{1F44D}", "isAcknowledgment": false]],
            ],
        ]
        data.messages["conversation05"] = [
            ["id": "m40", "role": "user", "content": "[Scheduled: Morning check]\nLook at the overnight alarms.", "createdAt": stamp(8_000)],
            ["id": "m41", "role": "assistant", "content": "No alarms overnight.", "createdAt": stamp(7_990)],
            ["id": "m42", "role": "user", "content": "[Background work finished: Compare sites]\nSite01 is faster than site02.", "createdAt": stamp(7_800)],
            ["id": "m43", "role": "assistant", "content": "Site01 is faster than site02.", "createdAt": stamp(7_790)],
            ["id": "m44", "role": "user", "content": "[Carrying on after a restart]\nContinue.", "createdAt": stamp(7_500)],
            ["id": "m45", "role": "system", "content": "Earlier: the plan was to compare sites.", "stopReason": "context_summary", "createdAt": stamp(7_400)],
            [
                "id": "m46", "role": "system", "content": "The model did not answer in time.", "stopReason": "error", "metadata": ["turnEnd": true],
                "createdAt": stamp(7_300),
            ],
        ]
        data.messages["conversation03"] = [
            ["id": "m20", "role": "user", "content": "How many pallets did site01 move?", "createdAt": stamp(90_100)],
            ["id": "m21", "role": "assistant", "content": "About 1,200 pallets, matching the last shift.", "createdAt": stamp(90_050)],
        ]
    }

    func withData<Result>(_ body: (inout Data) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&data)
    }

    /// Tells every open feed about an event in a conversation.
    func broadcast(conversationId: String, event: [String: Any]) {
        let sockets = withData { $0.sockets.filter { $0.conversationId == conversationId } }
        for socket in sockets { socket.push(event: event) }
    }

    /// Plays an assistant answer through the feeds, then stores it.
    func playAnswer(conversationId: String, text: String) {
        let messageId = withData { data -> String in
            data.nextNumber += 1
            return "demo-message-\(data.nextNumber)"
        }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            var spoken = ""
            for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                spoken += (spoken.isEmpty ? "" : " ") + word
                broadcast(
                    conversationId: conversationId,
                    event: ["type": "text_delta", "runId": "run-demo", "textDelta": ["messageId": messageId, "text": (spoken == word ? "" : " ") + word]])
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            withData { data in
                data.messages[conversationId, default: []].append([
                    "id": messageId, "role": "assistant", "content": text, "createdAt": ISO8601DateFormatter().string(from: Date()),
                ])
                if let index = data.conversations.firstIndex(where: { ($0["id"] as? String) == conversationId }) {
                    data.conversations[index]["activeRunId"] = NSNull()
                }
            }
            broadcast(conversationId: conversationId, event: ["type": "run_complete", "runId": "run-demo", "runComplete": ["stopReason": "end_turn"]])
        }
    }
}

struct DemoTransport: HTTPTransport {
    let state: DemoState

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let query = body["query"] as? String ?? ""
        let variables = body["variables"] as? [String: Any] ?? [:]
        let operation = query.split(whereSeparator: { " \n(".contains($0) }).dropFirst().first.map(String.init) ?? ""
        let answer = respond(operation: operation, variables: variables)
        let payload = try JSONSerialization.data(withJSONObject: ["data": answer])
        return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func respond(operation: String, variables: [String: Any]) -> [String: Any] {
        let conversationId = variables["conversationId"] as? String ?? ""
        switch operation {
        case "Me":
            return [
                "Me": [
                    "id": "user01", "email": "alex@example.test", "name": "Alex Example", "organizationId": "organization01",
                    "permissions": ["ticket:read", "ticket:write", "site:read"],
                ]
            ]
        case "GetOrganization":
            return ["GetOrganization": ["id": "organization01", "name": DemoOptions.isStaff ? "Support" : "Example Logistics", "isMujin": DemoOptions.isStaff]]
        case "ServerCapabilities":
            return [
                "__schema": [
                    "queryType": ["fields": [["name": "listTickets"], ["name": "listSites"], ["name": "listConversationWaiting"]]],
                    "mutationType": ["fields": [["name": "sendMessage"], ["name": "registerPushDevice"]]],
                    "subscriptionType": ["fields": [["name": "onConversationEvent"]]],
                ]
            ]
        case "GetMainAgent":
            return ["GetMainAgent": ["id": "agent01", "name": "Assistant", "isMain": true]]
        case "ListConversations":
            return ["ListConversations": ["conversations": state.withData { $0.conversations }, "meta": ["totalCount": 3]]]
        case "GetConversation":
            return ["GetConversation": state.withData { $0.conversations.first { ($0["id"] as? String) == conversationId } ?? [:] }]
        case "ListConversationMessages":
            return ["ListConversationMessages": state.withData { $0.messages[conversationId] ?? [] }]
        case "ListSites":
            return ["ListSites": ["sites": [["id": "site01", "name": "site01", "organizationId": "organization01", "isArchived": false], ["id": "site02", "name": "site02", "organizationId": "organization01", "isArchived": false]]]]
        case "ListOrganizations":
            return ["ListOrganizations": ["organizations": [["id": "organization01", "name": "Example Logistics", "isMujin": false, "isActive": true], ["id": "organization02", "name": "Sample Foods", "isMujin": false, "isActive": true]], "meta": ["totalCount": 2]]]
        case "GetUser":
            let names = ["user01": "Alex Example", "user02": "Sam Sample", "user03": "Robin Demo"]
            let userId = variables["userId"] as? String ?? ""
            return ["GetUser": ["id": userId, "name": names[userId] ?? "Someone Else", "email": "\(userId)@example.test", "organizationId": "organization01"]]
        case "ListSiteActiveAlarms":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListSiteActiveAlarms": [
                    [
                        "controllerId": "controller01", "isAvailable": true,
                        "alarms": ["alarms": [
                            ["alarmLevel": "error", "alarmMessage": "Gripper suction pressure is low", "alarmStatus": "active", "occurredAt": stamp(1_200), "originLabel": "controller01"],
                            ["alarmLevel": "warning", "alarmMessage": "Conveyor 2 is running slowly", "alarmStatus": "active", "occurredAt": stamp(5_400), "originLabel": "controller01"],
                        ]],
                    ],
                    ["controllerId": "controller02", "isAvailable": false, "alarms": NSNull()],
                ]
            ]
        case "ListSiteMobileRobots":
            return [
                "ListSiteMobileRobots": [
                    [
                        "controllerId": "controller01", "isAvailable": true,
                        "mobileRobots": ["robots": [
                            ["name": "robot_1", "isOnline": true, "hasError": false, "powerLevel": 0.82, "isCharging": false],
                            ["name": "robot_2", "isOnline": true, "hasError": true, "error": "Lost localization near aisle 4", "powerLevel": 0.4, "isCharging": false],
                            ["name": "robot_3", "isOnline": false, "hasError": false, "powerLevel": 0.1, "isCharging": true],
                        ]],
                    ]
                ]
            ]
        case "ListControllers":
            return [
                "ListControllers": [
                    "controllers": [
                        ["id": "controller01", "comment": "Pick station controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "connection": ["id": "connection01"], "hypervisorState": ["version": "2026.10.2"]],
                        ["id": "controller02", "comment": "Packing line controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "connection": NSNull(), "hypervisorState": ["version": "2026.9.4"]],
                    ], "meta": ["totalCount": 2],
                ]
            ]
        case "ListIncidents":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListIncidents": [
                    "incidents": [
                        ["id": "incident01", "title": "Person near the conveyor", "description": "A person stood inside the marked zone while the conveyor ran.", "kind": "safety", "siteId": "site01", "controllerId": "controller01", "organizationId": "organization01", "reviewStatus": "new", "activityStatus": "active", "detectedAt": stamp(2_400), "confidence": 0.87],
                        ["id": "incident02", "title": "Pallet left in aisle", "kind": "obstruction", "siteId": "site01", "organizationId": "organization01", "reviewStatus": "confirmed", "activityStatus": "cleared", "detectedAt": stamp(90_000), "confidence": 0.74],
                    ], "meta": ["totalCount": 2],
                ]
            ]
        case "ListIncidentEvidence":
            return ["ListIncidentEvidence": ["incidentEvidence": [["attachmentId": "attachment10", "contentType": "image/jpeg", "filename": "frame-001.jpg", "role": "frame"]]]]
        case "TransitionIncident":
            return ["TransitionIncident": ["incident": ["id": variables["incidentId"] as? String ?? "", "reviewStatus": variables["reviewStatus"] as? String ?? ""]]]
        case "ListTickets":
            return ["ListTickets": ["tickets": state.withData { $0.tickets }, "meta": ["totalCount": 5]]]
        case "GetTicket":
            let ticketId = variables["ticketId"] as? String ?? ""
            return ["GetTicket": state.withData { $0.tickets.first { ($0["id"] as? String) == ticketId } ?? [:] }]
        case "ListTicketComments":
            let ticketId = variables["ticketId"] as? String ?? ""
            let showsInternal = DemoOptions.isStaff
            return [
                "ListTicketComments": state.withData { data -> [[String: Any]] in
                    var rows = data.comments[ticketId] ?? []
                    if showsInternal && ticketId == "ticket01" {
                        rows.append(["id": "comment03", "authorUserId": "user02", "isInternal": true, "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3_600)), "body": "Hose looks fine on the photo. Asking the line owner for the pressure log."])
                    }
                    return rows
                }
            ]
        case "CreateTicketComment":
            let ticketId = variables["ticketId"] as? String ?? ""
            let comment: [String: Any] = [
                "id": "demo-comment-\(Int.random(in: 1000...9999))", "authorUserId": "user01", "isInternal": variables["isInternal"] as? Bool ?? false,
                "createdAt": ISO8601DateFormatter().string(from: Date()), "body": variables["body"] as? String ?? "",
            ]
            state.withData { $0.comments[ticketId, default: []].append(comment) }
            return ["CreateTicketComment": ["ticketComment": comment]]
        case "CreateTicket":
            let input = variables["ticket"] as? [String: Any] ?? [:]
            let created: [String: Any] = state.withData { data in
                data.nextNumber += 1
                let row: [String: Any] = [
                    "id": "ticket-new-\(data.nextNumber)", "sequence": 100 + data.nextNumber, "title": input["title"] as? String ?? "", "status": "new",
                    "priority": input["priority"] as? String ?? "normal", "siteId": input["siteId"] as? String ?? NSNull(), "organizationId": "organization01",
                    "requesterUserId": "user01", "authorUserId": "user01", "description": input["description"] as? String ?? "",
                    "createdAt": ISO8601DateFormatter().string(from: Date()), "modifiedAt": ISO8601DateFormatter().string(from: Date()),
                ]
                data.tickets.insert(row, at: 0)
                return row
            }
            return ["CreateTicket": ["ticket": created]]
        case "ListConversationWaiting":
            return [
                "ListConversationWaiting": state.withData { data -> [[String: Any]] in
                    var rows: [[String: Any]] = []
                    for (conversationId, cards) in data.approvals {
                        for card in cards {
                            rows.append([
                                "conversationId": conversationId, "conversationTitle": "Restart the planner on controller01", "waitingKind": "approval",
                                "interactionId": card["id"] ?? "", "promptText": "The assistant wants to restart the planner on controller01.", "toolName": "shell",
                                "toolRisk": "high", "askedAt": card["requestedAt"] ?? NSNull(),
                            ])
                        }
                    }
                    for (conversationId, cards) in data.questions {
                        for card in cards {
                            rows.append([
                                "conversationId": conversationId, "conversationTitle": "Restart the planner on controller01", "waitingKind": "question",
                                "interactionId": card["id"] ?? "", "promptText": card["question"] ?? "", "askedAt": card["askedAt"] ?? NSNull(),
                            ])
                        }
                    }
                    return rows
                }
            ]
        case "CountConversationMessages":
            let loaded = state.withData { $0.messages[conversationId]?.count ?? 0 }
            return ["CountConversationMessages": ["messageCount": conversationId == "conversation04" ? loaded + 12 : loaded]]
        case "RenameConversation":
            let title = variables["title"] as? String ?? ""
            state.withData { data in
                if let index = data.conversations.firstIndex(where: { ($0["id"] as? String) == conversationId }) { data.conversations[index]["title"] = title }
            }
            return ["RenameConversation": ["conversation": ["id": conversationId, "title": title, "isTitleCustom": true]]]
        case "ReactToConversationMessage":
            let messageId = variables["messageId"] as? String ?? ""
            let emoji = variables["emoji"] as? String ?? ""
            let reactions: [[String: Any]] = emoji.isEmpty ? [] : [["id": "demo-reaction", "messageId": messageId, "reactorKind": "user", "reactorUserId": "user01", "emoji": emoji, "isAcknowledgment": false]]
            return ["ReactToConversationMessage": ["message": ["id": messageId, "conversationId": conversationId, "reactions": reactions]]]
        case "ListBackgroundWork":
            // A conversation's own list holds only unfinished work; the Automations list holds all of it.
            if variables["conversationId"] != nil { return ["ListBackgroundWork": ["backgroundWork": [], "meta": ["totalCount": 0]]] }
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListBackgroundWork": [
                    "backgroundWork": [
                        [
                            "id": "work01", "title": "Compare throughput of site01 and site02", "purpose": "Read both sites' last 30 days and compare them.",
                            "workState": "running", "parentConversationId": "conversation04", "startedAt": stamp(300), "createdAt": stamp(320),
                        ],
                        [
                            "id": "work02", "title": "Check overnight alarms", "purpose": "Summarize alarms from the last 12 hours.", "workState": "done",
                            "resultText": "No alarms in the last 12 hours on any controller.", "parentConversationId": "conversation05", "startedAt": stamp(9_000),
                            "finishedAt": stamp(8_800), "createdAt": stamp(9_100), "costMicroMinorUnits": 3_400_000, "costCurrency": "USD",
                        ],
                    ], "meta": ["totalCount": 2],
                ]
            ]
        case "ListAgentSchedule":
            let formatter = ISO8601DateFormatter()
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            func at(_ base: Date, _ hour: Int) -> String { formatter.string(from: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base) }
            return [
                "ListAgentSchedule": [
                    "occurrences": [
                        ["occurrenceKind": "job", "occursAt": at(Date(), 17), "subjectId": "job02", "title": "End of shift report", "jobType": "recurring", "conversationId": "conversation05"],
                        ["occurrenceKind": "job", "occursAt": at(tomorrow, 7), "subjectId": "job01", "title": "Morning check", "jobType": "recurring", "conversationId": "conversation05"],
                        ["occurrenceKind": "goal_check_in", "occursAt": at(tomorrow, 9), "subjectId": "goal01", "title": "Reduce dock wait time"],
                        ["occurrenceKind": "job", "occursAt": at(tomorrow, 15), "subjectId": "job03", "title": "Watch controller01 planner", "jobType": "monitor"],
                    ], "unreadableJobCount": 0,
                ]
            ]
        case "ListAgentActivity":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListAgentActivity": [
                    "activities": [
                        ["id": "activity01", "activityKind": "scheduled_job", "activityStatus": "running", "title": "End of shift report", "startedAt": stamp(60), "conversationId": "conversation05"],
                        [
                            "id": "activity02", "activityKind": "scheduled_job", "activityStatus": "succeeded", "title": "Morning check", "startedAt": stamp(7_200),
                            "endedAt": stamp(7_100), "costMicroMinorUnits": 12_300_000, "costCurrency": "USD", "conversationId": "conversation05",
                        ],
                        [
                            "id": "activity03", "activityKind": "monitor", "activityStatus": "failed", "title": "Watch controller01 planner", "startedAt": stamp(20_000),
                            "endedAt": stamp(19_900), "errorMessage": "The controller did not answer.",
                        ],
                        [
                            "id": "activity04", "activityKind": "background_work", "activityStatus": "succeeded", "title": "Check overnight alarms", "startedAt": stamp(9_000),
                            "endedAt": stamp(8_800), "costMicroMinorUnits": 3_400_000, "costCurrency": "USD", "backgroundWorkId": "work02",
                        ],
                    ], "meta": ["totalCount": 4],
                ]
            ]
        case "ListConversationQuestions":
            return ["ListConversationQuestions": state.withData { $0.questions[conversationId] ?? [] }]
        case "ListConversationApprovals":
            return ["ListConversationApprovals": state.withData { $0.approvals[conversationId] ?? [] }]
        case "CreateConversation":
            let created: [String: Any] = state.withData { data in
                data.nextNumber += 1
                let id = "conversation-new-\(data.nextNumber)"
                let stamp = ISO8601DateFormatter().string(from: Date())
                let row: [String: Any] = [
                    "id": id, "agentId": "agent01", "title": NSNull(), "summary": NSNull(), "lastMessageAt": stamp, "activeRunId": NSNull(),
                    "archivedAt": NSNull(), "createdAt": stamp, "modifiedAt": stamp,
                ]
                data.conversations.insert(row, at: 0)
                return row
            }
            return ["CreateConversation": ["conversation": created]]
        case "SendMessage":
            let message = variables["message"] as? String ?? ""
            state.withData { data in
                data.nextNumber += 1
                data.messages[conversationId, default: []].append([
                    "id": "demo-user-\(data.nextNumber)", "role": "user", "content": message, "createdAt": ISO8601DateFormatter().string(from: Date()),
                ])
                if let index = data.conversations.firstIndex(where: { ($0["id"] as? String) == conversationId }) {
                    data.conversations[index]["activeRunId"] = "run-demo"
                    if data.conversations[index]["title"] is NSNull { data.conversations[index]["title"] = String(message.prefix(40)) }
                }
            }
            state.playAnswer(
                conversationId: conversationId,
                text: "This is a demo answer. Your real assistant would look this up and reply here, one word at a time.")
            return ["SendMessage": ["runId": "run-demo"]]
        case "AnswerQuestion":
            state.withData { data in
                for (key, rows) in data.questions { data.questions[key] = rows.filter { ($0["id"] as? String) != (variables["questionId"] as? String) } }
            }
            return ["AnswerQuestion": NSNull()]
        case "ResolveToolApproval":
            state.withData { data in
                for (key, rows) in data.approvals { data.approvals[key] = rows.filter { ($0["id"] as? String) != (variables["approvalId"] as? String) } }
            }
            return ["ResolveToolApproval": NSNull()]
        case "ArchiveConversation":
            state.withData { data in data.conversations.removeAll { ($0["id"] as? String) == conversationId } }
            return ["ArchiveConversation": ["conversation": ["id": conversationId, "archivedAt": ISO8601DateFormatter().string(from: Date())]]]
        default:
            return ["CancelRun": NSNull()]
        }
    }
}

/// DemoSocket is a feed socket on the fake server.
final class DemoSocket: FeedSocket, @unchecked Sendable {
    private struct Inner {
        var queue: [FeedFrame] = []
        var isClosed = false
        var conversationId = ""
    }

    private let state: DemoState
    private let inner = DemoLocked(Inner())

    init(state: DemoState) {
        self.state = state
    }

    var conversationId: String { inner.withValue { $0.conversationId } }

    private func enqueue(_ frame: FeedFrame) {
        inner.withValue { $0.queue.append(frame) }
    }

    func push(event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": "1", "type": "next", "payload": ["data": ["OnConversationEvent": event]]]) else { return }
        enqueue(.text(String(decoding: data, as: UTF8.self)))
    }

    func send(_ text: String) async throws {
        guard let message = try? SubscriptionMessage(decoding: text) else { return }
        switch message {
        case .connectionInit: enqueue(.text(#"{"type":"connection_ack"}"#))
        case .ping: enqueue(.text(#"{"type":"pong"}"#))
        case .subscribe(_, _, let variables):
            inner.withValue { $0.conversationId = variables["conversationId"]?.stringValue ?? "" }
            state.withData { $0.sockets.append(self) }
        default: break
        }
    }

    func receive() async throws -> FeedFrame {
        while true {
            let next: FeedFrame?? = inner.withValue { inner in
                if !inner.queue.isEmpty { return .some(inner.queue.removeFirst()) }
                return inner.isClosed ? .some(nil) : nil
            }
            if let next { return next ?? .closed(code: nil) }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    func close() {
        inner.withValue { $0.isClosed = true }
        state.withData { data in data.sockets.removeAll { $0 === self } }
    }
}

/// DemoLocked is a value behind a lock.
final class DemoLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
