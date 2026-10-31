import Foundation

/// TranscriptEntry is one thing shown in a conversation.
public enum TranscriptEntry: Equatable, Identifiable, Sendable {
    case user(id: String, text: String)
    case assistant(id: String, text: String, isStreaming: Bool)
    case tool(id: String, name: String, arguments: String, result: String?)
    case question(QuestionCard)
    case approval(ApprovalCard)
    case notice(id: String, text: String, isError: Bool)

    public var id: String {
        switch self {
        case .user(let id, _): "user:\(id)"
        case .assistant(let id, _, _): "assistant:\(id)"
        case .tool(let id, _, _, _): "tool:\(id)"
        case .question(let card): "question:\(card.id)"
        case .approval(let card): "approval:\(card.id)"
        case .notice(let id, _, _): "notice:\(id)"
        }
    }
}

/// Transcript is what a conversation screen shows: the persisted history,
/// then whatever the live feed has added since. It folds the events Portal
/// emits (text_delta, tool_call, tool_result, pending_question,
/// pending_approval, run_complete, run_error) into entries.
///
/// Live entries are tracked apart from persisted ones. A feed that reconnects
/// replays the running turn from its start, so the screen reloads the history
/// and calls `dropLiveEntries()`; the replay then fills the tail again without
/// showing anything twice.
public struct Transcript: Equatable, Sendable {
    public private(set) var entries: [TranscriptEntry] = []
    public private(set) var isRunning = false

    /// Whether a message the person sent has not come back from the server yet.
    public var hasPendingUser: Bool { !pendingUserTexts.isEmpty }

    private var persistedMessageIds: Set<String> = []
    private var persistedToolCallIds: Set<String> = []
    private var liveEntryIds: Set<String> = []
    private var pendingUserTexts: [String] = []
    private var noticeCount = 0

    public init() {}

    // MARK: history

    /// Replaces the persisted part with `messages`, and the cards that still
    /// wait for the person. Live entries stay unless the history now holds
    /// them; a sent message that has not come back yet stays at the end.
    public mutating func load(messages: [ConversationMessage], questions: [QuestionCard], approvals: [ApprovalCard], isRunning: Bool) {
        let live = entries.filter { liveEntryIds.contains($0.id) }
        persistedMessageIds = Set(messages.map(\.id))
        persistedToolCallIds = Set(messages.compactMap { $0.role == "tool" ? $0.toolCallId : nil })

        var rebuilt: [TranscriptEntry] = []
        var argumentsByCall: [String: String] = [:]
        var lastUserText: String?
        for message in messages {
            switch message.role {
            case "user":
                let text = Self.text(of: message.content)
                if !text.isEmpty {
                    rebuilt.append(.user(id: message.id, text: text))
                    lastUserText = text
                }
            case "assistant":
                for call in Self.toolCalls(in: message.toolCalls) { argumentsByCall[call.id] = call.arguments }
                let text = Self.visibleText(Self.text(of: message.content))
                if !text.isEmpty {
                    rebuilt.append(.assistant(id: message.id, text: text, isStreaming: false))
                } else if message.stopReason == "cancelled" {
                    rebuilt.append(.notice(id: message.id, text: "", isError: false))
                }
                for call in Self.toolCalls(in: message.toolCalls) where !persistedToolCallIds.contains(call.id) {
                    // A call with no result row yet is still running.
                    rebuilt.append(.tool(id: call.id, name: call.name, arguments: call.arguments, result: nil))
                }
            case "tool":
                let callId = message.toolCallIdOrId
                if message.stopReason == "cancelled" { continue }
                rebuilt.append(
                    .tool(
                        id: callId, name: message.toolName ?? "", arguments: argumentsByCall[callId] ?? "",
                        result: Self.text(of: message.content)))
            default:
                continue
            }
        }
        // A sent message the history now holds is no longer pending.
        if let lastUserText, let index = pendingUserTexts.lastIndex(of: lastUserText) {
            pendingUserTexts.removeSubrange(...index)
        }
        entries = rebuilt
        for text in pendingUserTexts { entries.append(.user(id: "pending:\(text)", text: text)) }

        for card in questions where !entries.contains(where: { $0.id == "question:\(card.id)" }) { entries.append(.question(card)) }
        for card in approvals where !entries.contains(where: { $0.id == "approval:\(card.id)" }) { entries.append(.approval(card)) }

        // Keep live entries the history does not hold.
        for entry in live where !entries.contains(where: { $0.id == entry.id }) {
            switch entry {
            case .assistant(let id, _, _) where persistedMessageIds.contains(id): continue
            case .tool(let id, _, _, _) where persistedToolCallIds.contains(id): continue
            default: entries.append(entry)
            }
        }
        liveEntryIds = Set(entries.map(\.id)).intersection(liveEntryIds)
        self.isRunning = isRunning
    }

    /// Forgets what the feed showed live, before the server replays the
    /// running turn on a new socket.
    public mutating func dropLiveEntries() {
        entries.removeAll { liveEntryIds.contains($0.id) }
        liveEntryIds = []
    }

    // MARK: sending

    /// Shows a message the person just sent, before the server has it.
    public mutating func appendPendingUser(_ text: String) {
        pendingUserTexts.append(text)
        entries.append(.user(id: "pending:\(text)", text: text))
        isRunning = true
    }

