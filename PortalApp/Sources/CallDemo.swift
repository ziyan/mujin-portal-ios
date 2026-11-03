import Foundation
import PortalKit

/// CallDemo is the demo's voice messages and calls: invented people, a chat with voice messages and call lines, a call going in
/// it, and the call screens the screenshots show. The simulator has no camera, so video tiles are placeholders.
enum CallDemo {
    static let screens: Set<String> = [
        "chat-voice", "chat-voice-composer", "chat-voice-recording", "chat-call-banner", "call-voice", "call-video", "call-transcription",
        "call-minimized", "call-picker", "call-ring-more",
    ]

    static func owns(_ screen: String?) -> Bool { screen.map { screens.contains($0) } ?? false }

    /// The chat a screen opens.
    static func conversationId(for screen: String?) -> String? {
        switch screen {
        case "chat-voice", "chat-voice-composer", "chat-voice-recording", "chat-call-banner": "chatconv03"
        case "call-picker": "chatconv02"
        default: nil
        }
    }

    /// Whether the demo's voice messages have been played: Sam's second one has, the first has not.
    @MainActor
    static func markPlayed() {
        VoiceMessagePlayer.shared.markPlayedForDemo("v3")
    }

    // MARK: the call

    nonisolated static func call(for screen: String) -> ChatCall {
        let isVideo = screen == "call-video"
        var members = [
            ChatCallMember(userId: "user01", userName: "Alex Example", ringState: "none", isInCall: true, isMuted: false, isVideoOn: isVideo),
            ChatCallMember(userId: "user03", userName: "Robin Demo", ringState: "answered", isInCall: true, isMuted: false, isVideoOn: isVideo),
        ]
        if screen == "call-voice" || screen == "call-video" {
            members.append(ChatCallMember(userId: "user04", userName: "Jordan Placeholder", ringState: "answered", isInCall: true, isMuted: true, isVideoOn: false))
        }
        return ChatCall(
            id: "call01", chatId: "chat02", startedByUserId: "user03", startedByUserName: "Robin Demo", chatDisplayName: "Pick station team",
            startedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-754)), isTranscriptionOn: screen == "call-transcription",
            transcriptionTurnedOnByUserId: screen == "call-transcription" ? "user03" : nil, transcriptionTurnedOnByName: screen == "call-transcription" ? "Robin Demo" : nil,
            transcriptState: screen == "call-transcription" ? "recording" : "off", members: members)
    }

    @MainActor
    static func session(for screen: String) -> ChatCallSession {
        ChatCallSession.demo(
            call: call(for: screen), chatTitle: "Pick station team", isCameraOn: screen == "call-video", elapsed: 754,
            speaking: ["user03"])
    }

    // MARK: server answers

    static func respond(operation: String, variables: [String: Any]) -> [String: Any]? {
        guard owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) else { return nil }
        let screen = ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] ?? ""
        switch operation {
        case "IsChatCallAvailable":
            return ["IsChatCallAvailable": true]
        case "ListGoingChatCalls":
            guard screen == "chat-call-banner" else { return ["ListGoingChatCalls": []] }
            return ["ListGoingChatCalls": [goingCallJSON]]
        case "GetChatCall":
            return ["GetChatCall": goingCallJSON]
        default:
            return nil
        }
    }

    private static var goingCallJSON: [String: Any] {
        [
            "id": "call02", "chatId": "chat03", "chatDisplayName": "Sam Sample", "startedByUserId": "user02", "startedByUserName": "Sam Sample",
            "startedAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-95)), "endedAt": NSNull(), "isTranscriptionOn": false,
            "members": [
                ["userId": "user02", "userName": "Sam Sample", "ringState": "none", "isInCall": true, "isMuted": false, "isVideoOn": false],
                ["userId": "user01", "userName": "Alex Example", "ringState": "ringing", "isInCall": false, "isMuted": false, "isVideoOn": false],
            ],
        ]
    }

    // MARK: the chat

    static func chatRow(stamp: (TimeInterval) -> String) -> [String: Any] {
        [
            "id": "chatconv03", "chatId": "chat03", "conversationKind": "chat", "title": "Sam Sample", "summary": NSNull(), "lastMessageAt": stamp(120), "activeRunId": NSNull(),
            "archivedAt": NSNull(), "createdAt": stamp(9_000), "modifiedAt": stamp(120), "isTitleCustom": false, "agentId": NSNull(),
            "chat": [
                "id": "chat03", "organizationId": "organization01", "chatKind": "direct", "name": NSNull(), "displayName": "Sam Sample", "isMemoryFilingEnabled": false,
                "lastMessageAt": stamp(120), "readerConversationId": "chatconv03", "readerNotificationLevel": "all", "isReaderAdmin": false,
                "isReaderMember": true, "readerUnreadMessageCount": 0, "readerLastReadMessageId": NSNull(), "lastMessageExcerpt": "Voice message", "lastMessageAuthorName": "Sam Sample",
                "members": [
                    member("user01", "Alex Example", "organization01", "Example Logistics"),
                    member("user02", "Sam Sample", "organization00", "Support", staff: true),
                ],
            ] as [String: Any],
        ]
    }

    private static func member(_ id: String, _ name: String, _ organizationId: String, _ organizationName: String, staff: Bool = false) -> [String: Any] {
        [
            "id": "member-\(id)", "userId": id, "userName": name, "organizationId": organizationId, "organizationName": organizationName, "isMujinUser": staff,
            "isAdmin": false, "lastReadMessageId": NSNull(), "leftAt": NSNull(), "notificationLevel": "all",
        ]
    }

    static func messages(screen: String, stamp: (TimeInterval) -> String) -> [[String: Any]] {
        func row(_ id: String, _ author: String, _ name: String, _ secondsAgo: TimeInterval, extra: [String: Any]) -> [String: Any] {
            var base: [String: Any] = [
                "id": id, "role": "user", "content": "", "createdAt": stamp(secondsAgo), "isChatMessage": true, "authorUserId": author, "authorName": name,
                "authorOrganizationName": author == "user02" ? "Support" : "Example Logistics", "authorOrganizationId": author == "user02" ? "organization00" : "organization01",
            ]
            for (key, value) in extra { base[key] = value }
            return base
        }
        func voice(_ attachment: String, _ seconds: Int, _ text: String?, _ state: String, shape: Int) -> [String: Any] {
            let levels = (0..<48).map { index -> Int in
                let wave = abs(sin(Double(index + shape) * 0.45)) * 0.7 + abs(sin(Double(index * (shape + 2)) * 0.21)) * 0.3
                return max(18, min(255, Int(wave * 255)))
            }
            return ["voiceMessage": ["attachmentId": attachment, "durationMS": seconds * 1000, "waveformLevels": levels, "transcriptText": text ?? NSNull(), "transcriptState": state]]
        }
        if screen == "chat-call-banner" {
            return [
                row("k1", "user02", "Sam Sample", 5_400, extra: ["call": endedCall(id: "call-a", reason: "ended", seconds: 272, withTranscript: true)]),
                row("k2", "user01", "Alex Example", 3_600, extra: ["call": endedCall(id: "call-b", reason: "declined", seconds: 0, startedBy: "user01")]),
                row("k3", "user02", "Sam Sample", 1_800, extra: ["call": endedCall(id: "call-c", reason: "missed", seconds: 0)]),
            ]
        }
        return [
            row("v1", "user02", "Sam Sample", 1_200, extra: voice("voicedemo01", 12, "Hi Alex, the pick list for station three is ready. I put the scanner on the left shelf.", "done", shape: 1)),
            row("v2", "user01", "Alex Example", 1_100, extra: voice("voicedemo02", 7, nil, "waiting", shape: 4)),
            row("v3", "user02", "Sam Sample", 900, extra: voice("voicedemo03", 31, "The gripper dropped two boxes this morning, both on the second pass. I will send the log after lunch.", "done", shape: 2)),
            row("v4", "user02", "Sam Sample", 600, extra: voice("voicewebm", 5, "Running late, start without me.", "done", shape: 6)),
            row("v5", "user02", "Sam Sample", 300, extra: voice("voicedemo05", 9, nil, "failed", shape: 3)),
        ]
    }

    private static func endedCall(id: String, reason: String, seconds: Int, startedBy: String = "user02", withTranscript: Bool = false) -> [String: Any] {
        var call: [String: Any] = [
            "id": id, "chatId": "chat03", "chatDisplayName": "Sam Sample", "startedByUserId": startedBy, "startedByUserName": startedBy == "user02" ? "Sam Sample" : "Alex Example",
            "startedAt": "2026-03-01T10:00:00Z", "endedAt": "2026-03-01T10:04:32Z", "endReason": reason, "durationMS": seconds * 1000, "isTranscriptionOn": withTranscript,
            "transcriptState": withTranscript ? "done" : "off", "members": [],
        ]
        if withTranscript {
            call["transcriptSegments"] = [
                ["id": "s1", "userId": "user02", "userName": "Sam Sample", "text": "Can you see the error on the station three screen?", "startMS": 1_000, "endMS": 4_000],
                ["id": "s2", "userId": "user01", "userName": "Alex Example", "text": "Yes, it says the scanner lost its connection.", "startMS": 5_000, "endMS": 8_000],
            ]
        }
        return call
    }
}
