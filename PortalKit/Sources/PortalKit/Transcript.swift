import Foundation

/// Viewing is the screen the person was looking at when they wrote: the
/// resource an "Ask about this" action names. `kind` is one of site,
/// controller, virtual_controller, ticket, incident, cell or agent_run.
public struct Viewing: Equatable, Sendable {
    public let kind: String
    public let id: String
    public let label: String?

    public init(kind: String, id: String, label: String? = nil) {
        self.kind = kind
        self.id = id
        self.label = label
    }
}

/// ToolActivity is one tool call of the assistant and what came of it.
public struct ToolActivity: Equatable, Identifiable, Sendable {
    /// The tool the quick model calls to hand the rest of the turn to the main model.
    public static let thinkHarderToolName = "think_harder"

    public let id: String
    public var name: String
    public var arguments: String
    public var result: String?
    /// One short line the tool wrote, safe to show with tool details off.
    public var note: String?
    public var durationMS: Int?

    public init(id: String, name: String, arguments: String = "", result: String? = nil, note: String? = nil, durationMS: Int? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.note = note
        self.durationMS = durationMS
    }

    public var isRunning: Bool { result == nil }

    /// How long the call took: "850 ms", "2.4 s", "1 min 5 s". Nil when unknown.
    public var durationText: String? {
        guard let durationMS, durationMS > 0 else { return nil }
        if durationMS < 1_000 { return "\(durationMS) ms" }
        if durationMS < 60_000 { return String(format: "%.1f s", Double(durationMS) / 1_000) }
        return "\(durationMS / 60_000) min \(Int((Double(durationMS % 60_000) / 1_000).rounded())) s"
    }

    /// The tool's name as words: `list_controllers` is "list controllers".
    public var displayName: String { name.replacingOccurrences(of: "_", with: " ") }

    public var isThinkingHarder: Bool { name == Self.thinkHarderToolName }
    public var producedItems: [ProducedItem] { ProducedItem.items(toolName: name, result: result) }

    /// The few words the quick model gave for handing over, when it gave any.
    public var thinkHarderReason: String? {
        guard isThinkingHarder, let data = arguments.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        let reason = value["switchReason"]?.stringValue ?? value["reason"]?.stringValue ?? ""
        return reason.isEmpty ? nil : reason
    }
}

/// TurnEndKind says why a turn ended without an answer.
public enum TurnEndKind: Equatable, Sendable {
    case failed
    case roundLimit
    case repeatedFailure

    init?(stopReason: String?) {
        switch stopReason {
        case "error": self = .failed
        case "round_limit": self = .roundLimit
        case "repeated_failure": self = .repeatedFailure
        default: return nil
        }
    }
}

/// TranscriptNote is a line about the assistant's own turns, drawn small
/// instead of as a bubble.
public enum TranscriptNote: Equatable, Sendable {
    /// The assistant carried on after a restart.
    case restart
    /// The scheduler started this turn for a job; `message` is the job's own text.
    case scheduled(jobName: String, message: String)
    /// Background work ended; `report` is what it handed back.
    case backgroundFinished(title: String, report: String)
    /// Finished work could not wake the assistant. The model never sees this.
    case backgroundNotice(text: String)
    /// A long conversation was compacted into `summary`.
    case compaction(summary: String)
}

/// TranscriptEntry is one thing shown in a conversation.
public enum TranscriptEntry: Equatable, Identifiable, Sendable {
    case user(id: String, text: String, viewing: Viewing?)
    case assistant(id: String, text: String, isStreaming: Bool)
    case tool(ToolActivity)
    /// A stretch of consecutive tool calls, folded into one "What it did" row.
    /// Only `Transcript.displayEntries` makes these.
    case toolGroup(id: String, tools: [ToolActivity])
    /// A page, drawing or file a tool made, shown whatever the tool display is.
    case produced(ProducedItem)
    case question(QuestionCard)
    case approval(ApprovalCard)
    case notice(id: String, text: String, isError: Bool)
    case turnEnd(id: String, kind: TurnEndKind, text: String)
    case note(id: String, TranscriptNote)

