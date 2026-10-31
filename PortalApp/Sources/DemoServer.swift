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
