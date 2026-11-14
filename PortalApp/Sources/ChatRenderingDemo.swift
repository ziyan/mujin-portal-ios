import Foundation
import SwiftUI

/// ChatRenderingDemo seeds the demo server with the chat rendering fixture (Fixtures/chat-rendering), the set of messages Portal's
/// web app and phone apps all draw, so each can be pictured and checked. Its screens:
///
/// - `rendering-chat`: the group chat "Rendering check", read by the customer, with every chat message of the fixture but the internal note.
/// - `rendering-chat-staff`: the same chat read by Mujin staff, with the internal note.
/// - `rendering-assistant`: a conversation with the assistant holding every assistant message, its tool lines and its artifacts.
///
/// Every message is seeded in file order. Thread replies go in their threads, and the reactions, the edit and the delete are applied.
enum ChatRenderingDemo {
    static let chatConversationId = "chatconv-rendering"
    static let chatId = "chat-rendering"
    static let assistantConversationId = "conversation-rendering"
    /// The prefix of every message id, followed by the message's key.
    static let messagePrefix = "render-"
    /// The prefix of an attachment id the fixture's files are served under.
    static let assetPrefix = "render-asset-"

    static func isScreen(_ screen: String?) -> Bool { screen?.hasPrefix("rendering-") == true }
    static var isStaffViewer: Bool { DemoOptions.screen == "rendering-chat-staff" }

    static func conversationId(for screen: String?) -> String? {
        switch screen {
        case "rendering-chat", "rendering-chat-staff": chatConversationId
        case "rendering-assistant": assistantConversationId
        case "rendering-formulas": formulasConversationId
        default: nil
        }
    }

    /// A long conversation full of formulas and diagrams, for measuring how a chat of them scrolls and how much memory it holds.
    static let formulasConversationId = "conversation-formulas"
    static let formulaMessageCount = 120

    static func formulaMessages(stamp: (TimeInterval) -> String) -> [[String: Any]] {
        (1...formulaMessageCount).map { number -> [String: Any] in
            var text = "Formula message \(number): the rate is $r_{\(number)} = \\frac{n}{t}$ picks an hour."
            if number % 5 == 0 { text += "\n\n$$\\sigma_{\(number)} = \\sqrt{\\frac{1}{N}\\sum_{i=1}^{N}(r_i - \\bar{r})^2}$$" }
            if number % 10 == 0 { text += "\n\n```mermaid\nflowchart LR\n  Pick\(number)[Pick] --> Pack\(number)[Pack] --> Ship\(number)[Ship]\n```" }
            return ["id": "formula\(number)", "role": "assistant", "content": text, "createdAt": stamp(Double(formulaMessageCount + 1 - number) * 60)]
        }
    }

    // MARK: the fixture

    private static let folder = Bundle.main.url(forResource: "chat-rendering", withExtension: nil)

