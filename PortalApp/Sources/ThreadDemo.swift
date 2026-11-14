import Foundation
import PortalKit

/// ThreadDemo is the demo's message threads: a chat with people and a conversation with the assistant whose main history shows every message, replies
/// included, and the threads under them. It is served only on its own screens, against a server that has threads. Every name is invented.
enum ThreadDemo {
    static let screens: Set<String> = [
        "thread-chat", "thread-chat-open", "thread-chat-working", "thread-chat-media", "thread-chat-media-open", "thread-conversation",
        "thread-conversation-open", "thread-push", "thread-link",
        // The thread screens of dictation and reading aloud, which need the same server and data (see SpeechDemo).
        "dictate-thread-chat", "dictate-thread-conversation", "read-aloud-thread-chat", "read-aloud-thread-conversation",
    ]

    static let chatConversationId = "chatconv-thread"
    static let assistantConversationId = "conversation-threads"
    /// The message of the chat whose thread holds three replies, and the one of the conversation whose thread holds two.
    static let chatThreadRootMessageId = "t01"
    static let assistantThreadRootMessageId = "a02"

    static func owns(_ screen: String?) -> Bool { screen.map { screens.contains($0) } ?? false }

    /// The conversation a screen opens.
    static func conversationId(for screen: String?) -> String? {
        switch screen {
        case "thread-chat", "thread-chat-open", "thread-chat-working", "thread-chat-media", "thread-chat-media-open", "dictate-thread-chat",
            "read-aloud-thread-chat":
            chatConversationId
        case "thread-conversation", "thread-conversation-open", "dictate-thread-conversation", "read-aloud-thread-conversation": assistantConversationId
        default: nil
        }
    }

    /// The thread a screen opens on, once its conversation is open.
    static func threadToOpen(for screen: String?) -> ThreadToOpen? {
        switch screen {
        case "thread-chat-open", "thread-chat-media-open", "dictate-thread-chat", "read-aloud-thread-chat":
            ThreadToOpen(conversationId: chatConversationId, threadRootMessageId: chatThreadRootMessageId)
        case "thread-conversation-open", "dictate-thread-conversation", "read-aloud-thread-conversation": ThreadToOpen(conversationId: assistantConversationId, threadRootMessageId: assistantThreadRootMessageId)
        default: nil
        }
    }

    // MARK: the data

    static func chatRow(stamp: (TimeInterval) -> String) -> [String: Any] {
        func member(_ id: String, _ name: String, admin: Bool = false) -> [String: Any] {
            [
                "id": "member-\(id)", "userId": id, "userName": name, "organizationId": "organization01", "organizationName": "Example Logistics", "isMujinUser": false,
                "isAdmin": admin, "lastReadMessageId": NSNull(), "leftAt": NSNull(), "notificationLevel": "all",
            ]
        }
        return [
            "id": chatConversationId, "chatId": "chat-thread", "conversationKind": "chat", "title": "Dock team", "summary": NSNull(), "lastMessageAt": stamp(360),
            "activeRunId": NSNull(), "archivedAt": NSNull(), "createdAt": stamp(20_000), "modifiedAt": stamp(360), "isTitleCustom": false, "agentId": NSNull(),
            "chat": [
                "id": "chat-thread", "organizationId": "organization01", "chatKind": "group", "name": "Dock team", "displayName": "Dock team", "isMemoryFilingEnabled": false,
                "lastMessageAt": stamp(360), "readerConversationId": chatConversationId, "readerNotificationLevel": "all", "isReaderAdmin": true, "isReaderMember": true,
                "readerUnreadMessageCount": 0, "readerLastReadMessageId": NSNull(), "lastMessageExcerpt": "Fine by me.",
                "lastMessageAuthorName": "Robin Demo",
                "members": [member("user01", "Alex Example", admin: true), member("user03", "Robin Demo"), member("user04", "Jordan Placeholder")],
            ] as [String: Any],
        ]
    }

    static func assistantRow(stamp: (TimeInterval) -> String) -> [String: Any] {
        [
            "id": assistantConversationId, "agentId": "agent01", "title": "Dock door checks", "summary": "Which dock doors faulted this week.",
            "lastMessageAt": stamp(600), "activeRunId": NSNull(), "archivedAt": NSNull(), "createdAt": stamp(9_000), "modifiedAt": stamp(600), "isMain": false,
        ]
    }