    /// Takes back a message that could not be sent.
    public mutating func removePendingUser(_ text: String) {
        if let index = pendingUserTexts.lastIndex(of: text) { pendingUserTexts.remove(at: index) }
        entries.removeAll { $0.id == "user:pending:\(text)" }
        isRunning = false
    }

    /// Removes a question card once it is answered.
    public mutating func removeQuestion(id: String) {
        entries.removeAll { $0.id == "question:\(id)" }
        liveEntryIds.remove("question:\(id)")
    }

    /// Removes an approval card once it is decided.
    public mutating func removeApproval(id: String) {
        entries.removeAll { $0.id == "approval:\(id)" }
        liveEntryIds.remove("approval:\(id)")
    }

    // MARK: events

    /// Folds one event from the feed in.
    public mutating func apply(_ event: ConversationEvent) {
        switch event.kind {
        case .textDelta:
            guard let delta = event.textDelta, !delta.messageId.isEmpty, !delta.text.isEmpty else { return }
            // A replay of a message the history holds shows nothing new.
            guard !persistedMessageIds.contains(delta.messageId) else { return }
            isRunning = true
            let entryId = "assistant:\(delta.messageId)"
            if let index = entries.firstIndex(where: { $0.id == entryId }), case .assistant(let id, let text, _) = entries[index] {
                entries[index] = .assistant(id: id, text: text + delta.text, isStreaming: true)
            } else {
                finishStreaming()
                entries.append(.assistant(id: delta.messageId, text: delta.text, isStreaming: true))
                liveEntryIds.insert(entryId)
            }
        case .toolCall:
            guard let call = event.toolCall, !call.toolCallId.isEmpty else { return }
            guard !persistedToolCallIds.contains(call.toolCallId) else { return }
            finishStreaming()
            isRunning = true
            let entryId = "tool:\(call.toolCallId)"
            guard !entries.contains(where: { $0.id == entryId }) else { return }
            entries.append(.tool(id: call.toolCallId, name: call.toolName, arguments: call.arguments ?? "", result: nil))
            liveEntryIds.insert(entryId)
        case .toolResult:
            guard let result = event.toolResult, let index = entries.firstIndex(where: { $0.id == "tool:\(result.toolCallId)" }),
                case .tool(let id, let name, let arguments, _) = entries[index]
            else { return }
            entries[index] = .tool(id: id, name: name, arguments: arguments, result: result.result ?? "")
        case .pendingQuestion:
            guard let question = event.pendingQuestion else { return }
            finishStreaming()
            let card = QuestionCard(id: question.questionId, question: question.question, choices: question.choices ?? [], allowOther: question.allowOther ?? true)
            guard !entries.contains(where: { $0.id == "question:\(card.id)" }) else { return }
            entries.append(.question(card))
            liveEntryIds.insert("question:\(card.id)")
        case .pendingApproval:
            guard let approval = event.pendingApproval else { return }
            finishStreaming()
            let card = ApprovalCard(
                id: approval.approvalId, toolCallId: approval.toolCallId ?? "", toolName: approval.toolName,
                policyReason: approval.policyReason ?? "", risk: approval.risk ?? "", arguments: approval.arguments ?? "")
            guard !entries.contains(where: { $0.id == "approval:\(card.id)" }) else { return }
            entries.append(.approval(card))
            liveEntryIds.insert("approval:\(card.id)")
        case .runComplete:
            finishStreaming()
            isRunning = false
        case .runError:
            finishStreaming()
            isRunning = false
            noticeCount += 1
            let text = event.runError?.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let id = "error:\(event.runId ?? "run"):\(noticeCount)"
            entries.append(.notice(id: id, text: text, isError: true))
            liveEntryIds.insert("notice:\(id)")
        case nil:
            return
        }
    }

    private mutating func finishStreaming() {
        for index in entries.indices {
            if case .assistant(let id, let text, true) = entries[index] {
                entries[index] = .assistant(id: id, text: text, isStreaming: false)
            }
        }
    }

    // MARK: reading persisted rows

    /// The text of a message's content: a string, or a list of typed parts.
    static func text(of content: JSONValue?) -> String {
        switch content {
        case .string(let text)?:
            // A string that is itself JSON text of a list of parts.
            if text.hasPrefix("["), let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), case .array = parsed {
                return Self.text(of: parsed)
            }
            return text
        case .array(let parts)?:
            return parts.compactMap { part in
                if case .string(let text) = part { return text }
                return part["text"]?.stringValue
            }.joined(separator: "\n")
        case .object(let object)?:
            return object["text"]?.stringValue ?? ""
        default:
            return ""
        }
    }

    /// The text a person should read: a suggestions marker the web app turns
    /// into chips is not shown, and neither is an unfinished one.
    public static func visibleText(_ text: String) -> String {
        guard let start = text.range(of: "<!--suggestions:") else { return text }
        return String(text[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct ToolCallRow {
        let id: String
        let name: String
        let arguments: String
    }

    /// The tool calls of an assistant row: a list of `{id, function: {name, arguments}}`.
    static func toolCalls(in value: JSONValue?) -> [ToolCallRow] {
        var candidate = value
        if case .string(let text)? = candidate { candidate = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
        guard case .array(let items)? = candidate else { return [] }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue, !id.isEmpty else { return nil }
            let function = item["function"]
            return ToolCallRow(id: id, name: function?["name"]?.stringValue ?? "", arguments: function?["arguments"]?.stringValue ?? "")
        }
    }
}

extension ConversationMessage {
    fileprivate var toolCallIdOrId: String { toolCallId ?? id }
}