    nonisolated(unsafe) private static let document: [String: Any] = {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent("messages.json")),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }()

    private static var messages: [[String: Any]] { document["messages"] as? [[String: Any]] ?? [] }
    private static var linkPreviews: [[String: Any]] { document["linkPreviews"] as? [[String: Any]] ?? [] }

    /// The people of the chat. The customer is the person reading; the colleague only belongs to the chat.
    private struct Person {
        let userId: String
        let name: String
        let organizationId: String
        let organizationName: String
        let isMujinUser: Bool
    }

    private static let customer = Person(
        userId: "user01", name: "Alex Example", organizationId: "organization01", organizationName: "Example Logistics", isMujinUser: false)
    private static let colleague = Person(
        userId: "user09", name: "Quinn Fixture", organizationId: "organization01", organizationName: "Example Logistics", isMujinUser: false)
    private static let staff = Person(userId: "user08", name: "Riley Stub", organizationId: "organization00", organizationName: "Support", isMujinUser: true)

    private static func person(_ author: String?) -> Person { author == "staff" ? staff : customer }

    /// What the fixture's placeholders stand for in the demo.
    static let placeholders: [String: String] = [
        "ticketSequence": "7", "siteId": "site01", "siteName": "Harbor Works", "cellId": "cell01", "cellName": "Packing Cell 2",
        "controllerId": "controller-harbor-01", "pageId": "page01", "pageTitle": "Shift handover notes",
        "portalOrigin": DemoServer.server.description, "staffName": staff.name, "customerName": customer.name,
    ]

    static func filled(_ text: String) -> String {
        placeholders.reduce(text) { result, entry in result.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value) }
    }

    private static func messageId(_ key: String) -> String { messagePrefix + key }

    /// The attachment id a fixture file is served under: its name with what an id may not hold made a hyphen.
    static func attachmentId(forFile name: String) -> String {
        assetPrefix + String(name.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// A file of the fixture, by the attachment id it is served under.
    static func asset(attachmentId: String) -> (data: Data, contentType: String)? {
        guard attachmentId.hasPrefix(assetPrefix), let folder else { return nil }
        let assets = folder.appendingPathComponent("assets")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: assets.path)) ?? []
        guard let name = names.first(where: { Self.attachmentId(forFile: $0) == attachmentId }),
            let data = try? Data(contentsOf: assets.appendingPathComponent(name))
        else { return nil }
        return (data, contentType(of: name))
    }

    private static func contentType(of name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "mp4": "video/mp4"
        case "pdf": "application/pdf"
        case "zip": "application/zip"
        case "csv": "text/csv"
        case "md": "text/markdown"
        case "html": "text/html"
        case "webm": "audio/webm"
        default: "text/plain"
        }
    }

    /// The text of a markdown artifact or the page of an html one, by its artifact id.
    static func artifactText(artifactId: String) -> String? {
        guard let entry = messages.first(where: { artifactIdOf($0) == artifactId }), let artifact = entry["artifact"] as? [String: Any],
            let file = artifact["file"] as? String, let folder,
            let data = try? Data(contentsOf: folder.appendingPathComponent("assets").appendingPathComponent(file))
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func artifactIdOf(_ entry: [String: Any]) -> String? {
        guard entry["artifact"] != nil, let key = entry["key"] as? String else { return nil }
        return messageId(key) + "~artifact"
    }

    // MARK: rows

    /// Seeds the chat, the assistant conversation and their messages.
    static func seed(_ data: inout DemoState.Data, stamp: (TimeInterval) -> String) {
        let chatEntries = messages.filter { $0["surface"] as? String == "chat" && (isStaffViewer || $0["isInternal"] as? Bool != true) }
        let assistantEntries = messages.filter { $0["surface"] as? String == "assistant" }
        data.chats.append(chatRow(stamp: stamp, lastAt: 600))
        data.messages[chatConversationId] = chatRows(chatEntries, stamp: stamp)
        data.conversations.append([
            "id": assistantConversationId, "agentId": "agent01", "title": "Rendering check", "summary": "Every way an answer draws.",
            "lastMessageAt": stamp(600), "activeRunId": NSNull(), "archivedAt": NSNull(), "createdAt": stamp(90_000), "modifiedAt": stamp(600),
            "isMain": false,
        ])
        data.messages[assistantConversationId] = assistantRows(assistantEntries, stamp: stamp)
        data.conversations.append([
            "id": formulasConversationId, "agentId": "agent01", "title": "Formulas", "summary": NSNull(), "lastMessageAt": stamp(60),
            "activeRunId": NSNull(), "archivedAt": NSNull(), "createdAt": stamp(90_000), "modifiedAt": stamp(60), "isMain": false,
        ])
        data.messages[formulasConversationId] = formulaMessages(stamp: stamp)
    }

    private static func member(_ person: Person, isAdmin: Bool) -> [String: Any] {
        [
            "id": "member-\(person.userId)", "userId": person.userId, "userName": person.name, "organizationId": person.organizationId,
            "organizationName": person.organizationName, "isMujinUser": person.isMujinUser, "isAdmin": isAdmin, "lastReadMessageId": NSNull(),
            "leftAt": NSNull(), "notificationLevel": "all",
        ]
    }

    private static func chatRow(stamp: (TimeInterval) -> String, lastAt: TimeInterval) -> [String: Any] {
        [
            "id": chatConversationId, "chatId": chatId, "conversationKind": "chat", "title": "Rendering check", "summary": NSNull(),
            "lastMessageAt": stamp(lastAt), "activeRunId": NSNull(), "archivedAt": NSNull(), "createdAt": stamp(90_000), "modifiedAt": stamp(lastAt),
            "isTitleCustom": false, "agentId": NSNull(),
            "chat": [
                "id": chatId, "organizationId": "organization01", "chatKind": "group", "name": "Rendering check", "displayName": "Rendering check",
                "isMemoryFilingEnabled": false, "lastMessageAt": stamp(lastAt), "readerConversationId": chatConversationId,
                "readerNotificationLevel": "all", "isReaderAdmin": true, "isReaderMember": true, "readerUnreadMessageCount": 0,
                "readerLastReadMessageId": NSNull(), "lastMessageExcerpt": "Line is back up.", "lastMessageAuthorName": customer.name,
                "canPostInternal": isStaffViewer,
                "members": [member(customer, isAdmin: true), member(colleague, isAdmin: false), member(staff, isAdmin: false)],
            ] as [String: Any],
        ]
    }

    /// The text a message is drawn from: its words, then its files in order.
    private static func body(of entry: [String: Any]) -> String {
        let text = filled((entry["editedText"] as? String) ?? (entry["text"] as? String) ?? "")
        let files = (entry["attachments"] as? [String] ?? []).map { name -> String in
            let isPicture = ["png", "jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased())
            return "\(isPicture ? "!" : "")[\(name)](/api/v1/attachment/\(attachmentId(forFile: name)))"
        }
        return ([text] + files).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func chatRows(_ entries: [[String: Any]], stamp: (TimeInterval) -> String) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        // Two minutes apart, the last one ten minutes ago, with a thread's replies a few seconds after their root.
        var secondsAgo = 600 + Double(entries.count) * 120
        let byKey = Dictionary(entries.compactMap { entry in (entry["key"] as? String).map { ($0, entry) } }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            guard let key = entry["key"] as? String else { continue }
            secondsAgo -= 120
            let author = person(entry["author"] as? String)
            let id = messageId(key)
            var row = chatMessage(id: id, author: author, text: entry["isDeleted"] as? Bool == true ? "" : body(of: entry), createdAt: stamp(secondsAgo))
            if entry["editedText"] != nil { row["editedAt"] = stamp(secondsAgo - 30) }
            if entry["isDeleted"] as? Bool == true { row["deletedAt"] = stamp(secondsAgo - 30) }
            if entry["isInternal"] as? Bool == true { row["isInternal"] = true }
            if let replyTo = entry["replyTo"] as? String, let replied = byKey[replyTo] {
                row["replyToMessageId"] = messageId(replyTo)
                row["replyToExcerpt"] = String(filled(replied["text"] as? String ?? "").prefix(80))
                row["replyToAuthorName"] = person(replied["author"] as? String).name
            }
            if let reactions = entry["reactions"] as? [[String: Any]] {
                row["reactions"] = reactions.enumerated().map { index, reaction -> [String: Any] in
                    [
                        "id": "\(id)~reaction\(index)", "messageId": id, "reactorKind": "user",
                        "reactorUserId": person(reaction["author"] as? String).userId, "emoji": reaction["emoji"] as? String ?? "",
                        "isAcknowledgment": false,
                    ]
                }
            }
            if let voice = entry["voiceMessage"] as? [String: Any] {
                let levels = (voice["waveformLevels"] as? [Double] ?? []).map { Int(($0 * 255).rounded()) }
                row["content"] = ""
                row["voiceMessage"] = [
                    "attachmentId": attachmentId(forFile: voice["file"] as? String ?? ""), "durationMS": voice["durationMS"] as? Int ?? 0,
                    "waveformLevels": levels, "transcriptText": NSNull(), "transcriptState": "off",
                ]
            }
            if let references = references(in: row["content"] as? String ?? "") { row["references"] = references }
            let replies = entry["threadReplies"] as? [[String: Any]] ?? []
            if !replies.isEmpty {
                row["threadReplyCount"] = replies.count
                row["threadLastReplyAt"] = stamp(secondsAgo - Double(replies.count) * 10)
            }
            rows.append(row)
            for (index, reply) in replies.enumerated() {
                var replyRow = chatMessage(
                    id: "\(id)~reply\(index + 1)", author: person(reply["author"] as? String), text: filled(reply["text"] as? String ?? ""),
                    createdAt: stamp(secondsAgo - Double(index + 1) * 10))
                replyRow["threadRootMessageId"] = id
                rows.append(replyRow)
            }
        }
        return rows
    }

    private static func chatMessage(id: String, author: Person, text: String, createdAt: String) -> [String: Any] {
        [
            "id": id, "role": "user", "content": text, "createdAt": createdAt, "isChatMessage": true, "authorUserId": author.userId,
            "authorName": author.name, "authorOrganizationId": author.organizationId, "authorOrganizationName": author.organizationName,
            "isAuthorMujinUser": author.isMujinUser,
        ]
    }

    /// The tickets, controllers and sites a message names, as the server resolves them for the reader.
    private static func references(in text: String) -> [[String: Any]]? {
        var found: [[String: Any]] = []
        let ticket = "#" + (placeholders["ticketSequence"] ?? "")
        if text.contains(ticket + " ") || text.hasSuffix(ticket) || text.contains(ticket + ",") {
            found.append([
                "referenceKind": "ticket", "writtenText": ticket, "isAccessible": true, "targetId": "ticket-rendering", "path": "/ticket/7",
                "label": "Conveyor jam at packing", "ticketSequence": 7, "ticketTitle": "Conveyor jam at packing", "ticketStatus": "open",
            ])
        }
        // A Portal address pasted on its own is a reference too, written as the whole address.
        let pastedTicket = (placeholders["portalOrigin"] ?? "") + "/ticket/" + (placeholders["ticketSequence"] ?? "")
        if text.contains(pastedTicket) {
            found.append([
                "referenceKind": "ticket", "writtenText": pastedTicket, "isAccessible": true, "targetId": "ticket-rendering", "path": "/ticket/7",
                "label": "Conveyor jam at packing", "ticketSequence": 7, "ticketTitle": "Conveyor jam at packing", "ticketStatus": "open",
            ])
        }
        let controller = placeholders["controllerId"] ?? ""
        if text.contains("(/controller/\(controller))") {
            found.append([
                "referenceKind": "controller", "writtenText": "[\(controller)](/controller/\(controller))", "isAccessible": true,
                "targetId": controller, "path": "/controller/\(controller)", "label": controller, "controllerName": controller,
                "isControllerConnected": true,
            ])
        }
        let siteId = placeholders["siteId"] ?? ""
        if text.contains("(/site/\(siteId))") {
            let name = placeholders["siteName"] ?? ""
            found.append([
                "referenceKind": "site", "writtenText": "[\(name)](/site/\(siteId))", "isAccessible": true, "targetId": siteId,
                "path": "/site/\(siteId)", "label": name, "siteName": name,
            ])
        }
        return found.isEmpty ? nil : found
    }

    private static func assistantRows(_ entries: [[String: Any]], stamp: (TimeInterval) -> String) -> [[String: Any]] {
        var rows: [[String: Any]] = [
            ["id": messageId("question"), "role": "user", "content": "Show me every way you can write an answer.", "createdAt": stamp(600 + Double(entries.count + 1) * 120)]
        ]
        var secondsAgo = 600 + Double(entries.count) * 120
        for entry in entries {
            guard let key = entry["key"] as? String else { continue }
            secondsAgo -= 120
            let id = messageId(key)
            var calls: [[String: Any]] = []
            var results: [[String: Any]] = []
            for (index, call) in (entry["toolCalls"] as? [[String: Any]] ?? []).enumerated() {
                let callId = "\(id)~call\(index + 1)"
                let name = call["name"] as? String ?? "tool"
                calls.append(["id": callId, "function": ["name": name, "arguments": json(call["arguments"] ?? [String: Any]())]])
                results.append(toolResult(id: "\(id)~result\(index + 1)", callId: callId, name: name, content: json(call["result"] ?? [String: Any]()), createdAt: stamp(secondsAgo - 5)))
            }
            if let artifact = entry["artifact"] as? [String: Any], let artifactId = artifactIdOf(entry) {
                let callId = "\(id)~call-artifact"
                let title = artifact["title"] as? String ?? ""
                let kind = artifact["kind"] as? String ?? "markdown"
                calls.append(["id": callId, "function": ["name": "artifact", "arguments": json(["title": title])]])
                let size = artifactText(artifactId: artifactId)?.utf8.count ?? 0
                results.append(toolResult(
                    id: "\(id)~result-artifact", callId: callId, name: "artifact",
                    content: json([
                        "artifactId": artifactId, "attachmentId": "\(artifactId)-file", "title": title, "artifactKind": kind, "sizeBytes": size,
                        "url": "/api/v1/artifact/\(artifactId)",
                    ]),
                    createdAt: stamp(secondsAgo - 6)))
            }
            var row: [String: Any] = ["id": id, "role": "assistant", "content": body(of: entry), "createdAt": stamp(secondsAgo)]
            if !calls.isEmpty { row["toolCalls"] = calls }
            rows.append(row)
            rows += results
        }
        return rows
    }

    private static func toolResult(id: String, callId: String, name: String, content: String, createdAt: String) -> [String: Any] {
        ["id": id, "role": "tool", "toolCallId": callId, "toolName": name, "content": content, "metadata": ["durationMS": 400], "createdAt": createdAt]
    }

    private static func json(_ value: Any) -> String {
        let filledValue = fill(value)
        guard JSONSerialization.isValidJSONObject(filledValue), let data = try? JSONSerialization.data(withJSONObject: filledValue, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func fill(_ value: Any) -> Any {
        switch value {
        case let text as String: filled(text)
        case let list as [Any]: list.map(fill)
        case let object as [String: Any]: object.mapValues(fill)
        default: value
        }
    }

    // MARK: link cards

    /// The cards of the fixture's messages: the cached outside pages it names, and Portal's own cards for its pasted links, all of
    /// them, as the server may return; the app shows at most three.
    static func linkPreviews(messageIds: [String]) -> [[String: Any]] {
        let texts = Dictionary(uniqueKeysWithValues: messages.compactMap { entry -> (String, String)? in
            guard let key = entry["key"] as? String else { return nil }
            return (messageId(key), filled((entry["editedText"] as? String) ?? (entry["text"] as? String) ?? ""))
        })
        return messageIds.compactMap { id -> [String: Any]? in
            guard let text = texts[id] else { return nil }
            var cards: [[String: Any]] = []
            for (index, preview) in linkPreviews.enumerated() {
                guard let url = preview["url"] as? String, text.contains(url), preview["status"] as? String == "ok" else { continue }
                var card: [String: Any] = [
                    "urlHash": "render-card-\(index)", "linkKind": "external", "url": url, "title": preview["title"] ?? NSNull(),
                    "description": preview["description"] ?? NSNull(), "siteName": preview["siteName"] ?? NSNull(),
                ]
                if let image = preview["image"] as? String { card["imageUrl"] = "/api/v1/attachment/\(attachmentId(forFile: image))" }
                cards.append(card)
            }
            cards += portalCards(in: text)
            return cards.isEmpty ? nil : ["messageId": id, "isPending": false, "linkPreviews": cards]
        }
    }

    private static func portalCards(in text: String) -> [[String: Any]] {
        let origin = placeholders["portalOrigin"] ?? ""
        let site = placeholders["siteId"] ?? ""
        let candidates: [(path: String, kind: String, title: String, description: String, status: String?)] = [
            ("/ticket/\(placeholders["ticketSequence"] ?? "")", "ticket", "Conveyor jam at packing", "Ticket #\(placeholders["ticketSequence"] ?? "")", "open"),
            ("/controller/\(placeholders["controllerId"] ?? "")", "controller", "Chat rendering fixture controller", "Controller", nil),
            ("/site/\(site)/cell/\(placeholders["cellId"] ?? "")", "cell", placeholders["cellName"] ?? "", "Cell at \(placeholders["siteName"] ?? "")", nil),
            ("/site/\(site)/page/\(placeholders["pageId"] ?? "")", "page", placeholders["pageTitle"] ?? "", "Page", nil),
            ("/site/\(site)", "site", placeholders["siteName"] ?? "", "Site", nil),
        ]
        var cards: [[String: Any]] = []
        var remaining = text
        for candidate in candidates {
            let url = origin + candidate.path
            // A longer address is matched first, so a cell's or page's address is not also read as its site's.
            guard let range = remaining.range(of: url), !(remaining[range.upperBound...].first.map { $0 == "/" } ?? false) else { continue }
            remaining.replaceSubrange(range, with: "")
            cards.append([
                "urlHash": "render-portal-\(candidate.kind)", "linkKind": candidate.kind, "url": url, "title": candidate.title,
                "description": candidate.description, "statusText": candidate.status ?? NSNull(), "path": candidate.path,
            ])
        }
        return cards
    }
}

/// RenderedMessageIdentifier names a drawn message for the rendering test, on the rendering screens only: elsewhere a message is
/// left as it is.
struct RenderedMessageIdentifier: ViewModifier {
    let messageId: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if ChatRenderingDemo.isScreen(DemoOptions.screen), messageId.hasPrefix(ChatRenderingDemo.messagePrefix) {
            content.accessibilityElement(children: .contain).accessibilityIdentifier("rendered-\(messageId)")
        } else {
            content
        }
    }
}