    /// The messages of the chat. A message with a thread says how many replies it holds and when the last came; the replies carry
    /// the message they hang from. One old reply has no thread and keeps its quote. With `isAssistantWorking` the assistant has been
    /// asked a question and its answer has not come yet.
    static func chatMessages(isAssistantWorking: Bool, hasMedia: Bool = false, stamp: (TimeInterval) -> String) -> [[String: Any]] {
        func said(
            _ id: String, _ author: String, _ name: String, _ text: String, _ secondsAgo: TimeInterval, extra: [String: Any] = [:]
        ) -> [String: Any] {
            var row: [String: Any] = [
                "id": id, "role": "user", "content": text, "createdAt": stamp(secondsAgo), "isChatMessage": true, "authorUserId": author, "authorName": name,
                "authorOrganizationName": "Example Logistics", "authorOrganizationId": "organization01",
            ]
            for (key, value) in extra { row[key] = value }
            return row
        }
        func answer(_ id: String, _ text: String, _ secondsAgo: TimeInterval, extra: [String: Any]) -> [String: Any] {
            var row = said(id, "assistant", "Mujin AI", text, secondsAgo, extra: extra)
            row["role"] = "assistant"
            row["authorUserId"] = NSNull()
            row["onBehalfOfUserId"] = "user01"
            row["onBehalfOfUserName"] = "Alex Example"
            return row
        }
        var rows: [[String: Any]] = [
            said("t01", "user03", "Robin Demo", "The dock door 4 sensor has been flickering since this morning.", 14_400, extra: [
                "threadReplyCount": hasMedia ? 6 : 3, "threadLastReplyAt": stamp(hasMedia ? 1_200 : 1_500),
                "threadSubject": [
                    "referenceKind": "ticket", "writtenText": "", "isAccessible": true, "targetId": "ticket-demo13", "path": "/ticket/13",
                    "label": "#13 Door 4 sensor flickers", "ticketSequence": 13, "ticketTitle": "Door 4 sensor flickers", "ticketStatus": "open",
                ] as [String: Any],
            ]),
            said("t02", "user04", "Jordan Placeholder", "I saw it too. The cable looks loose at the frame.", 13_800, extra: ["threadRootMessageId": "t01", "replyToMessageId": "t01"]),
            said("t03", "user01", "Alex Example", "Can someone tighten it before the afternoon shift?", 12_000, extra: [
                "threadRootMessageId": "t01", "replyToMessageId": "t01", "replyToExcerpt": "The dock door 4 sensor has been flickering", "replyToAuthorName": "Robin Demo",
            ]),
            said("t05", "user04", "Jordan Placeholder", "Shift change moves to 14:00 on Friday.", 3_000),
            said("t04", "user03", "Robin Demo", "On it. I will tell you when it is done.", 1_500, extra: [
                "threadRootMessageId": "t01", "replyToMessageId": "t01", "replyToExcerpt": "The dock door 4 sensor has been flickering", "replyToAuthorName": "Robin Demo",
            ]),
        ]
        if hasMedia {
            // Replies that hold a link card, a photo, a video and a file, to see how each looks beside the bar.
            rows += [
                said("t10", "user04", "Jordan Placeholder", "The wiring guide: https://example.test/docs/door-wiring", 1_400, extra: ["threadRootMessageId": "t01"]),
                said("t11", "user03", "Robin Demo", "This is the cable: ![camera-door4.jpg](/api/v1/attachment/imagedemo01)", 1_300, extra: ["threadRootMessageId": "t01"]),
                said("t12", "user01", "Alex Example", "The walkthrough and the log:\n\n[station-walkthrough.mp4](/api/v1/attachment/videodemo01)\n\n[pressure-log.pdf](/api/v1/attachment/pdfdemo01)", 1_200, extra: ["threadRootMessageId": "t01"]),
            ]
        }
        rows += [
            said("t06", "user01", "Alex Example", "@Mujin AI which doors reported the most sensor changes today?", 900, extra: ["isAddressingAssistant": true]),
        ]
        if isAssistantWorking {
            rows[rows.count - 1]["threadReplyCount"] = 0
        } else {
            rows[rows.count - 1]["threadReplyCount"] = 1
            rows[rows.count - 1]["threadLastReplyAt"] = stamp(840)
            rows[rows.count - 1]["threadSubject"] = [
                "referenceKind": "cell", "writtenText": "", "isAccessible": true, "targetId": "cell-demo01", "path": "/site/site-demo01/cell/cell-demo01",
                "label": "Cell North 2", "cellName": "Cell North 2", "cellSiteName": "Example Depot",
            ] as [String: Any]
            rows.append(
                answer("t07", "Door 4 reported 212 changes today, door 2 reported 9 and the other doors fewer than 5.", 840, extra: [
                    "threadRootMessageId": "t06", "replyToMessageId": "t06",
                ]))
        }
        rows += [
            said("t08", "user04", "Jordan Placeholder", "Thanks, I will check door 4 after lunch.", 600),
            // Written before threads: no thread, so it keeps its quote in the main history.
            said("t09", "user03", "Robin Demo", "Fine by me.", 360, extra: [
                "replyToMessageId": "t05", "replyToExcerpt": "Shift change moves to 14:00 on Friday.", "replyToAuthorName": "Jordan Placeholder",
            ]),
        ]
        if hasMedia {
            // A message written in Markdown: bold, a list and code, with a person mentioned.
            rows.append(
                said("t13", "user04", "Jordan Placeholder", "@Robin Demo the **door 4** checklist:\n\n- tighten the cable\n- test the sensor\n\n`sensor.reset()`", 120))
        }
        return rows
    }