    public var id: String {
        switch self {
        case .user(let id, _, _): "user:\(id)"
        case .assistant(let id, _, _): "assistant:\(id)"
        case .tool(let activity): "tool:\(activity.id)"
        case .toolGroup(let id, _): "toolgroup:\(id)"
        case .produced(let item): "produced:\(item.id)"
        case .question(let card): "question:\(card.id)"
        case .approval(let card): "approval:\(card.id)"
        case .notice(let id, _, _): "notice:\(id)"
        case .turnEnd(let id, _, _): "turnend:\(id)"
        case .note(let id, _): "note:\(id)"
        }
    }
}

/// Transcript is what a conversation screen shows: the persisted history,
/// then whatever the live feed has added since. It folds the events Portal
/// emits (text_delta, tool_call, tool_result, pending_question,
/// pending_approval, run_complete, run_error, round_retry, model_switch and
/// reacted) into entries.
///
/// Live entries are tracked apart from persisted ones. A feed that reconnects
/// replays the running turn from its start, so the screen reloads the history
/// and calls `dropLiveEntries()`; the replay then fills the tail again without
/// showing anything twice.
public struct Transcript: Equatable, Sendable {
    public static let restartMarker = "[Carrying on after a restart]"
    /// How old an open question may be and still take a typed answer when its turn is over.
    public static let freshQuestionAge: TimeInterval = 3_600

    public private(set) var entries: [TranscriptEntry] = []
    public private(set) var isRunning = false

    /// Whether a message the person sent has not come back from the server yet.
    public var hasPendingUser: Bool { !pendingUserTexts.isEmpty }

    private var persistedMessageIds: Set<String> = []
    private var persistedToolCallIds: Set<String> = []
    private var liveEntryIds: Set<String> = []
    private var pendingUserTexts: [String] = []
    private var noticeCount = 0
    private var persistedReactions: [String: [Reaction]] = [:]
    /// Reactions changed on this phone or by an event. They win over what a
    /// reload brings, because the transcript is read from a replica that can
    /// still lack a reaction written a moment ago.
    private var foldedReactions: [String: FoldedReactions] = [:]

    private struct FoldedReactions: Equatable, Sendable {
        let reactions: [Reaction]
        let changedAt: Date
    }

    public init() {}

    // MARK: history

