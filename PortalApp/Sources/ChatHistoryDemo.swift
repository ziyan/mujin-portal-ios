import Foundation

/// ChatHistoryDemo gives the demo's chat with Sam Sample a long history, a page at a time, so scrolling up through it can be
/// watched and tested. Every seventh message holds a picture and every ninth a link with a card. The screens:
///
/// - `chat-history`: the history, whose earlier pages take a moment to arrive, as they do across an ocean.
/// - `chat-history-live`: the same, while Sam types and sends a message every few seconds.
enum ChatHistoryDemo {
    static let conversationId = "chatconv01"
    static let historyCount = 120
    /// How long an earlier page takes to arrive, so a test can look at the list before and after it goes in.
    static let earlierPageDelaySeconds: Double = 1.5

    static func owns(_ screen: String?) -> Bool { screen == "chat-history" || screen == "chat-history-live" }
    static func isLive(_ screen: String?) -> Bool { screen == "chat-history-live" }
    static func conversationId(for screen: String?) -> String? { owns(screen) ? conversationId : nil }

    /// The history, oldest first, all of it before the chat's own messages.
    static func messages(stamp: (TimeInterval) -> String) -> [[String: Any]] {
        (1...historyCount).map { number in
            let isSam = number % 3 != 0
            return row(id: messageId(number), isSam: isSam, text: text(of: number), createdAt: stamp(3_000 + Double(historyCount + 1 - number) * 90))
        }
    }

    static func messageId(_ number: Int) -> String { String(format: "h%03d", number) }

    /// The words of a message start with its number, which the tests find it by.
    static func text(of number: Int) -> String {
        if number % 7 == 0 { return "History message \(number), a photo from the line: ![line-\(number).jpg](/api/v1/attachment/imagedemo0\(number % 2 + 1))" }
        if number % 9 == 0 { return "History message \(number), the notes are at https://example.test/docs/history-\(number)" }
        if number % 4 == 0 {
            return "History message \(number). The pallet count at the dock matched the plan, and the second shift picked up where the first left off."
        }
        return "History message \(number). All quiet at the dock."
    }

    /// The card under a history message that holds a link.
    static func preview(messageId: String) -> [String: Any]? {
        guard messageId.hasPrefix("h"), let number = Int(messageId.dropFirst()), number % 9 == 0, number % 7 != 0 else { return nil }
        return [
            "messageId": messageId, "isPending": false,
            "linkPreviews": [[
                "urlHash": "history\(number)", "linkKind": "external", "url": "https://example.test/docs/history-\(number)",
                "title": "Dock notes \(number)", "description": "What the shift saw at the dock, and what it changed.", "siteName": "example.test",
            ]],
        ]
    }

    /// The latest messages before the one given, as many as asked for, as the server pages them.
    static func page(_ rows: [[String: Any]], variables: [String: Any]) -> [[String: Any]] {
        var shown = rows
        if let before = variables["beforeMessageId"] as? String, !before.isEmpty, let index = shown.firstIndex(where: { ($0["id"] as? String) == before }) {
            shown = Array(shown[..<index])
        }
        if let count = variables["latestMessageCount"] as? Int, count > 0 { shown = Array(shown.suffix(count)) }
        return shown
    }

    private static let isLivePlaying = DemoLocked(false)

    /// Sam types, then sends, every few seconds, once the chat's feed is open.
    static func playLive(state: DemoState) {
        let isFirst = isLivePlaying.withValue { isPlaying -> Bool in
            defer { isPlaying = true }
            return !isPlaying
        }
        guard isFirst else { return }
        Task {
            for number in 1...20 {
                try? await Task.sleep(for: .seconds(2))
                state.broadcast(
                    conversationId: conversationId,
                    event: ["type": "chat_typing", "chat": ["type": "chat_typing", "chatId": "chat01", "actorUserId": "user02", "actorUserName": "Sam Sample"]])
                try? await Task.sleep(for: .seconds(2))
                let text = number % 2 == 0
                    ? "Live message \(number), a photo: ![live-\(number).jpg](/api/v1/attachment/imagedemo01)" : "Live message \(number) from the dock."
                let message = row(id: "live\(number)", isSam: true, text: text, createdAt: ISO8601DateFormatter().string(from: Date()))
                state.withData { $0.messages[conversationId, default: []].append(message) }
                state.broadcast(conversationId: conversationId, event: ["type": "chat_said", "chat": ["type": "chat_said", "chatId": "chat01", "message": message]])
            }
        }
    }

    private static func row(id: String, isSam: Bool, text: String, createdAt: String) -> [String: Any] {
        [
            "id": id, "role": "user", "content": text, "createdAt": createdAt, "isChatMessage": true,
            "authorUserId": isSam ? "user02" : "user01", "authorName": isSam ? "Sam Sample" : "Alex Example",
            "authorOrganizationName": isSam ? "Support" : "Example Logistics", "authorOrganizationId": isSam ? "organization00" : "organization01",
        ]
    }
}

/// TranscriptStreamDemo gives the assistant a long conversation whose next answer is written word by word a few seconds after the
/// screen opens, so reading further up while it is written can be watched and tested. Its screen is `conversation-stream`.
enum TranscriptStreamDemo {
    static let conversationId = "conversation-stream"
    static let turnCount = 25

    static func owns(_ screen: String?) -> Bool { screen == "conversation-stream" }

    static func conversationRow(stamp: (TimeInterval) -> String) -> [String: Any] {
        [
            "id": conversationId, "agentId": "agent01", "title": "Long dock review", "summary": "A long look at the dock doors.",
            "lastMessageAt": stamp(60), "activeRunId": NSNull(), "archivedAt": NSNull(), "createdAt": stamp(90_000), "modifiedAt": stamp(60),
            "isMain": false,
        ]
    }

    /// Questions and answers, oldest first, each starting with its number, which the tests find it by.
    static func messages(stamp: (TimeInterval) -> String) -> [[String: Any]] {
        (1...turnCount).flatMap { number -> [[String: Any]] in
            let secondsAgo = Double(turnCount + 1 - number) * 120
            return [
                ["id": "sq\(number)", "role": "user", "content": "Question \(number). How did dock door \(number % 4 + 1) do this shift?", "createdAt": stamp(secondsAgo + 60)],
                [
                    "id": "sa\(number)", "role": "assistant",
                    "content": "Answer \(number). Door \(number % 4 + 1) opened on time all shift, with one slow close just before the break that the sensor log shows as a late signal.",
                    "createdAt": stamp(secondsAgo),
                ],
            ]
        }
    }

    /// The answer written while the screen is open: long enough to go on well past the screen's end.
    static let streamedAnswer = (1...300).map { "streamed word \($0)" }.joined(separator: " ")

    private static let isPlaying = DemoLocked(false)

    /// Writes the next answer a few seconds after the conversation's feed opens.
    static func play(state: DemoState) {
        let isFirst = isPlaying.withValue { playing -> Bool in
            defer { playing = true }
            return !playing
        }
        guard isFirst else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            state.playAnswer(conversationId: conversationId, text: streamedAnswer)
        }
    }
}