    static func assistantMessages(stamp: (TimeInterval) -> String) -> [[String: Any]] {
        [
            ["id": "a01", "role": "user", "content": "How did the dock doors do this week?", "createdAt": stamp(8_800)],
            [
                "id": "a02", "role": "assistant", "createdAt": stamp(8_700), "threadReplyCount": 3, "threadLastReplyAt": stamp(2_400),
                "content": "Door 4 had the most faults this week: nine sensor faults, mostly on Tuesday. Doors 1 to 3 had none.",
            ],
            [
                "id": "a03", "role": "user", "content": "Which of those were real faults?", "createdAt": stamp(2_500), "threadRootMessageId": "a02",
                "replyToMessageId": "a02", "replyToExcerpt": "Door 4 had the most faults this week", "replyToAuthorName": "Assistant",
            ],
            // A progress line and a step before the answer: with the step rows hidden, the answer follows the progress line.
            [
                "id": "a03b", "role": "assistant", "createdAt": stamp(2_480), "threadRootMessageId": "a02",
                "content": "I'll compare the fault times with the sensor log first.",
                "toolCalls": [["id": "call-a03", "function": ["name": "controllers", "arguments": "{\"action\":\"logs\"}"]] as [String: Any]],
            ],
            [
                "id": "a03c", "role": "tool", "toolCallId": "call-a03", "toolName": "controllers", "content": "9 entries", "createdAt": stamp(2_450),
                "threadRootMessageId": "a02", "metadata": ["toolNote": "Read the sensor log of door 4", "durationMS": 900] as [String: Any],
            ],
            [
                "id": "a04", "role": "assistant", "createdAt": stamp(2_400), "threadRootMessageId": "a02",
                "content": "Two of the nine were real faults. The other seven were the sensor flickering, which a cable check should fix.",
            ],
            ["id": "a05", "role": "user", "content": "Remind me to check the door 4 wiring on Friday.", "createdAt": stamp(700)],
            ["id": "a06", "role": "assistant", "createdAt": stamp(600), "content": "I will remind you on Friday morning."],
        ]
    }

    // MARK: past calls

    static func isCallHistoryScreen(_ screen: String?) -> Bool { screen?.hasPrefix("chat-call-history") == true }