    /// Replaces the persisted part with `messages`, and the cards that still
    /// wait for the person. Live entries stay unless the history now holds
    /// them; a sent message that has not come back yet stays at the end.
    public mutating func load(messages: [ConversationMessage], questions: [QuestionCard], approvals: [ApprovalCard], isRunning: Bool) {
        let live = entries.filter { liveEntryIds.contains($0.id) }
        persistedMessageIds = Set(messages.map(\.id))
        persistedToolCallIds = Set(messages.compactMap { $0.role == "tool" ? $0.toolCallId : nil })
        persistedReactions = [:]
        for message in messages where !(message.reactions ?? []).isEmpty { persistedReactions[message.id] = message.reactions }

        var rebuilt: [TranscriptEntry] = []
        var argumentsByCall: [String: String] = [:]
        var lastUserText: String?
        for message in messages {
            switch message.role {
            case "user":
                let text = Self.text(of: message.content)
                guard !text.isEmpty else { continue }
                lastUserText = text
                if let note = Self.note(forUserText: text) {
                    rebuilt.append(.note(id: message.id, note))
                } else {
                    var viewing: Viewing?
                    if let kind = message.viewingKind, !kind.isEmpty, let id = message.viewingId, !id.isEmpty {
                        viewing = Viewing(kind: kind, id: id, label: message.viewingLabel)
                    }
                    rebuilt.append(.user(id: message.id, text: text, viewing: viewing))
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
                    rebuilt.append(.tool(ToolActivity(id: call.id, name: call.name, arguments: call.arguments)))
                }
            case "tool":
                if message.stopReason == "cancelled" { continue }
                let callId = message.toolCallId ?? message.id
                let metadata = message.metadata?.objectValue
                let note = metadata?["toolNote"]?.stringValue
                rebuilt.append(
                    .tool(
                        ToolActivity(
                            id: callId, name: message.toolName ?? "", arguments: argumentsByCall[callId] ?? "",
                            result: Self.text(of: message.content), note: (note ?? "").isEmpty ? nil : note,
                            durationMS: metadata?["durationMS"]?.numberValue.map { Int($0) })))
            case "system":
                if let entry = Self.entry(forSystem: message) { rebuilt.append(entry) }
            default:
                continue
            }
        }
        // A sent message the history now holds is no longer pending.
        if let lastUserText, let index = pendingUserTexts.lastIndex(of: lastUserText) {
            pendingUserTexts.removeSubrange(...index)
        }
        entries = rebuilt
        for text in pendingUserTexts { entries.append(.user(id: "pending:\(text)", text: text, viewing: nil)) }

        for card in questions where !entries.contains(where: { $0.id == "question:\(card.id)" }) { entries.append(.question(card)) }
        for card in approvals where !entries.contains(where: { $0.id == "approval:\(card.id)" }) { entries.append(.approval(card)) }

        // Keep live entries the history does not hold.
        let persistedTurnEnds = rebuilt.compactMap { entry -> TurnEndKind? in
            if case .turnEnd(_, let kind, _) = entry { return kind }
            return nil
        }
        for entry in live where !entries.contains(where: { $0.id == entry.id }) {
            switch entry {
            case .assistant(let id, _, _) where persistedMessageIds.contains(id): continue
            case .tool(let activity) where persistedToolCallIds.contains(activity.id): continue
            case .turnEnd(_, let kind, _) where persistedTurnEnds.contains(kind): continue
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
    public mutating func appendPendingUser(_ text: String, viewing: Viewing? = nil) {
        pendingUserTexts.append(text)
        entries.append(.user(id: "pending:\(text)", text: text, viewing: viewing))
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

    // MARK: typed answers

    /// The open question that typed text answers: the first one the person
    /// has not set aside, whose turn is still running or that is under an
    /// hour old. An approval is never answered by text.
    public func answerableQuestion(dismissedIds: Set<String>, now: Date = Date()) -> QuestionCard? {
        for entry in entries {
            guard case .question(let card) = entry, !dismissedIds.contains(card.id) else { continue }
            if isRunning { return card }
            if let asked = PortalDate.parse(card.askedAt), now.timeIntervalSince(asked) < Self.freshQuestionAge { return card }
        }
        return nil
    }

    // MARK: reactions

    /// The reactions on a message: what the phone or an event changed, else what the history holds.
    public func reactions(for messageId: String) -> [Reaction] {
        foldedReactions[messageId]?.reactions ?? persistedReactions[messageId] ?? []
    }

    /// Sets a message's reactions to the full list the server returned.
    public mutating func setReactions(_ reactions: [Reaction], for messageId: String, now: Date = Date()) {
        foldedReactions[messageId] = FoldedReactions(reactions: reactions, changedAt: now)
    }

    /// Lets the history win again over changes older than `age`, after a
    /// reconnect, when something may have changed while the feed was down.
    public mutating func expireFoldedReactions(olderThan age: TimeInterval, now: Date = Date()) {
        foldedReactions = foldedReactions.filter { now.timeIntervalSince($0.value.changedAt) < age }
    }

    // MARK: events

    /// Folds one event from the feed in.
    public mutating func apply(_ event: ConversationEvent, now: Date = Date()) {
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
            entries.append(.tool(ToolActivity(id: call.toolCallId, name: call.toolName, arguments: call.arguments ?? "")))
            liveEntryIds.insert(entryId)
        case .toolResult:
            guard let result = event.toolResult, let index = entries.firstIndex(where: { $0.id == "tool:\(result.toolCallId)" }),
                case .tool(var activity) = entries[index]
            else { return }
            activity.result = result.result ?? ""
            if let note = result.toolNote, !note.isEmpty { activity.note = note }
            if let duration = result.durationMS, duration > 0 { activity.durationMS = duration }
            entries[index] = .tool(activity)
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
            let reason = event.runComplete?.turnEndReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !reason.isEmpty, let kind = TurnEndKind(stopReason: event.runComplete?.stopReason) {
                appendLiveTurnEnd(kind: kind, text: reason, runId: event.runId)
            }
        case .runError:
            finishStreaming()
            isRunning = false
            // The operator's text is not for the person; the bounded sentence is.
            let reason = event.runError?.turnEndReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            appendLiveTurnEnd(kind: .failed, text: reason, runId: event.runId)
        case .roundRetry:
            // The round starts over: the text it streamed is dropped.
            guard let discarded = event.roundRetry?.discardedMessageId, !discarded.isEmpty else { return }
            entries.removeAll { $0.id == "assistant:\(discarded)" && liveEntryIds.contains($0.id) }
            liveEntryIds.remove("assistant:\(discarded)")
        case .reacted:
            guard let reacted = event.reacted, !reacted.messageId.isEmpty else { return }
            let change = Reaction(emoji: reacted.emoji, reactorKind: reacted.reactorKind, reactorUserId: reacted.reactorUserId)
            let current = reactions(for: reacted.messageId)
            foldedReactions[reacted.messageId] = FoldedReactions(reactions: Reaction.folding(change, into: current), changedAt: now)
        case .modelSwitch:
            // A switch the quick model asked for is already on screen from its own tool call.
            guard let modelSwitch = event.modelSwitch, modelSwitch.switchCause != "tool" else { return }
            finishStreaming()
            isRunning = true
            let id = "model-switch-\(event.runId ?? "")"
            guard !entries.contains(where: { $0.id == "tool:\(id)" }) else { return }
            let arguments = (try? JSONEncoder().encode(["switchReason": modelSwitch.switchReason ?? ""])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            entries.append(.tool(ToolActivity(id: id, name: ToolActivity.thinkHarderToolName, arguments: arguments, result: "")))
            liveEntryIds.insert("tool:\(id)")
        case .chatSaid, .chatEdited, .chatDeleted, .chatReacted, .chatMembers, .chatTyping, .chatRead, .chatLinkPreview, nil:
            // Chat events belong to ChatTimeline.
            return
        }
    }

    private mutating func appendLiveTurnEnd(kind: TurnEndKind, text: String, runId: String?) {
        noticeCount += 1
        let id = "\(runId ?? "run"):\(noticeCount)"
        entries.append(.turnEnd(id: id, kind: kind, text: text))
        liveEntryIds.insert("turnend:\(id)")
    }

    private mutating func finishStreaming() {
        for index in entries.indices {
            if case .assistant(let id, let text, true) = entries[index] {
                entries[index] = .assistant(id: id, text: text, isStreaming: false)
            }
        }
    }

    // MARK: display

    /// The entries as the screen draws them: each stretch of consecutive tool
    /// calls folds into one row, and what the calls made (a page, a file) is
    /// drawn right after it. "Thinking harder" stays a line of its own.
    public var displayEntries: [TranscriptEntry] {
        var result: [TranscriptEntry] = []
        var group: [ToolActivity] = []
        func flush() {
            guard !group.isEmpty else { return }
            result.append(.toolGroup(id: group[0].id, tools: group))
            for item in group.flatMap(\.producedItems) { result.append(.produced(item)) }
            group = []
        }
        for entry in entries {
            if case .tool(let activity) = entry {
                if activity.isThinkingHarder {
                    flush()
                    result.append(entry)
                } else {
                    group.append(activity)
                }
            } else {
                flush()
                result.append(entry)
            }
        }
        flush()
        return result
    }

    // MARK: reading persisted rows

    /// The note a user-role message stands for, when the assistant or the
    /// scheduler wrote it rather than the person.
    static func note(forUserText text: String) -> TranscriptNote? {
        if text.hasPrefix(restartMarker) { return .restart }
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else { return nil }
        let rest = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        func title(after prefix: String) -> String? {
            guard first.hasPrefix(prefix), first.hasSuffix("]") else { return nil }
            return String(first.dropFirst(prefix.count).dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if let name = title(after: "[Scheduled:") { return .scheduled(jobName: name, message: rest) }
        if let name = title(after: "[Background work finished:") { return .backgroundFinished(title: name, report: rest) }
        return nil
    }

    /// The entry a system row stands for: the note that ended a turn, the
    /// notice that finished work could not wake the assistant, or a
    /// compaction summary. Other system rows are not shown.
    static func entry(forSystem message: ConversationMessage) -> TranscriptEntry? {
        let metadata = message.metadata?.objectValue
        let text = Self.text(of: message.content).trimmingCharacters(in: .whitespacesAndNewlines)
        if metadata?["turnEnd"]?.boolValue == true, let kind = TurnEndKind(stopReason: message.stopReason) {
            return .turnEnd(id: message.id, kind: kind, text: text)
        }
        if metadata?["backgroundNote"]?.boolValue == true, !text.isEmpty {
            return .note(id: message.id, .backgroundNotice(text: text))
        }
        if message.stopReason == "context_summary" {
            return .note(id: message.id, .compaction(summary: text))
        }
        return nil
    }

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
