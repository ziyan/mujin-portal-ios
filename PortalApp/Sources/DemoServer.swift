import Foundation
import PortalKit
import UIKit

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

    static func makeModel(isSignedIn: Bool = ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] != "welcome") -> AppModel {
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
        var chats: [[String: Any]] = []
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
        func conversation(_ id: String, _ title: String, _ summary: String, _ secondsAgo: TimeInterval, running: Bool = false, isMain: Bool = false) -> [String: Any] {
            [
                "isMain": isMain,
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
            conversation("conversation06", "A thought about dock doors", "The assistant started this conversation.", 600),
            conversation("conversation-photos", "Line photos", "Twelve photos from the pick line.", 40_000),
            conversation("conversation-main", "Stored title that is never shown", "Dock door 4 is slow again; I filed a ticket.", 300, isMain: true),
        ]
        data.messages["conversation-photos"] = [
            ["id": "ph01", "role": "user", "content": "Photo 1 from the line: ![camera-01.jpg](/api/v1/attachment/imagedemo02)", "createdAt": stamp(39400)],
            ["id": "ph02", "role": "assistant", "content": "Photo 2 from the line: ![camera-02.jpg](/api/v1/attachment/imagedemo01)", "createdAt": stamp(38800)],
            ["id": "ph03", "role": "assistant", "content": "Photo 3 from the line: ![camera-03.jpg](/api/v1/attachment/imagedemo02)", "createdAt": stamp(38200)],
            ["id": "ph04", "role": "user", "content": "Photo 4 from the line: ![camera-04.jpg](/api/v1/attachment/imagedemo01)", "createdAt": stamp(37600)],
            ["id": "ph05", "role": "assistant", "content": "Photo 5 from the line: ![camera-05.jpg](/api/v1/attachment/imagedemo02)", "createdAt": stamp(37000)],
            ["id": "ph06", "role": "assistant", "content": "Photo 6 from the line: ![camera-06.jpg](/api/v1/attachment/imagedemo01)", "createdAt": stamp(36400)],
            ["id": "ph07", "role": "user", "content": "Photo 7 from the line: ![camera-07.jpg](/api/v1/attachment/imagedemo02)", "createdAt": stamp(35800)],
            ["id": "ph08", "role": "assistant", "content": "Photo 8 from the line: ![camera-08.jpg](/api/v1/attachment/imagedemo01)", "createdAt": stamp(35200)],
            ["id": "ph09", "role": "assistant", "content": "Photo 9 from the line: ![camera-09.jpg](/api/v1/attachment/imagedemo02)", "createdAt": stamp(34600)],
            ["id": "ph10", "role": "user", "content": "Photo 10 from the line: ![camera-10.jpg](/api/v1/attachment/imagedemo01)", "createdAt": stamp(34000)],
            ["id": "ph11", "role": "assistant", "content": "Photo 11 from the line: ![camera-11.jpg](/api/v1/attachment/imagedemo02)", "createdAt": stamp(33400)],
            ["id": "ph12", "role": "assistant", "content": "Photo 12 from the line: ![camera-12.jpg](/api/v1/attachment/imagedemo01)", "createdAt": stamp(32800)],
        ]
        data.messages["conversation-main"] = [
            ["id": "mm01", "role": "user", "content": "What changed overnight?", "createdAt": stamp(7_300)],
            ["id": "mm02", "role": "assistant", "content": "Nothing urgent. One idea for you: dock door 4 has been slow three days in a row.", "createdAt": stamp(7_250)],
            ["id": "mm03", "role": "assistant", "content": "Dock door 4 is slow again; I filed a ticket.", "createdAt": stamp(300)],
            [
                "id": "mm04", "role": "assistant", "createdAt": stamp(120),
                "content": "Here are the two stations and a short clip.\n\n**Station 3 (c123)**: ![camera-a1b2c3.jpg](/api/v1/attachment/imagedemo01)\n\n**Station 4 (c124)**: ![camera-d4e5f6.jpg](/api/v1/attachment/imagedemo02)\n\n[station-walkthrough.mp4](/api/v1/attachment/videodemo01)",
            ],
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
        func member(_ id: String, _ name: String, _ organizationId: String, _ organizationName: String, staff: Bool = false, admin: Bool = false, read: String? = nil) -> [String: Any] {
            [
                "id": "member-\(id)", "userId": id, "userName": name, "organizationId": organizationId, "organizationName": organizationName, "isMujinUser": staff,
                "isAdmin": admin, "lastReadMessageId": read ?? NSNull(), "leftAt": NSNull(), "notificationLevel": "all",
            ]
        }
        func chatRow(_ conversationId: String, _ chatId: String, _ kind: String, _ name: String, _ excerpt: String, _ author: String, unread: Int, secondsAgo: TimeInterval, members: [[String: Any]]) -> [String: Any] {
            [
                "id": conversationId, "chatId": chatId, "conversationKind": "chat", "title": name, "summary": NSNull(), "lastMessageAt": stamp(secondsAgo), "activeRunId": NSNull(),
                "archivedAt": NSNull(), "createdAt": stamp(secondsAgo + 5_000), "modifiedAt": stamp(secondsAgo), "isTitleCustom": false, "agentId": NSNull(),
                "chat": [
                    "id": chatId, "organizationId": "organization01", "chatKind": kind, "name": kind == "group" ? name : NSNull(), "displayName": name, "isMemoryFilingEnabled": false,
                    "lastMessageAt": stamp(secondsAgo), "readerConversationId": conversationId, "readerNotificationLevel": "all", "isReaderAdmin": kind == "group",
                    "isReaderMember": true, "readerUnreadMessageCount": unread, "readerLastReadMessageId": NSNull(), "lastMessageExcerpt": excerpt, "lastMessageAuthorName": author,
                    "members": members,
                ] as [String: Any],
            ]
        }
        data.chats = [
            chatRow("chatconv01", "chat01", "direct", "Sam Sample", "Thanks! Also see the checklist.", "Sam Sample", unread: 2, secondsAgo: 600, members: [
                member("user01", "Alex Example", "organization01", "Example Logistics", read: "c8"),
                member("user02", "Sam Sample", "organization00", "Support", staff: true, read: "c8"),
            ]),
            chatRow("chatconv02", "chat02", "group", "Pick station team", "Shift change at 14:00.", "Robin Demo", unread: 0, secondsAgo: 7_200, members: [
                member("user01", "Alex Example", "organization01", "Example Logistics", admin: true),
                member("user03", "Robin Demo", "organization01", "Example Logistics"),
                member("user04", "Jordan Placeholder", "organization01", "Example Logistics"),
            ]),
        ]
        func said(_ id: String, _ author: String, _ name: String, _ text: String, _ secondsAgo: TimeInterval, role: String = "user", extra: [String: Any] = [:]) -> [String: Any] {
            var row: [String: Any] = [
                "id": id, "role": role, "content": text, "createdAt": stamp(secondsAgo), "isChatMessage": true, "authorUserId": author, "authorName": name,
                "authorOrganizationName": author == "user02" ? "Support" : "Example Logistics", "authorOrganizationId": author == "user02" ? "organization00" : "organization01",
            ]
            for (key, value) in extra { row[key] = value }
            return row
        }
        data.messages["chatconv01"] = [
            said("c1", "user02", "Sam Sample", "Hi Alex, I saw the gripper ticket. Can you send the pressure log?", 3_000),
            said("c2", "user01", "Alex Example", "Sure. It is on the ticket now: /ticket/1", 2_900),
            said("c3", "user02", "Sam Sample", "Got it. The checklist is here: https://example.test/docs/suction", 2_800, extra: [
                "replyToMessageId": "c2", "replyToExcerpt": "Sure. It is on the ticket now", "replyToAuthorName": "Alex Example",
                "reactions": [["id": "rc3", "messageId": "c3", "reactorKind": "user", "reactorUserId": "user01", "emoji": "\u{1F44D}", "isAcknowledgment": false]],
            ]),
            said("c4", "user01", "Alex Example", "@Mujin AI summarize the pressure readings from the ticket", 1_000, extra: ["isAddressingAssistant": true]),
            said("c5", "assistant", "Mujin AI", "Suction pressure dipped below 40 kPa four times in two hours, each time just before a drop.", 950, role: "assistant", extra: ["authorUserId": NSNull(), "onBehalfOfUserId": "user01", "onBehalfOfUserName": "Alex Example", "replyToMessageId": "c4", "replyToExcerpt": "@Mujin AI summarize the pressure readings", "replyToAuthorName": "Alex Example"]),
            said("c6", "user02", "Sam Sample", "", 900, extra: ["deletedAt": stamp(880)]),
            said("c7", "user02", "Sam Sample", "That matches what I saw. I will schedule a hose replacement.", 700, extra: ["editedAt": stamp(650)]),
            said("c8", "user01", "Alex Example", "Thanks, please do.", 620),
        ]
        data.messages["chatconv02"] = [
            said("d1", "user03", "Robin Demo", "Shift change at 14:00.", 7_200),
            said("d2", "user04", "Jordan Placeholder", "I can take the pick station.", 7_100),
        ]
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
                "body": "The gripper drops about one box in twenty at pick station 3. A frame from the camera, the walkthrough and the pressure log are attached.\n\n![frame_008.jpg](attachment:imagedemo01)\n\n<video src=\"attachment:videodemo01\" controls preload=\"metadata\" width=\"100%\" title=\"station-walkthrough.mp4\"></video>\n\n<iframe src=\"attachment:pdfdemo01\" width=\"100%\" height=\"600\" title=\"pressure-log.pdf\"></iframe>\n\n![removed.png](attachment:missingdemo01)",
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
        data.messages["conversation06"] = [
            ["id": "m50", "role": "user", "content": "[Speaking first: idea]\nShare the open idea about dock doors.", "createdAt": stamp(660)],
            [
                "id": "m51", "role": "assistant", "createdAt": stamp(650),
                "content": "I noticed dock door 3 opened late four mornings in a row. Want me to watch it and tell you when it happens? You prefer short answers [[user/preferences#2]].",
            ],
            [
                "id": "m52", "role": "system", "content": "Looking more closely: the pattern needs a week of history.", "createdAt": stamp(640),
                "metadata": ["depthNote": true, "reasonKind": "lookingClosely", "reasonParameters": ["reason": "the pattern needs a week of history"]],
            ],
            [
                "id": "m53", "role": "assistant", "createdAt": stamp(630),
                "content": "[Goal needs you: Keep dock waits under 20 minutes]\n\nThe goal \"Keep dock waits under 20 minutes\" is waiting for you.\n\nShould I also watch dock door 4?\n\nAnswer here and I will pass it on. (goal id: goal01)",
                "metadata": ["goalNeedsYou": ["goalId": "goal01", "waitId": "wait01"]],
            ],
            [
                "id": "m54", "role": "system", "content": "The model provider is busy. Try again in a minute.", "stopReason": "error", "createdAt": stamp(620),
                "metadata": ["turnEnd": true, "reasonKind": "providerRateLimited", "reasonParameters": [:]],
            ],
        ]
        data.messages["conversation03"] = [
            ["id": "m20", "role": "user", "content": "How many pallets did site01 move?", "createdAt": stamp(90_100)],
            ["id": "m21", "role": "assistant", "content": "About 1,200 pallets, matching the last shift.", "createdAt": stamp(90_050)],
        ]
        data.messages["conversation05"] = [
            ["id": "sc1", "role": "user", "content": "Is this checklist still right? https://example.test/docs/suction and the ticket /ticket/1", "createdAt": stamp(90_100)],
            ["id": "sc2", "role": "assistant", "content": "Yes. The checklist matches what the ticket describes: check the hose first, then the seals.", "createdAt": stamp(90_000)],
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
        if let path = request.url?.path, path.hasPrefix("/api/v1/user/") || path.hasPrefix("/api/v1/organization/") || path.hasPrefix("/api/v1/attachment/") {
            // Two demo people and one organization have a picture; everyone else gets a 404 and keeps their initials.
            let image = DemoPictures.jpeg(forPath: path)
            let response = HTTPURLResponse(url: request.url!, statusCode: image == nil ? 404 : 200, httpVersion: nil, headerFields: ["Content-Type": path.hasSuffix("pdfdemo01") ? "application/pdf" : "image/jpeg"])!
            return (image ?? Data(), response)
        }
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let query = body["query"] as? String ?? ""
        let variables = body["variables"] as? [String: Any] ?? [:]
        let operation = query.split(whereSeparator: { " \n(".contains($0) }).dropFirst().first.map(String.init) ?? ""
        // The loading screenshot holds the stats back so the placeholders are what is photographed.
        if ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "site-loading",
            ["ListControllerTelemetrySummaries", "ListCells", "ListSiteVirtualControllers", "ListSiteOrchestrators"].contains(operation)
        {
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        }
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
                    "id": "user01", "email": "alex@example.test", "name": "Alex Example", "organizationId": "organization01", "hasAvatar": false, "modifiedAt": "2026-01-01T00:00:00Z",
                    "permissions": ["ticket:read", "ticket:write", "site:read", "organization:operate-all"],
                ]
            ]
        case "GetOrganization":
            return ["GetOrganization": ["id": "organization01", "name": DemoOptions.isStaff ? "Support" : "Example Logistics", "isMujin": DemoOptions.isStaff]]
        case "ServerCapabilities":
            return [
                "__schema": [
                    "queryType": ["fields": [["name": "listTickets"], ["name": "listSites"], ["name": "listConversationWaiting"], ["name": "listChatCandidates"]]],
                    "mutationType": ["fields": [["name": "sendMessage"], ["name": "registerPushDevice"], ["name": "startDirectChat"]]],
                    "subscriptionType": ["fields": [["name": "onConversationEvent"]]],
                ]
            ]
        case "GetMainAgent":
            return ["GetMainAgent": ["id": "agent01", "name": "Assistant", "isMain": true]]
        case "ListConversations":
            if variables["conversationKind"] as? String == "chat" {
                return ["ListConversations": ["conversations": state.withData { $0.chats }, "meta": ["totalCount": 2]]]
            }
            return ["ListConversations": ["conversations": state.withData { $0.conversations }, "meta": ["totalCount": 7]]]
        case "GetConversation":
            return ["GetConversation": state.withData { data in (data.conversations + data.chats).first { ($0["id"] as? String) == conversationId } ?? [:] }]
        case "GetChat":
            let chatId = variables["chatId"] as? String ?? ""
            return ["GetChat": state.withData { data in data.chats.compactMap { $0["chat"] as? [String: Any] }.first { ($0["id"] as? String) == chatId } ?? [:] }]
        case "ListChatCandidates":
            let staff = DemoOptions.isStaff
            let rows: [[String: Any]] = staff
                ? [
                    ["userId": "user03", "userName": "Robin Demo", "email": "robin@example.test", "organizationId": "organization01", "organizationName": "Example Logistics", "isMujinUser": false],
                    ["userId": "user04", "userName": "Jordan Placeholder", "email": "jordan@example.test", "organizationId": "organization02", "organizationName": "Sample Foods", "isMujinUser": false],
                    ["userId": "user05", "userName": "Ana Support", "email": "ana@example.test", "organizationId": "organization00", "organizationName": "Support", "isMujinUser": true],
                ]
                : [
                    ["userId": "user03", "userName": "Robin Demo", "email": "robin@example.test", "organizationId": "organization01", "organizationName": "Example Logistics", "isMujinUser": false],
                    ["userId": "user04", "userName": "Jordan Placeholder", "email": "jordan@example.test", "organizationId": "organization01", "organizationName": "Example Logistics", "isMujinUser": false],
                    ["userId": "user02", "userName": "Sam Sample", "email": "sam@example.test", "organizationId": "organization00", "organizationName": "Support", "isMujinUser": true],
                ]
            return ["ListChatCandidates": rows]
        case "ListAuthorizedAgents":
            return ["ListAuthorizedAgents": [["id": "agent01", "name": "Mujin AI", "isMain": true, "isEnabled": true], ["id": "agent02", "name": "Site Helper", "isMain": false, "isEnabled": true]]]
        case "StartDirectChat":
            return ["StartDirectChat": ["chat": ["id": "chat01"], "conversation": ["id": "chatconv01"]]]
        case "CreateGroupChat":
            return ["CreateGroupChat": ["chat": ["id": "chat02"], "conversation": ["id": "chatconv02"]]]
        case "ListMessageLinkPreviews":
            let ids = variables["messageIds"] as? [String] ?? []
            return [
                "ListMessageLinkPreviews": ids.compactMap { id -> [String: Any]? in
                    switch id {
                    case "c2":
                        return ["messageId": id, "isPending": false, "linkPreviews": [["urlHash": "hash01", "linkKind": "ticket", "resourceId": "ticket01", "title": "Gripper drops boxes at pick station 3", "description": "Ticket #1", "statusText": "open", "path": "/ticket/1"]]]
                    case "sc1":
                        return ["messageId": id, "isPending": false, "linkPreviews": [
                            ["urlHash": "hash03", "linkKind": "external", "url": "https://example.test/docs/suction", "title": "Suction cup checklist", "description": "Steps to check hoses, seals and pressure before a shift.", "siteName": "example.test"],
                            ["urlHash": "hash04", "linkKind": "ticket", "resourceId": "ticket01", "title": "Gripper drops boxes at pick station 3", "description": "Ticket #1", "statusText": "open", "path": "/ticket/1"],
                        ]]
                    case "c3":
                        return ["messageId": id, "isPending": false, "linkPreviews": [["urlHash": "hash02", "linkKind": "external", "url": "https://example.test/docs/suction", "title": "Suction cup checklist", "description": "Steps to check hoses, seals and pressure before a shift.", "siteName": "example.test"]]]
                    default: return nil
                    }
                }
            ]
        case "SetChatTyping", "MarkChatRead", "EditChatMessage", "DeleteChatMessage", "RemoveMessageLinkPreviews":
            return [operation: NSNull()]
        case "ListConversationMessages":
            return ["ListConversationMessages": state.withData { $0.messages[conversationId] ?? [] }]
        case "ListSites":
            let all: [[String: Any]] = [
                ["id": "site01", "name": "site01", "organizationId": "organization01", "isArchived": false],
                ["id": "site02", "name": "site02", "organizationId": "organization01", "isArchived": false],
                ["id": "site03", "name": "Bakery line", "organizationId": "organization02", "isArchived": false],
                ["id": "site04", "name": "Cold store", "organizationId": "organization02", "isArchived": false],
                ["id": "site05", "name": "Lab cell", "organizationId": "organization00", "isArchived": false],
                ["id": "site06", "name": "Retired yard", "organizationId": "organization02", "isArchived": true],
            ]
            // A customer sees its own organization's sites; a Mujin user sees them all, or one organization's when asked.
            let scope = variables["organizationId"] as? String ?? (DemoOptions.isStaff ? nil : "organization01")
            let shown = all.filter { scope == nil || ($0["organizationId"] as? String) == scope }
            return ["ListSites": ["sites": shown, "meta": ["totalCount": shown.count]]]
        case "ListOrganizations":
            return ["ListOrganizations": ["organizations": [["id": "organization01", "name": "Example Logistics", "isMujin": false, "isActive": true, "hasLogo": true, "modifiedAt": "2026-01-01T00:00:00Z"], ["id": "organization02", "name": "Sample Foods", "isMujin": false, "isActive": true], ["id": "organization00", "name": "Support", "isMujin": true, "isActive": true]], "meta": ["totalCount": 2]]]
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
                        ["id": "controller01", "comment": "Pick station controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect", "controller:write"], "releaseId": "release01", "releaseImageId": "image01", "connection": ["id": "connection01"], "hypervisorState": ["version": "2026.10.2"]],
                        ["id": "controller02", "comment": "Packing line controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect"], "releaseId": "release01", "connection": NSNull(), "hypervisorState": ["version": "2026.9.4"]],
                    ], "meta": ["totalCount": 2],
                ]
            ]
        case "ListControllerTelemetrySummaries":
            return [
                "ListControllerTelemetrySummaries": [
                    ["controllerId": "controller01", "isAvailable": true, "activeAlarmCount": 1, "totals": ["pickOperationCount": 1_480, "pickedPartCount": 1_392, "humanInterventionCount": 21, "directRobotThroughputPartsPerHour": 58.0]],
                    ["controllerId": "controller02", "isAvailable": false],
                ]
            ]
        case "ListCells":
            return ["ListCells": ["cells": [["id": "cell01", "name": "Pick cell A", "controllerIds": ["controller01"]], ["id": "cell02", "name": "Packing line", "controllerIds": ["controller02"]]]]]
        case "ListSiteOrchestrators":
            return [
                "ListSiteOrchestrators": [
                    [
                        "controllerId": "controller01", "isAvailable": true,
                        "orchestrators": ["activeRunModeName": "Normal", "orchestrators": [
                            ["orchestratorId": "orchestrator01", "orchestratorType": "pick_station", "runStatus": "running", "processStatus": "running", "hasError": false],
                            ["orchestratorId": "orchestrator02", "orchestratorType": "packing_line", "runStatus": "stopped", "hasError": true, "statusMessage": "Label printer not responding"],
                        ]],
                    ],
                    ["controllerId": "controller02", "isAvailable": false],
                ]
            ]
        case "ListSiteUserIDs":
            return ["ListSiteUserIDs": ["user01", "user02", "user03"]]
        case "ListOrganizationUsers":
            return [
                "ListOrganizationUsers": [
                    "users": [
                        ["id": "user01", "name": "Alex Example", "email": "alex@example.test"], ["id": "user02", "name": "Sam Sample", "email": "sam@example.test", "hasAvatar": true, "modifiedAt": "2026-01-01T00:00:00Z"],
                        ["id": "user03", "name": "Robin Demo", "email": "robin@example.test", "hasAvatar": true, "modifiedAt": "2026-01-01T00:00:00Z"],
                    ]
                ]
            ]
        case "GetRelease":
            return [
                "GetRelease": [
                    "id": "release01", "name": "Autumn release", "application": "controller", "channel": "stable", "status": "published", "versionString": "2026.10.2",
                    "createdAt": "2026-10-20T09:00:00Z",
                    "description": [["locale": "en", "text": "Faster picking and steadier packing lines."], ["locale": "ja-JP", "text": "ピッキングが速くなり、梱包ラインが安定します。"]],
                    "changelog": [
                        ["locale": "en", "text": "## Improvements\n\n- Pick cycles are about 8 percent shorter on mixed trays.\n- The packing line planner recovers from a label printer fault without a restart.\n\n## Fixes\n\n- Alarms no longer repeat after a network drop."],
                        ["locale": "ja-JP", "text": "## 改善\n\n- 混在トレイのピッキングサイクルが約8%短縮されました。\n- 梱包ラインのプランナーが、ラベルプリンターの障害から再起動なしで復旧します。\n\n## 修正\n\n- ネットワーク切断後にアラームが繰り返されなくなりました。"],
                    ],
                    "images": [["id": "image01", "tag": "2026.10.2", "labelVersion": "2026.10.2"]],
                ]
            ]
        case "ListReleases":
            return [
                "ListReleases": [
                    "releases": [
                        ["id": "release01", "name": "Autumn release", "channel": "stable", "status": "published", "versionString": "2026.10.2", "createdAt": "2026-10-20T09:00:00Z"],
                        ["id": "release02", "name": "Summer release", "channel": "stable", "status": "published", "versionString": "2026.7.5", "createdAt": "2026-07-14T09:00:00Z"],
                        ["id": "release03", "name": "Preview of the winter release", "channel": "preview", "status": "draft", "versionString": "2026.12.0-rc1", "createdAt": "2026-10-28T09:00:00Z"],
                    ], "meta": ["totalCount": 3],
                ]
            ]
        case "ListTicketsUsingRelease":
            return ["ListTicketsUsingRelease": [["id": "ticket01", "sequence": 1, "title": "Gripper drops boxes at pick station 3", "status": "open", "priority": "high", "siteId": "site01", "organizationId": "organization01", "authorUserId": "user01", "requesterUserId": "user01", "assigneeUserIds": []]]]
        case "GetReleaseImage":
            return ["GetReleaseImage": ["id": "image01", "releaseId": "release01", "registry": "registry.example.test", "repository": "controller/base", "tag": "2026.10.2", "digest": "sha256:0123abcd", "labelVersion": "2026.10.2", "labelProject": "appcontroller", "labelPreset": "standard", "labelHardwares": ["hw-a", "hw-b"], "labelBuild": "1042", "createdAt": "2026-10-20T09:00:00Z"]]
        case "ListControllersUsingRelease":
            return ["ListControllersUsingRelease": [["id": "controller01", "comment": "Pick station controller", "releaseId": "release01", "releaseImageId": "image01"], ["id": "controller02", "releaseId": "release01"]]]
        case "ListVirtualControllersUsingRelease":
            return ["ListVirtualControllersUsingRelease": [["id": "virtual01", "name": "Training cell", "status": "running", "releaseId": "release01"]]]
        case "ListControllerSyncedUserCounts":
            return ["ListControllerSyncedUserCounts": [["controllerId": "controller01", "count": 3, "isAvailable": true], ["controllerId": "controller02", "count": 0, "isAvailable": true]]]
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
        case "ListNotifications":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListNotifications": [
                    "notifications": [
                        ["id": "notification01", "kind": "ticket_comment", "createdAt": stamp(900), "ticketId": "ticket01", "ticket": ["id": "ticket01", "sequence": 1, "title": "Gripper drops boxes at pick station 3"]],
                        ["id": "notification02", "kind": "incident", "createdAt": stamp(2_400), "incidentId": "incident01", "incident": ["id": "incident01", "title": "Person near the conveyor"]],
                        ["id": "notification03", "kind": "alarm", "createdAt": stamp(5_000), "readAt": stamp(4_000), "alarmMessage": "Gripper suction pressure is low", "siteName": "site01"],
                        ["id": "notification04", "kind": "agent_job_failed", "createdAt": stamp(20_000), "readAt": stamp(19_000), "agentJobName": "Watch controller01 planner", "agentJobFailureMessage": "The controller did not answer."],
                    ], "meta": ["totalCount": 4],
                ]
            ]
        case "CountUnreadNotifications":
            return ["CountUnreadNotifications": 2]
        case "MarkNotificationRead", "MarkAllNotificationsRead":
            return [operation: NSNull()]
        case "NotificationPreferences":
            return ["NotificationPreferences": [["kind": "incident", "channel": "push", "isEnabled": false], ["kind": "agent_job_failed", "channel": "email", "isEnabled": true]]]
        case "SetNotificationPreference":
            return ["SetNotificationPreference": ["kind": variables["kind"] as? String ?? "", "channel": variables["channel"] as? String ?? "", "isEnabled": variables["isEnabled"] as? Bool ?? true]]
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
        case "EnsureMainConversation":
            let main = state.withData { data in data.conversations.first { ($0["isMain"] as? Bool) == true } ?? [:] }
            return ["EnsureMainConversation": ["conversation": main]]
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
        case "SendMessage" where conversationId.hasPrefix("chatconv"):
            let message = variables["message"] as? String ?? ""
            let row: [String: Any] = [
                "id": "demo-chat-\(Int.random(in: 1000...9999))", "role": "user", "content": message, "createdAt": ISO8601DateFormatter().string(from: Date()), "isChatMessage": true,
                "authorUserId": "user01", "authorName": "Alex Example", "replyToMessageId": variables["replyToMessageId"] ?? NSNull(),
            ]
            state.withData { $0.messages[conversationId, default: []].append(row) }
            return ["SendMessage": ["runId": "", "message": row]]
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
        case "ListGoals":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListGoals": [
                    "goals": [
                        [
                            "id": "goal01", "title": "Keep dock waits under 20 minutes", "description": "Watch the dock doors and tell me when a truck waits too long.",
                            "goalState": "waiting", "statusLine": "Dock door 3 opened late four mornings in a row.", "waitingQuestion": "Should I also watch dock door 4?",
                            "conversationId": "conversation06", "nextCheckAt": stamp(-3_600), "lastCheckAt": stamp(1_800), "checkIntervalMinutes": 60, "turnCount": 9, "todayTurnCount": 3,
                        ],
                        [
                            "id": "goal02", "title": "Reduce pallet rework at site02", "goalState": "working", "statusLine": "Rework fell from 6 to 4 percent this week.",
                            "nextCheckAt": stamp(-7_200), "lastCheckAt": stamp(3_000), "checkIntervalMinutes": 240, "turnCount": 14, "todayTurnCount": 1,
                        ],
                        ["id": "goal03", "title": "Clear the open alarm backlog", "goalState": "met", "statusLine": "No open alarms remain.", "turnCount": 6],
                    ], "meta": ["totalCount": 3],
                ]
            ]
        case "GetGoal":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "GetGoal": [
                    "id": "goal01", "title": "Keep dock waits under 20 minutes", "description": "Watch the dock doors and tell me when a truck waits too long.",
                    "goalState": "waiting", "statusLine": "Dock door 3 opened late four mornings in a row.", "waitingQuestion": "Should I also watch dock door 4?",
                    "conversationId": "conversation06", "nextCheckAt": stamp(-3_600), "lastCheckAt": stamp(1_800), "checkIntervalMinutes": 60, "turnCount": 9, "todayTurnCount": 3,
                ]
            ]
        case "ListGoalActivities":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListGoalActivities": [
                    ["id": "activity-goal1", "goalId": "goal01", "activityText": "Read the last 30 days of dock door events.", "createdAt": stamp(7_000)],
                    ["id": "activity-goal2", "goalId": "goal01", "activityText": "Found that door 3 opens late on weekday mornings.", "createdAt": stamp(1_800)],
                ]
            ]
        case "ListIdeas":
            return [
                "ListIdeas": [
                    "ideas": [
                        [
                            "id": "idea01", "ideaKind": "found", "headline": "Watch dock door 3", "rank": 1,
                            "body": "It opened late four mornings in a row. I can watch it and tell you each time.",
                            "evidence": [["evidenceKind": "site", "evidenceId": "site01", "evidenceLabel": "Site01"], ["evidenceKind": "ticket", "evidenceId": "ticket01", "evidenceLabel": "#1 Gripper drops boxes"]],
                        ],
                        ["id": "catalog:weekly", "ideaKind": "catalog", "headline": "A weekly summary on Mondays", "rank": 2, "body": "Get the week's throughput and alarms as one short note every Monday morning."],
                    ]
                ]
            ]
        case "ListMemoryPages":
            return [
                "ListMemoryPages": [
                    "memoryPages": [
                        ["id": "page01", "path": "people/sample-person/work-habits", "memoryScope": "user", "name": "", "summary": "How you like answers written.", "liveFactCount": 3],
                        ["id": "page02", "path": "site/site01/docks", "memoryScope": "site", "name": "Site01 docks", "summary": "Door timings and known quirks.", "liveFactCount": 5],
                        ["id": "page03", "path": "organization/shifts", "memoryScope": "organization", "name": "Shift pattern", "summary": "Three shifts, handover at 06:00, 14:00 and 22:00.", "liveFactCount": 2],
                        ["id": "page04", "path": "organization/dock-door-rules", "memoryScope": "organization", "name": "", "liveFactCount": 1],
                    ], "meta": ["totalCount": 3],
                ]
            ]
        case "GetMemoryPage":
            return [
                "GetMemoryPage": [
                    "id": "page01", "path": "people/sample-person/work-habits", "memoryScope": "user", "name": "", "summary": "How you like answers written.", "liveFactCount": 3,
                    "isWritableByReader": true, "aliases": [],
                    "facts": [
                        ["id": "fact01", "number": 1, "factKind": "preference", "sentence": "Prefers short answers without tables.", "evidence": [["evidenceKind": "conversation", "quote": "Keep it short, no tables please."]]],
                        ["id": "fact02", "number": 2, "factKind": "preference", "sentence": "Reads the summary first and the details only if needed.", "isInferred": true],
                        ["id": "fact03", "number": 3, "factKind": "fact", "sentence": "Works the early shift at site01."],
                        ["id": "fact04", "number": 4, "factKind": "fact", "sentence": "Used to work at site03.", "supersededByFactId": "fact03"],
                    ],
                    "links": [["fromMemoryPageId": "page01", "toMemoryPageId": "page02", "relation": "works_on", "linkStatus": "stated", "toPageName": "Site01 docks", "toPagePath": "site/site01/docks"]],
                ]
            ]
        case "ListMemoryRevisions":
            return ["ListMemoryRevisions": [["revisionNumber": 2, "revisionKind": "fact_added", "actorKind": "assistant", "changeReason": "Filed after a conversation", "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3_600))]]]
        case "GetAgentDreamSetting":
            return [
                "GetAgentDreamSetting": [
                    "organizationId": "organization01", "isDreamEnabled": true, "dreamBudgetSharePercent": 20, "dreamTokenCap": 200_000, "dailyTokenAllowance": 2_000_000,
                    "todayBudgetTokenCount": 400_000, "todaySpentTokenCount": 120_000, "lastDreamEndedAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-14_000)),
                    "isDreaming": false, "hasBacklog": true, "canManageOrganization": true,
                ]
            ]
        case "ListMemoryLinkProposals":
            return ["ListMemoryLinkProposals": [["fromMemoryPageId": "page02", "toMemoryPageId": "page03", "relation": "follows", "linkStatus": "proposed", "fromPageName": "Site01 docks", "toPageName": "Shift pattern"]]]
        case "ListMemoryDreams":
            return [
                "ListMemoryDreams": [
                    "memoryDreams": [
                        [
                            "id": "dream01", "dreamStatus": "completed", "dreamTrigger": "automatic", "startedAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-14_400)),
                            "endedAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-14_000)),
                            "phaseReports": [["dreamPhase": "decay", "phaseOutcome": "done", "doneItemCount": 4], ["dreamPhase": "associate", "phaseOutcome": "done", "doneItemCount": 1]],
                            "gapQuestions": ["Which dock handles returns?"],
                        ]
                    ], "meta": ["totalCount": 1],
                ]
            ]
        case "GetAgentSpeakFirstSetting":
            return ["GetAgentSpeakFirstSetting": ["isEnabledForOrganization": true, "isEnabledForUser": true, "disabledReasons": ["memory_check"], "canManageOrganization": true]]
        case "GetAgentMemorySetting":
            return ["GetAgentMemorySetting": ["isFilingEnabledForUser": true, "isFilingEnabledForOrganization": true, "canManageOrganization": true]]
        case "GetAgentVoiceSetting":
            return ["GetAgentVoiceSetting": ["speechVoice": "", "defaultSpeechVoice": "alloy", "speechVoices": ["alloy", "ash", "coral", "nova", "sage"]]]
        case "GetAgentBackgroundSetting":
            return ["GetAgentBackgroundSetting": ["areGoalsEnabled": true, "areFoundIdeasEnabled": true, "isSpeakFirstEnabled": true, "canManageOrganization": true]]
        case "ListMemoryFilings":
            guard conversationId == "conversation06" else { return ["ListMemoryFilings": []] }
            return [
                "ListMemoryFilings": [
                    [
                        "id": "filing01", "sourceKind": "conversation", "conversationId": "conversation06", "filingTrigger": "automatic", "writtenFactCount": 2,
                        "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)),
                        "facts": [
                            ["id": "fact02", "number": 2, "pagePath": "people/sample-person/work-habits", "sentence": "Reads the summary first and the details only if needed.", "isInferred": true, "memoryScope": "user"],
                            ["id": "fact05", "number": 5, "pagePath": "site/site01/docks", "sentence": "Dock door 3 opens late on weekday mornings.", "memoryScope": "site"],
                        ],
                    ]
                ]
            ]
        case "ListConversationArtifacts":
            guard conversationId == "conversation04" else { return ["ListConversationArtifacts": []] }
            return ["ListConversationArtifacts": [["id": "artifact01", "conversationId": "conversation04", "attachmentId": "attachment01", "title": "Throughput by site", "artifactKind": "html", "sizeBytes": 2048]]]
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


/// DemoPictures draws the avatars and the logo the demo server serves: a head and shoulders on a colored ground.
enum DemoPictures {
    static func jpeg(forPath path: String) -> Data? {
        switch path {
        case "/api/v1/user/user02/avatar": return render(ground: .systemTeal, figure: .white, isLogo: false)
        case "/api/v1/user/user03/avatar": return render(ground: .systemOrange, figure: .white, isLogo: false)
        case "/api/v1/organization/organization01/logo": return render(ground: .systemIndigo, figure: .white, isLogo: true)
        case "/api/v1/attachment/imagedemo01", "/api/v1/attachment/imagedemo02", "/api/v1/attachment/videodemo01": return camera()
        case "/api/v1/attachment/pdfdemo01": return pdf()
        default: return nil
        }
    }

    /// A camera frame of a pick station, drawn from shapes: a belt, boxes and a gripper.
    private static func camera() -> Data {
        let size = CGSize(width: 800, height: 520)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.85) { _ in
            UIColor(red: 0.16, green: 0.2, blue: 0.26, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor(red: 0.28, green: 0.32, blue: 0.38, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 360, width: 800, height: 160)).fill()
            UIColor.systemOrange.setFill()
            for index in 0..<4 { UIBezierPath(roundedRect: CGRect(x: 60 + CGFloat(index) * 180, y: 300, width: 120, height: 90), cornerRadius: 6).fill() }
            UIColor(white: 0.85, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 380, y: 0, width: 30, height: 190)).fill()
            UIBezierPath(roundedRect: CGRect(x: 350, y: 180, width: 90, height: 40), cornerRadius: 8).fill()
            UIColor.systemTeal.setStroke()
            let frame = UIBezierPath(rect: CGRect(x: 20, y: 20, width: 760, height: 480))
            frame.lineWidth = 3
            frame.stroke()
        }
    }

    private static func pdf() -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28, weight: .bold)]
            "Pressure log".draw(at: CGPoint(x: 56, y: 56), withAttributes: attributes)
            "Suction pressure dips before each drop at the pick station.".draw(at: CGPoint(x: 56, y: 110), withAttributes: [.font: UIFont.systemFont(ofSize: 15)])
        }
    }

    private static func render(ground: UIColor, figure: UIColor, isLogo: Bool) -> Data {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            ground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            figure.withAlphaComponent(0.92).setFill()
            if isLogo {
                UIBezierPath(roundedRect: CGRect(x: 50, y: 60, width: 100, height: 90), cornerRadius: 10).fill()
                UIBezierPath(roundedRect: CGRect(x: 70, y: 30, width: 60, height: 40), cornerRadius: 8).fill()
            } else {
                UIBezierPath(ovalIn: CGRect(x: 70, y: 40, width: 60, height: 60)).fill()
                UIBezierPath(ovalIn: CGRect(x: 35, y: 115, width: 130, height: 130)).fill()
            }
        }
    }
}