    /// The past calls of the demo chat, and the words and recordings of one.
    static func respondToCalls(operation: String, variables: [String: Any], stamp: (TimeInterval) -> String) -> [String: Any]? {
        guard isCallHistoryScreen(DemoOptions.screen) else { return nil }
        func call(_ id: String, caller: String, reason: String, seconds: Int, ago: TimeInterval, segments: Int, recordings: Int) -> [String: Any] {
            [
                "id": id, "chatId": "chat02", "messageId": "d-\(id)", "startedByUserId": caller == "Alex Example" ? "user01" : "user03", "startedByUserName": caller,
                "startedAt": stamp(ago + Double(seconds)), "endedAt": stamp(ago), "endReason": reason, "durationMS": reason == "ended" ? seconds * 1000 : NSNull(),
                "transcriptState": segments > 0 ? "done" : "off", "recordingCount": recordings, "transcriptSegmentCount": segments,
                "members": [["userId": "user01", "userName": "Alex Example", "ringState": "answered"], ["userId": "user03", "userName": "Robin Demo", "ringState": "answered"]],
            ]
        }
        let calls = [
            call("past-call-1", caller: "Robin Demo", reason: "ended", seconds: 272, ago: 5_000, segments: 4, recordings: 2),
            call("past-call-2", caller: "Alex Example", reason: "missed", seconds: 0, ago: 90_000, segments: 0, recordings: 0),
            call("past-call-3", caller: "Robin Demo", reason: "ended", seconds: 61, ago: 200_000, segments: 0, recordings: 0),
        ]
        switch operation {
        case "ListChatCalls":
            let skipped = (variables["options"] as? [String: Any])?["after"] as? Int ?? 0
            return ["ListChatCalls": ["calls": Array(calls.dropFirst(skipped)), "meta": ["totalCount": calls.count]]]
        case "GetChatCall" where (variables["callId"] as? String)?.hasPrefix("past-call") == true:
            var detail = calls.first { ($0["id"] as? String) == variables["callId"] as? String } ?? calls[0]
            if detail["id"] as? String == "past-call-1" {
                detail["transcriptSegments"] = [
                    ["id": "s1", "userId": "user03", "userName": "Robin Demo", "startMS": 1_000, "endMS": 6_000, "text": "Door 4 is flickering again."],
                    ["id": "s2", "userId": "user01", "userName": "Alex Example", "startMS": 7_000, "endMS": 11_000, "text": "Can you tighten the cable at the frame?"],
                    ["id": "s3", "userId": "user03", "userName": "Robin Demo", "startMS": 12_000, "endMS": 15_000, "text": "Yes, I am on my way."],
                    ["id": "s4", "userId": "user01", "userName": "Alex Example", "startMS": 16_000, "endMS": 18_000, "text": "Thank you."],
                ]
                detail["recordingAttachments"] = [["id": "rec1", "filename": "robin.m4a", "uploadedByUserId": "user03"], ["id": "rec2", "filename": "alex.m4a", "uploadedByUserId": "user01"]]
            } else {
                detail["transcriptSegments"] = []
                detail["recordingAttachments"] = []
            }
            return ["GetChatCall": detail]
        default:
            return nil
        }
    }

    // MARK: server answers

    /// The rows a read of messages returns: one thread with its root first, or everything.
    static func messages(_ rows: [[String: Any]], variables: [String: Any]) -> [[String: Any]] {
        func threadRoot(_ row: [String: Any]) -> String? {
            guard let root = row["threadRootMessageId"] as? String, !root.isEmpty else { return nil }
            return root
        }
        if let root = variables["threadRootMessageId"] as? String, !root.isEmpty {
            return rows.filter { ($0["id"] as? String) == root || threadRoot($0) == root }
        }
        return rows
    }

    /// The thread a message sent as a reply goes in: the thread of the message it answers, or a new one hanging from it.
    static func threadRoot(replyingTo replyToMessageId: String?, in rows: [[String: Any]]) -> String? {
        guard let replyToMessageId, !replyToMessageId.isEmpty, let replied = rows.first(where: { ($0["id"] as? String) == replyToMessageId }) else { return nil }
        if let root = replied["threadRootMessageId"] as? String, !root.isEmpty { return root }
        return replyToMessageId
    }

    /// Counts a reply under the message its thread hangs from, as the server does.
    static func countReply(under rootMessageId: String, at createdAt: String, in rows: inout [[String: Any]]) {
        guard let index = rows.firstIndex(where: { ($0["id"] as? String) == rootMessageId }) else { return }
        rows[index]["threadReplyCount"] = ((rows[index]["threadReplyCount"] as? Int) ?? 0) + 1
        rows[index]["threadLastReplyAt"] = createdAt
    }
}
