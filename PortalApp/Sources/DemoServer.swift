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
    /// The code on the link address the demo's scan screen pretends to read.
    static let linkCode = "ZGVtby1saW5rLWNvZGUtMDEyMzQ1Njc4OQ"

    static func makeModel(isSignedIn: Bool = !["welcome", "demo-entered"].contains(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] ?? "")) -> AppModel {
        let account = Account(
            server: server, clientId: PortalClient.builtInClientId, userId: "user01", displayName: "Alex Example", email: "alex@example.test",
            accessToken: "demo-access", refreshToken: "demo-refresh", accessTokenExpiresAt: Date().addingTimeInterval(365 * 24 * 3600))
        let store = MemoryAccountStore(ring: isSignedIn ? AccountRing(accounts: [account], activeAccountKey: account.accountKey) : AccountRing())
        let state = DemoState()
        return AppModel(
            store: store, transport: DemoTransport(state: state),
            socketFactory: { _, _ in DemoSocket(state: state) }, cameraSocketFactory: { url, _ in DemoCameraSocket(url: url) }, isDemo: true)
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
        /// How many times the demo was asked to send feedback, for the screen that refuses the first.
        var feedbackSendCount = 0
        /// The controllers left out of site views, for the screens that have the feature.
        var excludedControllerIds: Set<String> = []
        var virtualControllerName = "Training cell"
        var virtualControllerSize = "medium"
        var isVirtualControllerPaused = false
        var isVirtualControllerDestroyed = false
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
            conversation("conversation02", "Restart the planner on controller1", "Waiting for your approval.", 120, running: true),
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
                    - **site03** had two short network drops on `controller2`.

                    ## Next steps

                    1. Check the cabling at site03.
                    2. Review the alarm thresholds.

                    > Nothing needs your action today.
                    """,
            ],
            ["id": "m03", "role": "user", "content": "Show me the stations, and where the checklist is.", "createdAt": stamp(3_000)],
            [
                "id": "m04", "role": "assistant", "createdAt": stamp(2_950),
                "content": """
                    The checklist is at [Suction cup checklist](https://example.test/docs/suction) and the raw log is at https://example.test/logs/pressure.

                    | Station | State | Picks |
                    | :--- | :---: | ---: |
                    | Station 1 | Running | 1,204 |
                    | Station 2 | Idle | 87 |
                    | Station 3 | **Fault** | 12 |
                    """,
            ],
            [
                "id": "m05", "role": "assistant", "createdAt": stamp(2_900),
                "content": """
                    The longer view, from `controller2`:

                    | Station | Operator | Last pick | Picks today | Average cycle | Drops | Note |
                    | --- | --- | --- | ---: | ---: | ---: | --- |
                    | Station 1 | Robin Demo | 09:41:07 | 1,204 | 3.2 s | 2 | Hose replaced |
                    | Station 2 | Jordan Placeholder | 08:15:52 | 87 | 4.8 s | 0 | Waiting for stock |
                    | Station 3 | Not assigned | 07:02:30 | 12 | 9.6 s | 5 | See ticket #1 |
                    """,
            ],
        ]
        if DemoOptions.screen == "conversation-links" {
            data.messages["conversation01"]?.append([
                "id": "m06", "role": "assistant", "createdAt": stamp(2_800),
                "content": """
                    [Assistant checklist](https://example.test/docs/assistant)

                    https://example.test/docs/assistant-plain

                    [Assistant ticket](https://demo.example.test/ticket/1)

                    [controller3](/controller/controller3)

                    [[site/site01/docks#2]]

                    - [Assistant list checklist](https://example.test/docs/assistant-list)
                    - A plain item

                    > [Assistant quote checklist](https://example.test/docs/assistant-quote)

                    | Document | Link |
                    | --- | --- |
                    | Hose guide | [Assistant table checklist](https://example.test/docs/assistant-table) |
                    """,
            ])
        }
        data.messages["conversation02"] = [
            ["id": "m10", "role": "user", "content": "Restart the planner on controller1.", "createdAt": stamp(200)],
            [
                "id": "m11", "role": "assistant", "content": "I will check the planner status first.", "createdAt": stamp(190),
                "toolCalls": [["id": "call01", "function": ["name": "controllers", "arguments": "{\"action\":\"status\",\"controller\":\"controller1\"}"]]],
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
        // A turn at work between two of its steps: it said what it is doing, one step is done and the next is still running.
        if DemoOptions.screen == "conversation:conversation-working" {
            data.conversations.append(conversation("conversation-working", "Pick rates this week", "Comparing the two cells.", 20, running: true))
            data.messages["conversation-working"] = [
                ["id": "m70", "role": "user", "content": "Compare the pick rates of the two cells on site01 this week.", "createdAt": stamp(40)],
                [
                    "id": "m71", "role": "assistant", "content": "I'll read this week's pick rates for both cells first.", "createdAt": stamp(36),
                    "toolCalls": [call("call70", "controllers", "{\"action\":\"telemetry\",\"cell\":\"cell01\"}")],
                ],
                toolMessage("m72", "call70", "controllers", "pick rate: 412 per hour", note: "Read the pick rates of Pick cell A", durationMS: 1_400, 34),
                ["id": "m73", "role": "assistant", "content": "", "createdAt": stamp(30), "toolCalls": [call("call71", "controllers", "{\"action\":\"telemetry\",\"cell\":\"cell02\"}")]],
            ]
        }
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
            chatRow("chatsite01", "chat-site", "site", "Plant North · Example Logistics", "The dock door sensor is back.", "Robin Demo", unread: 0, secondsAgo: 9_000, members: [
                member("user01", "Alex Example", "organization01", "Example Logistics"),
                member("user02", "Sam Sample", "organization00", "Support", staff: true),
                member("user03", "Robin Demo", "organization01", "Example Logistics"),
                member("user04", "Jordan Placeholder", "organization01", "Example Logistics"),
                member("user05", "Casey Trial", "organization01", "Example Logistics"),
                member("user06", "Morgan Mock", "organization01", "Example Logistics"),
                member("user07", "Taylor Test", "organization01", "Example Logistics"),
                member("user08", "Riley Stub", "organization00", "Support", staff: true),
                member("user09", "Quinn Fixture", "organization01", "Example Logistics"),
                member("user10", "Avery Draft", "organization01", "Example Logistics"),
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
            said("c9", "user02", "Sam Sample", "Notes: [Suction cup checklist](https://example.test/docs/suction) and the log https://example.test/logs/pressure.", 540),
            said("c10", "user02", "Sam Sample", "Dips this week:\n\n| Station | Dips | Lowest kPa |\n| :--- | ---: | ---: |\n| Station 3 | 4 | 31 |\n| Station 1 | 1 | 38 |", 500),
        ]
        if DemoOptions.screen == "chat-links" {
            // One link of each kind per message, each message holding nothing else, so the whole text is the link.
            data.messages["chatconv01"]?.append(contentsOf: [
                said("l1", "user02", "Sam Sample", "https://example.test/docs/plain", 400),
                said("l2", "user02", "Sam Sample", "[Pressure checklist](https://example.test/docs/markdown)", 390),
                said("l3", "user02", "Sam Sample", "[Gripper ticket](https://demo.example.test/ticket/1)", 380),
                said("l4", "user02", "Sam Sample", "| Document | Link |\n| --- | --- |\n| Hose guide | [Table checklist](https://example.test/docs/table) |", 370),
                said("l5", "user02", "Sam Sample", "- [List checklist](https://example.test/docs/list)\n- A plain item", 360),
                said("l6", "user02", "Sam Sample", "> [Quote checklist](https://example.test/docs/quote)", 350),
                // The assistant writes a Portal page as a path, with no server in it.
                said("l7", "assistant", "Mujin AI", "[controller1](/controller/controller1)", 340, role: "assistant"),
                said("l8", "assistant", "Mujin AI", "- [controller2](/controller/controller2) has an open alarm.\n- Another plain item", 330, role: "assistant"),
                said("l9", "assistant", "Mujin AI", "[Site by path](/site/site01)", 320, role: "assistant"),
                said("l10", "assistant", "Mujin AI", "[Ticket by path](/ticket/1)", 310, role: "assistant"),
            ])
        }
        data.messages["chatconv02"] = [
            said("d1", "user03", "Robin Demo", "Shift change at 14:00.", 7_200),
            said("d2", "user04", "Jordan Placeholder", "I can take the pick station.", 7_100),
        ]
        if CallDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) {
            data.chats.append(CallDemo.chatRow(stamp: stamp))
            data.messages["chatconv03"] = CallDemo.messages(screen: ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] ?? "", stamp: stamp)
        }
        if ThreadDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) {
            data.chats.append(ThreadDemo.chatRow(stamp: stamp))
            data.conversations.append(ThreadDemo.assistantRow(stamp: stamp))
            data.messages[ThreadDemo.chatConversationId] = ThreadDemo.chatMessages(
                isAssistantWorking: ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "thread-chat-working",
                hasMedia: ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]?.hasPrefix("thread-chat-media") == true, stamp: stamp)
            data.messages[ThreadDemo.assistantConversationId] = ThreadDemo.assistantMessages(stamp: stamp)
        }
        data.tickets = [
            ticket("ticket01", 1, "Gripper drops boxes at pick station 3", "open", "high", requester: "user01", organization: "organization01", secondsAgo: 7_200),
            ticket("ticket02", 2, "Network drops on controller2", "pending", "normal", requester: "user03", organization: "organization02", secondsAgo: 20_000),
            ticket("ticket03", 3, "Label printer jams on the packing line", "new", "normal", requester: "user01", organization: "organization01", secondsAgo: 900),
            ticket("ticket04", 4, "Camera view is rotated", "solved", "low", requester: "user01", organization: "organization01", secondsAgo: 200_000),
            ticket("ticket05", 5, "Planner restart request", "closed", "normal", requester: "user03", organization: "organization02", secondsAgo: 900_000),
        ]
        if SiteViewDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) { data.excludedControllerIds = SiteViewDemo.initiallyExcludedControllerIds }
        if FeedbackDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]), !FeedbackDemo.hasNoFeedback(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) {
            data.tickets += FeedbackDemo.tickets(stamp: stamp)
            data.comments.merge(FeedbackDemo.comments(stamp: stamp)) { _, new in new }
        }
        data.comments["ticket01"] = [
            [
                "id": "comment01", "authorUserId": "user01", "isOriginalRequest": true, "isInternal": false, "createdAt": stamp(10_800),
                "body": "The gripper drops about one box in twenty at pick station 3. A frame from the camera, the walkthrough and the pressure log are attached.\n\n![frame_008.jpg](attachment:imagedemo01)\n\n<video src=\"attachment:videodemo01\" controls preload=\"metadata\" width=\"100%\" title=\"station-walkthrough.mp4\"></video>\n\n<iframe src=\"attachment:pdfdemo01\" width=\"100%\" height=\"600\" title=\"pressure-log.pdf\"></iframe>\n\n![shelf.jpg](attachment:imagedemo03)\n\n![removed.png](attachment:missingdemo01)",
            ],
            [
                "id": "comment02", "authorUserId": "user02", "isInternal": false, "createdAt": stamp(7_200),
                "body": "Thanks Alex. I looked at the last two hours of logs and the suction pressure dips before each drop. Can you check the hose at the gripper?\(DemoOptions.screen?.hasPrefix("search-q:") == true ? "\n\n[Suction cup checklist](https://example.test/docs/suction)" : "")",
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
    func playAnswer(conversationId: String, text: String, threadRootMessageId: String? = nil) {
        let messageId = withData { data -> String in
            data.nextNumber += 1
            return "demo-message-\(data.nextNumber)"
        }
        Task {
            // Every event of a run answering in a thread says which.
            let threadFields: [String: Any] = threadRootMessageId.map { ["threadRootMessageId": $0] } ?? [:]
            try? await Task.sleep(nanoseconds: 300_000_000)
            var spoken = ""
            for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                spoken += (spoken.isEmpty ? "" : " ") + word
                broadcast(
                    conversationId: conversationId,
                    event: ["type": "text_delta", "runId": "run-demo", "textDelta": ["messageId": messageId, "text": (spoken == word ? "" : " ") + word]]
                        .merging(threadFields) { current, _ in current })
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            withData { data in
                let createdAt = ISO8601DateFormatter().string(from: Date())
                data.messages[conversationId, default: []].append(
                    ["id": messageId, "role": "assistant", "content": text, "createdAt": createdAt].merging(threadFields) { current, _ in current })
                if let threadRootMessageId {
                    ThreadDemo.countReply(under: threadRootMessageId, at: createdAt, in: &data.messages[conversationId, default: []])
                }
                if let index = data.conversations.firstIndex(where: { ($0["id"] as? String) == conversationId }) {
                    data.conversations[index]["activeRunId"] = NSNull()
                }
            }
            broadcast(
                conversationId: conversationId,
                event: ["type": "run_complete", "runId": "run-demo", "runComplete": ["stopReason": "end_turn"]].merging(threadFields) { current, _ in current })
            // As on the server: the title it writes from the first exchange comes a few seconds after the turn ends, as an event.
            if conversationId.hasPrefix("conversation-new-") {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                announceTitle(conversationId: conversationId, title: "A first question for the assistant")
            }
        }
    }

    /// Stores a conversation's title and tells every open feed about it, as the server does for each title it writes.
    func announceTitle(conversationId: String, title: String, isTitleCustom: Bool = false) {
        withData { data in
            if let index = data.conversations.firstIndex(where: { ($0["id"] as? String) == conversationId }) {
                data.conversations[index]["title"] = title
            }
        }
        broadcast(
            conversationId: conversationId,
            event: [
                "type": "conversation_updated",
                "conversationUpdated": ["conversationId": conversationId, "conversationTitle": title, "isTitleCustom": isTitleCustom],
            ])
    }
}

struct DemoTransport: HTTPTransport {
    let state: DemoState

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let path = request.url?.path, path.hasPrefix("/api/v1/unifiprotect/") {
            return DemoCameraPaths.respond(to: request)
        }
        if let path = request.url?.path, path.contains("/webapp/"), path.hasSuffix("/icon") {
            // Most demo apps have an icon (one of them an SVG, as real apps ship); one is listed with an icon the server does not have.
            let icon = DemoWebApps.icon(forPath: path)
            let response = HTTPURLResponse(url: request.url!, statusCode: icon == nil ? 404 : 200, httpVersion: nil, headerFields: ["Content-Type": icon?.contentType ?? "text/plain"])!
            return (icon?.data ?? Data(), response)
        }
        if let url = request.url, url.path.hasSuffix("voicewebm") {
            // A browser's recording, which the phone cannot play.
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/webm;codecs=opus"])!)
        }
        if request.httpMethod == "POST", request.url?.path == "/api/v1/attachment" {
            // An upload: the demo keeps nothing and names every file the same.
            return (Data(#"{"id":"upload-demo-01"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
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
        // A real server takes a moment, and a screen can open before the list it belongs to has arrived.
        if operation == "ListConversations", let delay = ProcessInfo.processInfo.environment["PORTAL_DEMO_LIST_DELAY_SECONDS"].flatMap(UInt64.init) {
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
        }
        if operation == "ListPortalFeedback", FeedbackDemo.failsToList(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) {
            let refusal = try JSONSerialization.data(withJSONObject: ["errors": [["message": FeedbackDemo.listFailureMessage]]])
            return (refusal, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        if operation == "SubmitPortalFeedback", FeedbackDemo.failsFirstSend(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]),
            state.withData({ data in
                data.feedbackSendCount += 1
                return data.feedbackSendCount
            }) == 1
        {
            let refusal = try JSONSerialization.data(withJSONObject: ["errors": [["message": FeedbackDemo.failureMessage]]])
            return (refusal, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        if let message = PagesDemo.refusal(operation: operation, screen: ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) {
            let refusal = try JSONSerialization.data(withJSONObject: ["errors": [["message": message]]])
            return (refusal, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let answer = respond(operation: operation, variables: variables)
        let payload = try JSONSerialization.data(withJSONObject: ["data": answer])
        return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    /// The answers of the screens for a controller left out of site views, a site's telemetry source and the alarm levels.
    private func siteViewAnswer(operation: String, variables: [String: Any]) -> [String: Any]? {
        let screen = ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]
        let excluded = state.withData { $0.excludedControllerIds }
        let cellId = variables["cellId"] as? String
        switch operation {
        case "ListControllers":
            let ids = SiteViewDemo.controllerIds(inCell: cellId)
            let rows = SiteViewDemo.controllerRows(excluded: excluded).filter { ids == nil || ids!.contains($0["id"] as? String ?? "") }
            return ["ListControllers": ["controllers": rows, "meta": ["totalCount": rows.count]]]
        case "GetController":
            let row = SiteViewDemo.controllerRows(excluded: excluded).first { ($0["id"] as? String) == (variables["controllerId"] as? String) }
            return ["GetController": row ?? NSNull()]
        case "ListCells":
            return ["ListCells": ["cells": SiteViewDemo.cells.map { ["id": $0.id, "name": $0.name, "controllerIds": $0.controllerIds, "virtualControllerIds": [], "cameraIds": []] as [String: Any] }]]
        case "ListControllerTelemetrySummaries":
            return ["ListControllerTelemetrySummaries": SiteViewDemo.telemetrySummaries(requested: variables["controllerIds"] as? [String])]
        case "ListSiteExcludedControllerIDs":
            let ids = SiteViewDemo.controllerIds(inCell: cellId)
            return ["ListSiteExcludedControllerIDs": excluded.sorted().filter { ids == nil || ids!.contains($0) }]
        case "ModifyControllerExclusion":
            let controllerId = variables["controllerId"] as? String ?? ""
            let isExcluded = (variables["controller"] as? [String: Any])?["isExcludedFromSiteViews"] as? Bool ?? false
            state.withData { data in
                if isExcluded { data.excludedControllerIds.insert(controllerId) } else { data.excludedControllerIds.remove(controllerId) }
            }
            return ["ModifyController": ["controller": ["id": controllerId, "isExcludedFromSiteViews": isExcluded]]]
        case "ListSiteActiveAlarms" where SiteViewDemo.alarmLevelScreens.contains(screen ?? ""):
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListSiteActiveAlarms": DemoCells.narrow(
                    [["controllerId": "controller1", "isAvailable": true, "alarms": ["alarms": SiteViewDemo.levelAlarms(screen: screen, stamp: stamp)]]], variables: variables)
            ]
        default:
            return nil
        }
    }

    /// The demo's one virtual controller, as the server describes it now.
    private static func virtualControllerRow(_ data: DemoState.Data) -> [String: Any] {
        [
            "id": "virtual01", "name": data.virtualControllerName, "comment": "Used for training", "siteId": "site01", "region": "us-1",
            "status": data.isVirtualControllerPaused ? "paused" : "running", "pausedAt": data.isVirtualControllerPaused ? "2026-10-30T10:00:00Z" : NSNull(),
            "size": data.virtualControllerSize, "product": "standard", "releaseId": "release01",
            "viewerCapabilities": ["virtual_controller:modify", "virtual_controller:destroy", "virtual_controller:connect"],
        ]
    }

    private func respond(operation: String, variables: [String: Any]) -> [String: Any] {
        if let answer = AccountDemo.respond(operation: operation, variables: variables) { return answer }
        if let answer = PlatformDemo.respond(operation: operation, variables: variables) { return answer }
        if let answer = ThreadDemo.respondToCalls(operation: operation, variables: variables, stamp: { ISO8601DateFormatter().string(from: Date().addingTimeInterval(-$0)) }) { return answer }
        if let answer = CallDemo.respond(operation: operation, variables: variables) { return answer }
        if let answer = SearchDemo.respond(operation: operation, variables: variables) { return answer }
        if let answer = PagesDemo.respond(operation: operation, variables: variables, screen: ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) { return answer }
        if SiteViewDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]), let answer = siteViewAnswer(operation: operation, variables: variables) { return answer }
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
            // The call screens are shot against a server that has voice messages and calls; the others against one that does not.
            let hasCalls = CallDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"])
            // The thread screens are shot against a server that reads one thread or the main history without replies.
            let hasThreads = ThreadDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"])
            // Dictation and reading aloud are shot against a server whose voice setting says whether each is set up.
            let hasSpeech = SpeechDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"])
            let hasCallHistory = ThreadDemo.isCallHistoryScreen(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"])
            var queryFields: [[String: Any]] = [
                ["name": "listTickets"], ["name": "listSites"], ["name": "listConversationWaiting"], ["name": "listChatCandidates"], ["name": "listControllerWebApps"],
                ["name": "globalSearch"],
                ["name": "listConversationMessages", "args": hasThreads ? [["name": "threadRootMessageId"]] : []],
            ]
            if hasCallHistory { queryFields.append(["name": "listChatCalls"]) }
            var mutationFields: [[String: Any]] = [
                ["name": "sendMessage", "args": hasCalls ? [["name": "voiceMessage"]] : []], ["name": "registerPushDevice"], ["name": "startDirectChat"], ["name": "openSiteChat"],
            ]
            if hasCalls { mutationFields += [["name": "startChatCall"], ["name": "joinChatCallMedia"]] }
            mutationFields.append(["name": "setMainConversation"])
            // Feedback about Portal is shot against a server that has it; every other screen is not.
            if FeedbackDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) { mutationFields.append(["name": "submitPortalFeedback"]) }
            // Leaving a controller out of site views, the site's telemetry source and the alarm levels come with one server release.
            let hasSiteViewRules = SiteViewDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"])
            if hasSiteViewRules { queryFields.append(["name": "listSiteExcludedControllerIDs", "args": [["name": "siteId"], ["name": "cellId"]]]) }
            if hasThreads { mutationFields.append(["name": "openChatMessage"]) }
            // Documentation pages are shot against a server that has them.
            let hasPages = PagesDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"])
            if hasPages {
                queryFields += ["listPages", "getPage", "getPageRevision", "listPageRevisions"].map { ["name": $0] }
                mutationFields += ["createPage", "modifyPage", "publishPage"].map { ["name": $0] }
            }
            var schemaAnswer: [String: Any] = [
                "__schema": [
                    "queryType": ["fields": queryFields],
                    "mutationType": ["fields": mutationFields],
                    "subscriptionType": ["fields": [["name": "onConversationEvent"]] + (hasCalls ? [["name": "onChatCallEvent"], ["name": "onChatCallSignal"]] : [])],
                ]
            ]
            let voiceSettingFields = hasSpeech ? SpeechDemo.voiceSettingFieldNames : ["speechVoice", "speechVoices", "defaultSpeechVoice", "previewText"]
            schemaAnswer["voiceSetting"] = ["fields": voiceSettingFields.map { ["name": $0] }]
            schemaAnswer["siteType"] = ["fields": (hasSiteViewRules ? ["id", "name", "telemetrySourceControllerId"] : ["id", "name"]).map { ["name": $0] }]
            if hasPages {
                let pageFields = ["id", "siteId", "parentPageId", "position", "currentRevisionId", "title", "icon", "isPublished", "draftTitle", "draftContent", "viewerCapabilities"]
                schemaAnswer["pageType"] = ["fields": pageFields.map { ["name": $0] }]
            }
            return schemaAnswer
        case "GetMainAgent":
            return ["GetMainAgent": ["id": "agent01", "name": "Assistant", "isMain": true]]
        case "ListConversations":
            if variables["conversationKind"] as? String == "chat" {
                // A list leaves out who is in a site chat, as a real server does.
                let rows = state.withData { $0.chats }.map { row -> [String: Any] in
                    guard var room = row["chat"] as? [String: Any], room["chatKind"] as? String == "site" else { return row }
                    room["members"] = [[String: Any]]()
                    var listed = row
                    listed["chat"] = room
                    return listed
                }
                return ["ListConversations": ["conversations": rows, "meta": ["totalCount": 3]]]
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
        case "ListSiteChatPeople":
            let people: [[String: Any]] = [("user01", "Alex Example"), ("user02", "Sam Sample"), ("user03", "Robin Demo"), ("user11", "Drew Sample")].map {
                ["userId": $0.0, "userName": $0.1, "organizationId": "organization01", "organizationName": "Example Logistics", "isMujinUser": false]
            }
            return ["ListSiteChatPeople": people]
        case "OpenChatMessage":
            // A link to a message opens the reader's own conversation of the chat; a message the demo does not hold is not found.
            let messageId = variables["messageId"] as? String ?? ""
            let isHeld = state.withData { $0.messages[ThreadDemo.chatConversationId]?.contains { ($0["id"] as? String) == messageId } ?? false }
            return isHeld ? ["OpenChatMessage": ["conversation": ["id": ThreadDemo.chatConversationId]]] : ["OpenChatMessage": NSNull()]
        case "GetMessageThreadRoot":
            let messageId = variables["messageId"] as? String ?? ""
            let root = state.withData { $0.messages[conversationId]?.first { ($0["id"] as? String) == messageId }?["threadRootMessageId"] }
            return ["GetMessageThreadRoot": ["threadRootMessageId": root ?? NSNull()]]
        case "OpenSiteChat":
            return ["OpenSiteChat": ["chat": ["id": "chat-site"], "conversation": ["id": "chatsite01"]]]
        case "AddChatMembers":
            // As on the server: the people join the same chat, and a direct chat becomes a group of everyone, its two people administrators.
            let chatId = variables["chatId"] as? String ?? ""
            let userIds = variables["userIds"] as? [String] ?? []
            let names = ["user02": "Sam Sample", "user03": "Robin Demo", "user04": "Jordan Placeholder", "user05": "Ana Support"]
            let chat = state.withData { data -> [String: Any] in
                guard let index = data.chats.firstIndex(where: { ($0["chat"] as? [String: Any])?["id"] as? String == chatId }),
                    var room = data.chats[index]["chat"] as? [String: Any]
                else { return [:] }
                var members = room["members"] as? [[String: Any]] ?? []
                if room["chatKind"] as? String == "direct" {
                    members = members.map { var member = $0; member["isAdmin"] = true; return member }
                    room["chatKind"] = "group"
                    room["isReaderAdmin"] = true
                }
                for userId in userIds where !members.contains(where: { $0["userId"] as? String == userId }) {
                    members.append([
                        "id": "member-\(userId)", "userId": userId, "userName": names[userId] ?? userId, "organizationId": "organization01",
                        "organizationName": "Example Logistics", "isMujinUser": false, "isAdmin": false, "lastReadMessageId": NSNull(), "leftAt": NSNull(),
                        "notificationLevel": "all",
                    ])
                }
                room["members"] = members
                if room["name"] is NSNull || room["name"] == nil {
                    let name = members.compactMap { ($0["userName"] as? String)?.split(separator: " ").first.map(String.init) }.joined(separator: ", ")
                    room["name"] = name
                    room["displayName"] = name
                    data.chats[index]["title"] = name
                }
                data.chats[index]["chat"] = room
                return room
            }
            return ["AddChatMembers": ["chat": chat]]
        case "ListMessageLinkPreviews":
            let ids = variables["messageIds"] as? [String] ?? []
            return [
                "ListMessageLinkPreviews": ids.compactMap { id -> [String: Any]? in
                    switch id {
                    case "t10":
                        return ["messageId": id, "isPending": false, "linkPreviews": [["urlHash": "hash05", "linkKind": "external", "url": "https://example.test/docs/door-wiring", "title": "Dock door wiring guide", "description": "Where the sensor cable runs and how to seat it.", "siteName": "example.test"]]]
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
        case "MarkChatRead":
            let chatId = variables["chatId"] as? String
            state.withData { data in
                for index in data.chats.indices where (data.chats[index]["chatId"] as? String) == chatId {
                    guard var room = data.chats[index]["chat"] as? [String: Any] else { continue }
                    room["readerUnreadMessageCount"] = 0
                    data.chats[index]["chat"] = room
                }
            }
            return [operation: NSNull()]
        case "SetChatTyping", "EditChatMessage", "DeleteChatMessage", "RemoveMessageLinkPreviews":
            return [operation: NSNull()]
        case "ListConversationMessages":
            return ["ListConversationMessages": ThreadDemo.messages(state.withData { $0.messages[conversationId] ?? [] }, variables: variables)]
        case "ListSites":
            let all: [[String: Any]] = [
                ["id": "site01", "name": "site01", "organizationId": "organization01", "isArchived": false, "viewerCapabilities": ["virtual_controller:create"]],
                ["id": "site02", "name": "site02", "organizationId": "organization01", "isArchived": false],
                ["id": "site03", "name": "Bakery line", "organizationId": "organization02", "isArchived": false],
                ["id": "site04", "name": "Cold store", "organizationId": "organization02", "isArchived": false],
                ["id": "site05", "name": "Lab cell", "organizationId": "organization00", "isArchived": false],
                ["id": "site06", "name": "Retired yard", "organizationId": "organization02", "isArchived": true],
            ]
            // A customer sees its own organization's sites; a Mujin user sees them all, or one organization's when asked.
            let scope = variables["organizationId"] as? String ?? (DemoOptions.isStaff ? nil : "organization01")
            let shown = SiteViewDemo.sites(all.filter { scope == nil || ($0["organizationId"] as? String) == scope }, screen: ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"])
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
                "ListSiteActiveAlarms": DemoCells.narrow([
                    [
                        "controllerId": "controller1", "isAvailable": true,
                        "alarms": ["alarms": [
                            ["logEntryId": "alarmEntry01", "alarmLevel": "error", "alarmMessage": "Gripper suction pressure is low", "alarmStatus": "active", "occurredAt": stamp(1_200), "originLabel": "Pick station gripper"],
                            ["logEntryId": "alarmEntry02", "alarmLevel": "warning", "alarmMessage": "Conveyor 2 is running slowly", "alarmStatus": "active", "occurredAt": stamp(5_400), "originLabel": "controller1"],
                        ]],
                    ],
                    ["controllerId": "controller2", "isAvailable": false, "alarms": NSNull()],
                ], variables: variables)
            ]
        case "GetAlarmDetail":
            // A controller's clock: the offset is part of the timestamp, as the real server sends it.
            let controllerClock = ISO8601DateFormatter()
            controllerClock.timeZone = TimeZone(secondsFromGMT: -4 * 3600) ?? .current
            return [
                "GetAlarmDetail": [
                    "logEntryId": variables["logEntryId"] as? String ?? "alarmEntry01", "alarmStatus": "active",
                    "alarmLevel": ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "alarm-levels-critical" ? "critical" : "error",
                    "alarmMessage": "Gripper suction pressure is low", "occurredAt": controllerClock.string(from: Date().addingTimeInterval(-1_200)),
                    "originKind": "device", "originControllerId": "controller1",
                    "originFields": [["key": "deviceName", "value": "gripper_1"], ["key": "zoneName", "value": "pick_zone_a"]],
                    "metadata": [
                        ["key": "alarmCode", "value": "E1042"], ["key": "pressureKPa", "value": "38.5"], ["key": "thresholdKPa", "value": "60"],
                        ["key": "isRecoverable", "value": "true"], ["key": "recentReadingsKPa", "value": "[61.2, 52.8, 44.1, 38.5]"],
                        ["key": "context", "value": "{\"cycleIndex\": 18, \"partName\": \"box_small\", \"pickerArm\": {\"name\": \"arm_1\", \"payloadKg\": 1.4}}"],
                        ["key": "operatorHint", "value": "Check the suction cup and the hose for a leak."],
                    ],
                ]
            ]
        case "ListSiteMobileRobots":
            return [
                "ListSiteMobileRobots": DemoCells.narrow([
                    [
                        "controllerId": "controller1", "isAvailable": true,
                        "mobileRobots": ["robots": [
                            ["name": "robot_1", "status": "Running", "isOnline": true, "hasError": false, "powerLevel": 0.82, "isCharging": false, "isLoaded": true],
                            ["name": "robot_2", "status": "Paused", "isOnline": true, "hasError": true, "error": "Lost localization near aisle 4", "powerLevel": 0.4, "isCharging": false, "isLoaded": false],
                            ["name": "robot_3", "status": "Offline", "isOnline": false, "hasError": false, "powerLevel": 0.1, "isCharging": true, "isLoaded": false],
                        ]],
                    ]
                ], variables: variables)
            ]
        case "ListControllers":
            let controllers: [[String: Any]] = [
                ["id": "controller1", "comment": "Pick station controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect", "controller:write", "controller:edit", "backup:delete"], "releaseId": "release01", "releaseImageId": "image01", "connection": ["id": "connection01"], "hypervisorState": ["version": "2026.10.2"]],
                ["id": "controller2", "comment": "Packing line controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect"], "releaseId": "release01", "connection": NSNull(), "hypervisorState": ["version": "2026.9.4"]],
                ["id": "controller3", "comment": "Palletizer controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect"], "releaseId": "release01", "connection": ["id": "connection03"], "hypervisorState": ["version": "2026.10.2"]],
            ]
            let shown = DemoCells.narrow(controllers, key: "id", variables: variables)
            return ["ListControllers": ["controllers": shown, "meta": ["totalCount": shown.count]]]
        case "GetController":
            let controllerId = variables["controllerId"] as? String ?? ""
            let known: [[String: Any]] = [
                ["id": "controller1", "comment": "Pick station controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect", "controller:write", "controller:edit", "backup:delete"], "releaseId": "release01", "releaseImageId": "image01", "connection": ["id": "connection01"], "hypervisorState": ["version": "2026.10.2"]],
                ["id": "controller2", "comment": "Packing line controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect"], "releaseId": "release01", "connection": NSNull(), "hypervisorState": ["version": "2026.9.4"]],
                ["id": "controller3", "comment": "Palletizer controller", "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": ["controller:connect"], "releaseId": "release01", "connection": ["id": "connection03"], "hypervisorState": ["version": "2026.10.2"]],
            ]
            if let controller = known.first(where: { ($0["id"] as? String) == controllerId }) { return ["GetController": controller] }
            return ["GetController": NSNull()]
        case "ListControllerTelemetrySummaries":
            let requestedIds = variables["controllerIds"] as? [String]
            let summaries: [[String: Any]] = [
                ["controllerId": "controller1", "isAvailable": true, "activeAlarmCount": 1, "totals": ["pickOperationCount": 1_480, "pickedPartCount": 1_392, "humanInterventionCount": 21, "directRobotThroughputPartsPerHour": 58.0]],
                ["controllerId": "controller2", "isAvailable": false],
                ["controllerId": "controller3", "isAvailable": true, "activeAlarmCount": 0, "totals": ["pickOperationCount": 620, "pickedPartCount": 604, "humanInterventionCount": 3, "directRobotThroughputPartsPerHour": 31.5]],
            ]
            return ["ListControllerTelemetrySummaries": summaries.filter { requestedIds == nil || requestedIds!.contains($0["controllerId"] as? String ?? "") }]
        case "ListCells":
            return ["ListCells": ["cells": DemoCells.rows]]
        case "ListSiteOrchestrators":
            return [
                "ListSiteOrchestrators": DemoCells.narrow([
                    [
                        "controllerId": "controller1", "isAvailable": true,
                        "orchestrators": ["activeRunModeName": "Normal", "orchestrators": [
                            ["orchestratorId": "orchestrator01", "orchestratorType": "productioncycle", "runStatus": "Idle", "processStatus": "Started", "hasError": false, "state": ["productionCycleStatus": "Running"]],
                            ["orchestratorId": "orchestrator02", "orchestratorType": "warehouseexecution", "runStatus": "Working", "processStatus": "Started", "hasError": false, "state": ["warehouseExecutionState": ["warehouseExecutionStatus": "Paused"]]],
                            ["orchestratorId": "orchestrator03", "orchestratorType": "packing_line", "runStatus": "Idle", "hasError": true, "statusMessage": "Label printer not responding", "state": ["printerIsReady": false]],
                        ]],
                    ],
                    ["controllerId": "controller2", "isAvailable": false],
                ], variables: variables)
            ]
        case "ListControllerAlarms", "ListControllerOrchestrators", "ListControllerMobileRobots":
            // A controller's own reads answer with its row of the site's, which is what the site's read held before the controller's own existed.
            let siteOperation = ["ListControllerAlarms": "ListSiteActiveAlarms", "ListControllerOrchestrators": "ListSiteOrchestrators", "ListControllerMobileRobots": "ListSiteMobileRobots"][operation] ?? ""
            let field = ["ListControllerAlarms": "alarms", "ListControllerOrchestrators": "orchestrators", "ListControllerMobileRobots": "mobileRobots"][operation] ?? ""
            let rows = respond(operation: siteOperation, variables: [:])[siteOperation] as? [[String: Any]] ?? []
            let row = rows.first { ($0["controllerId"] as? String) == (variables["controllerId"] as? String) }
            let answerName = ["ListControllerAlarms": "ListControllerActiveAlarms", "ListControllerOrchestrators": "ListControllerOrchestrators", "ListControllerMobileRobots": "ListControllerMobileRobots"][operation] ?? ""
            if let own = row?[field] as? [String: Any] { return [answerName: own] }
            if operation == "ListControllerAlarms" { return [answerName: ["alarms": [[String: Any]]()]] }
            if operation == "ListControllerMobileRobots" { return [answerName: ["robots": [[String: Any]]()]] }
            return [answerName: NSNull()]
        case "ListControllerWebApps":
            return ["ListControllerWebApps": DemoWebApps.list(controllerId: variables["controllerId"] as? String, virtualControllerId: variables["virtualControllerId"] as? String)]
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
                        ["locale": "en", "text": "## Data entry\n\nA long first paragraph, as a real release note has, that says what changed for the people on the floor and why, so that it wraps over several lines on a phone and takes fewer on a wide screen. It goes on for a while so that the height of the row depends on the width it is measured at.\n\n<img src=\"attachment:imagedemo02\" height=\"500px\" alt=\"The screen asking for data\" />\n\nAnother paragraph follows the picture and is about as long, so the row holds words, then a picture, then words, as a real note does, and the picture sits in the middle of it rather than at either end.\n\n![camera-01.jpg](attachment:imagedemo02)\n\n## Improvements\n\n- Pick cycles are about 8 percent shorter on mixed trays.\n- The packing line planner recovers from a label printer fault without a restart.\n\n## Fixes\n\n- Alarms no longer repeat after a network drop."],
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
            return ["ListControllersUsingRelease": [["id": "controller1", "comment": "Pick station controller", "releaseId": "release01", "releaseImageId": "image01"], ["id": "controller2", "releaseId": "release01"]]]
        case "ListVirtualControllerSnapshots":
            return ["ListVirtualControllerSnapshots": ["snapshots": [
                ["id": "snapshot01", "virtualControllerId": "virtual01", "comment": "Before the planner update", "status": "ready", "createdAt": "2026-10-28T08:00:00Z"],
                ["id": "snapshot02", "virtualControllerId": "virtual01", "comment": "Clean install", "status": "ready", "createdAt": "2026-10-20T08:00:00Z"],
            ], "meta": ["totalCount": 2]]]
        case "CreateVirtualControllerSnapshot", "RestoreVirtualControllerSnapshot", "ModifyVirtualControllerSnapshot", "DestroyVirtualControllerSnapshot":
            return [operation: ["virtualControllerSnapshot": ["id": "snapshot03", "status": "ready"]]]
        case "ListVirtualControllerProducts":
            return ["ListVirtualControllerProducts": [["name": "standard", "displayName": "Standard"], ["name": "palletizing", "displayName": "Palletizing"]]]
        case "ListVirtualControllerRegions":
            return ["ListVirtualControllerRegions": [["region": "us-1", "isLocal": true], ["region": "jp-1", "isLocal": false]]]
        case "CreateVirtualController":
            return ["CreateVirtualController": ["virtualController": Self.virtualControllerRow(DemoState.Data())]]
        case "ListBackups":
            return ["ListBackups": ["backups": [
                ["id": "backup01", "controllerId": "controller1", "label": "Nightly", "createdAt": "2026-10-30T02:00:00Z", "sizeBytes": 48_000_000, "sourceVersion": "2026.10.2"],
                ["id": "backup02", "controllerId": "controller1", "label": "Before the planner update", "createdAt": "2026-10-27T14:30:00Z", "sizeBytes": 47_500_000, "sourceVersion": "2026.9.4"],
            ], "meta": ["totalCount": 2]]]
        case "GetControllerSyncProgress":
            return ["GetControllerSyncProgress": ["retrievedAt": "2026-10-31T09:00:00Z", "syncState": ["reportedAt": "2026-10-31T09:00:00Z", "progress": [
                ["resourceType": "tickets", "pushedCount": 320, "totalCount": 400], ["resourceType": "pages", "pushedCount": 90, "totalCount": 90],
            ]]]]
        case "ModifyController", "AssignControllersToSite", "DeleteBackup":
            return [operation: ["controller": ["id": "controller1"], "backupId": "backup01", "controllerIds": ["controller1"]]]
        case "ListAlarmSubscriptions":
            return ["ListAlarmSubscriptions": ["alarmSubscriptions": [
                ["id": "alarm01", "name": "Pick station", "isEnabled": true, "minimumAlarmLevel": "warning", "controllerIds": ["controller1"], "virtualControllerIds": []],
            ], "meta": ["totalCount": 1]]]
        case "CreateAlarmSubscription", "ModifyAlarmSubscription", "DeleteAlarmSubscription":
            return [operation: NSNull()]
        case "ListAllVirtualControllers":
            let rows = state.withData { data -> [[String: Any]] in data.isVirtualControllerDestroyed ? [] : [Self.virtualControllerRow(data)] }
            return ["ListVirtualControllers": ["virtualControllers": rows, "meta": ["totalCount": rows.count]]]
        case "RetrieveControllerLink":
            return ["RetrieveControllerLink": ["id": "controller9", "comment": "New pick station", "viewerCapabilities": []]]
        case "ApproveControllerLink":
            return ["ApproveControllerLink": ["controller": ["id": "controller9"]]]
        case "GetControllerSettings":
            return ["GetController": ["id": "controller1", "isSyncEnabled": true, "syncIntervalSeconds": 3_600, "isBackupEnabled": true, "backupIntervalSeconds": 86_400]]
        case "SetControllerSyncSettings", "SetControllerBackupSettings":
            return [operation: ["controller": ["id": "controller1"]]]
        case "ListVirtualControllerAlarms":
            return ["ListControllerActiveAlarms": ["alarms": [["alarmLevel": "warning", "alarmMessage": "Disk usage above 80 percent", "alarmStatus": "active", "occurredAt": "2026-10-31T08:00:00Z"]]]]
        case "ListSiteVirtualControllers":
            let cell = DemoCells.cell(variables)
            let rows = state.withData { data -> [[String: Any]] in data.isVirtualControllerDestroyed ? [] : [Self.virtualControllerRow(data)] }
                .filter { cell == nil || cell!.virtualControllerIds.contains($0["id"] as? String ?? "") }
            return ["ListVirtualControllers": ["virtualControllers": rows]]
        case "GetVirtualController":
            return ["GetVirtualController": state.withData { Self.virtualControllerRow($0) }]
        case "SetVirtualControllersPaused":
            state.withData { $0.isVirtualControllerPaused = variables["paused"] as? Bool ?? false }
            return ["SetVirtualControllersPaused": ["virtualControllerIds": ["virtual01"]]]
        case "ModifyVirtualController":
            let input = variables["virtualController"] as? [String: Any] ?? [:]
            let row = state.withData { data -> [String: Any] in
                if let name = input["name"] as? String { data.virtualControllerName = name }
                if let size = input["size"] as? String { data.virtualControllerSize = size }
                return Self.virtualControllerRow(data)
            }
            return ["ModifyVirtualController": ["virtualController": row]]
        case "DestroyVirtualController":
            state.withData { $0.isVirtualControllerDestroyed = true }
            return ["DestroyVirtualController": ["virtualController": ["id": "virtual01", "status": "destroying"]]]
        case "ListVirtualControllerSizes":
            return ["ListVirtualControllerSizes": [["name": "small", "displayName": "Small", "diskCapacityBytes": 20_000_000_000], ["name": "medium", "displayName": "Medium", "diskCapacityBytes": 50_000_000_000], ["name": "large", "displayName": "Large", "diskCapacityBytes": 100_000_000_000]]]
        case "ListVirtualControllersUsingRelease":
            return ["ListVirtualControllersUsingRelease": [["id": "virtual01", "name": "Training cell", "status": "running", "releaseId": "release01"]]]
        case "ListControllerSyncedUserCounts":
            return ["ListControllerSyncedUserCounts": [["controllerId": "controller1", "count": 3, "isAvailable": true], ["controllerId": "controller2", "count": 0, "isAvailable": true]]]
        case "ListIncidents":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            return [
                "ListIncidents": [
                    "incidents": [
                        ["id": "incident01", "title": "Person near the conveyor", "description": "A person stood inside the marked zone while the conveyor ran.", "kind": "safety", "siteId": "site01", "cellId": "cell01", "controllerId": "controller1", "organizationId": "organization01", "reviewStatus": "new", "activityStatus": "active", "detectedAt": stamp(2_400), "confidence": 0.87],
                        ["id": "incident02", "title": "Pallet left in aisle", "kind": "obstruction", "siteId": "site01", "organizationId": "organization01", "reviewStatus": "confirmed", "activityStatus": "cleared", "detectedAt": stamp(90_000), "confidence": 0.74],
                    ], "meta": ["totalCount": 2],
                ]
            ]
        case "ListCameras", "GetCamera", "ListIncidentCameras":
            return DemoCameras.respond(operation: operation, variables: variables) ?? [:]
        case "ListIncidentEvidence":
            return ["ListIncidentEvidence": ["incidentEvidence": [["attachmentId": "attachment10", "contentType": "image/jpeg", "filename": "frame-001.jpg", "role": "frame"]]]]
        case "TransitionIncident":
            return ["TransitionIncident": ["incident": ["id": variables["incidentId"] as? String ?? "", "reviewStatus": variables["reviewStatus"] as? String ?? ""]]]
        case "ListNotifications":
            let stamp = { (secondsAgo: TimeInterval) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo)) }
            let rows: [[String: Any]] = [
                ["id": "notification01", "kind": "ticket_comment", "createdAt": stamp(900), "ticketId": "ticket01", "ticket": ["id": "ticket01", "sequence": 1, "title": "Gripper drops boxes at pick station 3"]],
                ["id": "notification02", "kind": "incident", "createdAt": stamp(2_400), "incidentId": "incident01", "incident": ["id": "incident01", "title": "Person near the conveyor"]],
                ["id": "notification03", "kind": "alarm", "createdAt": stamp(5_000), "readAt": stamp(4_000), "alarmMessage": "Gripper suction pressure is low", "controllerId": "controller1", "siteName": "site01"],
                ["id": "notification04", "kind": "agent_job_failed", "createdAt": stamp(20_000), "readAt": stamp(19_000), "agentJobName": "Watch controller1 planner", "agentJobFailureMessage": "The controller did not answer."],
                ["id": "notification05", "kind": "agent_message", "createdAt": stamp(30_000), "agentMessageConversationId": "conversation-main", "agentMessageExcerpt": "Main chat has a new answer"],
                ["id": "notification06", "kind": "chat_message", "createdAt": stamp(40_000), "chatConversationId": "chatconv01", "chatId": "chat01", "chatName": "Sam Sample", "chatAuthorName": "Sam Sample", "chatMessageExcerpt": "A new message in the chat"],
            ]
            let aggregations = (variables["options"] as? [String: Any])?["aggregations"] as? [[String: Any]]
            let status = (aggregations?.first?["filter"] as? [String: Any])?["value"] as? String
            let shown = rows.filter { status == nil || ($0["readAt"] != nil) == (status == "read") }
            return ["ListNotifications": ["notifications": shown, "meta": ["totalCount": shown.count]]]
        case "CountUnreadNotifications":
            return ["CountUnreadNotifications": 4]
        case "MarkNotificationRead", "MarkAllNotificationsRead":
            return [operation: NSNull()]
        case "NotificationPreferences":
            return ["NotificationPreferences": [["kind": "incident", "channel": "push", "isEnabled": false], ["kind": "agent_job_failed", "channel": "email", "isEnabled": true]]]
        case "SetNotificationPreference":
            return ["SetNotificationPreference": ["kind": variables["kind"] as? String ?? "", "channel": variables["channel"] as? String ?? "", "isEnabled": variables["isEnabled"] as? Bool ?? true]]
        case "ListTickets":
            let cell = DemoCells.cell(variables)
            let tickets = state.withData { data in cell.map { Array(data.tickets.prefix($0.ticketCount)) } ?? data.tickets }
            return ["ListTickets": ["tickets": tickets, "meta": ["totalCount": cell == nil ? 5 : tickets.count]]]
        case "GetTicket":
            let ticketId = variables["ticketId"] as? String ?? ""
            return ["GetTicket": state.withData { $0.tickets.first { ($0["id"] as? String) == ticketId } ?? [:] }]
        case "GetTicketBySequence":
            let sequence = (variables["sequence"] as? NSNumber)?.intValue ?? 0
            if let ticket = state.withData({ data in data.tickets.first { ($0["sequence"] as? Int) == sequence } }) { return ["GetTicketBySequence": ticket] }
            return ["GetTicketBySequence": NSNull()]
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
        case "ListPortalFeedback":
            let requesterUserId = variables["requesterUserId"] as? String ?? ""
            let rows = state.withData { data in data.tickets.filter { ($0["isPortalFeedback"] as? Bool) == true && ($0["requesterUserId"] as? String) == requesterUserId } }
            return ["ListTickets": ["tickets": rows, "meta": ["totalCount": rows.count]]]
        case "SubmitPortalFeedback":
            let feedbackText = variables["feedbackText"] as? String ?? ""
            let created: [String: Any] = state.withData { data in
                data.nextNumber += 1
                let row: [String: Any] = [
                    "id": "feedback-new-\(data.nextNumber)", "sequence": 100 + data.nextNumber, "title": "Portal feedback: " + feedbackText, "status": "new",
                    "priority": "normal", "organizationId": "organization01", "requesterUserId": "user01", "authorUserId": "user01", "description": feedbackText,
                    "createdAt": ISO8601DateFormatter().string(from: Date()), "modifiedAt": ISO8601DateFormatter().string(from: Date()), "isPortalFeedback": true,
                    "viewerCapabilities": [],
                ]
                data.tickets.insert(row, at: 0)
                return row
            }
            return ["SubmitPortalFeedback": ["ticket": created]]
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
                                "conversationId": conversationId, "conversationTitle": "Restart the planner on controller1", "waitingKind": "approval",
                                "interactionId": card["id"] ?? "", "promptText": "The assistant wants to restart the planner on controller1.", "toolName": "shell",
                                "toolRisk": "high", "askedAt": card["requestedAt"] ?? NSNull(),
                            ])
                        }
                    }
                    for (conversationId, cards) in data.questions {
                        for card in cards {
                            rows.append([
                                "conversationId": conversationId, "conversationTitle": "Restart the planner on controller1", "waitingKind": "question",
                                "interactionId": card["id"] ?? "", "promptText": card["question"] ?? "", "askedAt": card["askedAt"] ?? NSNull(),
                            ])
                        }
                    }
                    return rows
                }
            ]
        case "CountConversationMessages":
            let loaded = ThreadDemo.messages(state.withData { $0.messages[conversationId] ?? [] }, variables: variables).count
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
                        ["occurrenceKind": "job", "occursAt": at(tomorrow, 15), "subjectId": "job03", "title": "Watch controller1 planner", "jobType": "monitor"],
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
                            "id": "activity03", "activityKind": "monitor", "activityStatus": "failed", "title": "Watch controller1 planner", "startedAt": stamp(20_000),
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
            var row: [String: Any] = [
                "id": "demo-chat-\(Int.random(in: 1000...9999))", "role": "user", "content": message, "createdAt": ISO8601DateFormatter().string(from: Date()), "isChatMessage": true,
                "authorUserId": "user01", "authorName": "Alex Example", "replyToMessageId": variables["replyToMessageId"] ?? NSNull(),
            ]
            state.withData { data in
                // On the screens with threads a reply goes in the thread of the message it answers.
                if ThreadDemo.owns(DemoOptions.screen), let root = ThreadDemo.threadRoot(replyingTo: variables["replyToMessageId"] as? String, in: data.messages[conversationId] ?? []) {
                    row["threadRootMessageId"] = root
                    ThreadDemo.countReply(under: root, at: row["createdAt"] as? String ?? "", in: &data.messages[conversationId, default: []])
                }
                data.messages[conversationId, default: []].append(row)
            }
            return ["SendMessage": ["runId": "", "message": row]]
        case "SendMessage":
            let message = variables["message"] as? String ?? ""
            var threadRootMessageId: String?
            state.withData { data in
                data.nextNumber += 1
                var row: [String: Any] = [
                    "id": "demo-user-\(data.nextNumber)", "role": "user", "content": message, "createdAt": ISO8601DateFormatter().string(from: Date()),
                ]
                // On the screens with threads a reply goes in the thread of the message it answers, and so does the answer.
                if ThreadDemo.owns(DemoOptions.screen), let root = ThreadDemo.threadRoot(replyingTo: variables["replyToMessageId"] as? String, in: data.messages[conversationId] ?? []) {
                    row["threadRootMessageId"] = root
                    threadRootMessageId = root
                    ThreadDemo.countReply(under: root, at: row["createdAt"] as? String ?? "", in: &data.messages[conversationId, default: []])
                }
                data.messages[conversationId, default: []].append(row)
                if let index = data.conversations.firstIndex(where: { ($0["id"] as? String) == conversationId }) {
                    data.conversations[index]["activeRunId"] = "run-demo"
                }
            }
            // As on the server: the first message gives the conversation a placeholder title, announced at once.
            let isUntitled = state.withData { data in
                data.conversations.first { ($0["id"] as? String) == conversationId }?["title"] is NSNull
            }
            if isUntitled, let placeholder = ConversationListUpdate.placeholderTitle(for: message) {
                state.announceTitle(conversationId: conversationId, title: placeholder)
            }
            state.playAnswer(
                conversationId: conversationId,
                text: "This is a demo answer. Your real assistant would look this up and reply here, one word at a time.",
                threadRootMessageId: threadRootMessageId)
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
        case "SetMainConversation":
            return ["SetMainConversation": ["conversation": ["id": conversationId, "isMain": true]]]
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
            var voiceSetting: [String: Any] = ["speechVoice": "", "defaultSpeechVoice": "alloy", "speechVoices": ["alloy", "ash", "coral", "nova", "sage"]]
            // Dictation and reading aloud are set up on the screens that show them, and on no other.
            if SpeechDemo.owns(DemoOptions.screen) {
                voiceSetting["isDictationAvailable"] = true
                voiceSetting["isReadAloudAvailable"] = true
            }
            return ["GetAgentVoiceSetting": voiceSetting]
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
            // The title-event screen: a conversation is open when the server renames it, and the title changes at once.
            if DemoOptions.screen == "title-event", conversationId == "conversation01" {
                let demoState = state
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    demoState.announceTitle(conversationId: "conversation01", title: "Slow dock doors this week")
                }
            }
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
        case "/api/v1/attachment/imagedemo03": return tall()
        case "/api/v1/attachment/pdfdemo01": return pdf()
        default: return nil
        }
    }

    /// The still picture of one of the demo site's cameras: the same invented pick station with the boxes in another color and the gripper
    /// in another place for each.
    static func cameraFrame(variant: Int) -> Data { camera(variant: variant) }

    /// A camera frame of a pick station, drawn from shapes: a belt, boxes and a gripper.
    private static func camera(variant: Int = 0) -> Data {
        let boxColors: [UIColor] = [.systemOrange, .systemTeal, .systemYellow, .systemPink]
        let size = CGSize(width: 800, height: 520)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.85) { _ in
            UIColor(red: 0.16, green: 0.2, blue: 0.26, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor(red: 0.28, green: 0.32, blue: 0.38, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 360, width: 800, height: 160)).fill()
            boxColors[variant % boxColors.count].setFill()
            for index in 0..<4 { UIBezierPath(roundedRect: CGRect(x: 60 + CGFloat(index) * 180, y: 300, width: 120, height: 90), cornerRadius: 6).fill() }
            UIColor(white: 0.85, alpha: 1).setFill()
            let shift = CGFloat(variant % 4) * 70 - 100
            UIBezierPath(rect: CGRect(x: 380 + shift, y: 0, width: 30, height: 190)).fill()
            UIBezierPath(roundedRect: CGRect(x: 350 + shift, y: 180, width: 90, height: 40), cornerRadius: 8).fill()
            UIColor.systemTeal.setStroke()
            let frame = UIBezierPath(rect: CGRect(x: 20, y: 20, width: 760, height: 480))
            frame.lineWidth = 3
            frame.stroke()
        }
    }

    /// A tall picture, a shelf seen from the front.
    private static func tall() -> Data {
        let size = CGSize(width: 500, height: 900)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.85) { _ in
            UIColor(red: 0.2, green: 0.24, blue: 0.3, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor.systemOrange.setFill()
            for row in 0..<5 { for column in 0..<3 { UIBezierPath(roundedRect: CGRect(x: 40 + CGFloat(column) * 150, y: 40 + CGFloat(row) * 170, width: 120, height: 110), cornerRadius: 6).fill() } }
            UIColor.systemTeal.setStroke()
            let frame = UIBezierPath(rect: CGRect(x: 12, y: 12, width: 476, height: 876))
            frame.lineWidth = 4
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


/// DemoWebApps is the invented apps of the demo controller and virtual controller, and the icons the demo server serves for them.
enum DemoWebApps {
    private struct App {
        let id: String
        let name: String
        /// An SF Symbol drawn white on a colored square, or nil for the app that has no icon.
        let symbol: String?
        let color: UIColor
        let isIconMissing: Bool
    }

    private static let apps: [App] = [
        App(id: "pick-monitor", name: "Pick Monitor", symbol: "gauge.with.dots.needle.bottom.50percent", color: .systemOrange, isIconMissing: false),
        App(id: "line-statistics", name: "Line Statistics", symbol: nil, color: .systemBlue, isIconMissing: false),
        App(id: "station-setup", name: "Station Setup", symbol: "slider.horizontal.3", color: .systemGreen, isIconMissing: false),
        App(id: "calibration-helper", name: "Calibration Helper", symbol: "scope", color: .systemPurple, isIconMissing: false),
        App(id: "device-console", name: "Device Console", symbol: "terminal", color: .systemGray, isIconMissing: false),
        App(id: "order-board", name: "Order Board", symbol: "list.bullet.rectangle", color: .systemTeal, isIconMissing: false),
        App(id: "inbound-and-outbound-station-manager", name: "Inbound and Outbound Station Manager", symbol: nil, color: .systemIndigo, isIconMissing: true),
        App(id: "packing-review", name: "Packing Review", symbol: "shippingbox", color: .systemBrown, isIconMissing: true),
    ]

    /// The apps ListControllerWebApps answers for the demo's controllers: the online controller has eight, the virtual controller four,
    /// and the offline one has none to offer.
    static func list(controllerId: String?, virtualControllerId: String?) -> [String: Any] {
        let isVirtual = virtualControllerId != nil
        if controllerId == "controller2" { return ["isAvailable": false, "source": NSNull(), "webApps": []] }
        let shown = isVirtual ? apps.filter { ["pick-monitor", "station-setup", "device-console", "calibration-helper"].contains($0.id) } : apps
        let prefix = isVirtual ? "/api/v1/virtualcontroller/\(virtualControllerId ?? "")" : "/api/v1/controller/\(controllerId ?? "")"
        return [
            "isAvailable": true, "source": isVirtual ? "virtual" : "live",
            "webApps": shown.map { app -> [String: Any] in
                // The one with no icon at all has no icon address; "Packing Review" has an address the server cannot serve.
                let hasIconAddress = app.symbol != nil || app.id == "line-statistics"
                return [
                    "webAppId": app.id, "name": app.name, "versionString": "1.0.0", "openPath": "/app/\(app.id)",
                    "iconUrl": hasIconAddress ? "\(prefix)/webapp/\(app.id)/icon" : NSNull(),
                ]
            },
        ]
    }

    static func icon(forPath path: String) -> (data: Data, contentType: String)? {
        let parts = path.split(separator: "/")
        guard let index = parts.firstIndex(of: "webapp"), index + 1 < parts.count, let app = apps.first(where: { $0.id == String(parts[index + 1]) }), !app.isIconMissing else { return nil }
        guard let symbol = app.symbol else {
            let svg = """
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><rect width="96" height="96" rx="20" fill="#2f6fde"/>\
                <rect x="22" y="48" width="12" height="28" fill="white"/><rect x="42" y="32" width="12" height="44" fill="white"/>\
                <rect x="62" y="20" width="12" height="56" fill="white"/></svg>
                """
            return (Data(svg.utf8), "image/svg+xml")
        }
        let size = CGSize(width: 128, height: 128)
        let data = UIGraphicsImageRenderer(size: size).pngData { _ in
            app.color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 28).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
            if let image = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                image.draw(in: CGRect(x: (size.width - image.size.width) / 2, y: (size.height - image.size.height) / 2, width: image.size.width, height: image.size.height))
            }
        }
        return (data, "image/png")
    }
}
