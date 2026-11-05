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

    /// The path of the screen a resource is on, matching the web routes: `/site/<id>` and so on.
    public var page: String? {
        switch kind {
        case "site": "/site/\(id)"
        case "controller": "/controller/\(id)"
        case "virtual_controller": "/virtualcontroller/\(id)"
        case "ticket": "/ticket/\(id)"
        case "incident": "/incident/\(id)"
        default: nil
        }
    }
}

/// PageContext is the screen the person is on, sent with every message to the
/// assistant so it knows what "this" is. A path with no query or fragment, at
/// most 200 characters, and the screen's title, at most 120.
public enum PageContext {
    public static let maximumPathLength = 200
    public static let maximumTitleLength = 120

    public static func path(_ path: String) -> String? {
        var text = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cut = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<cut]) }
        guard text.hasPrefix("/"), !text.hasPrefix("//") else { return nil }
        return String(text.prefix(maximumPathLength))
    }

    public static func title(_ title: String?) -> String? {
        let text = (title ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(maximumTitleLength))
    }
}

/// ReplyReference is a message a reply is about, shown above the composer
/// and, once sent, as a compact quote above the reply. The words of the
/// quote are never put in the message itself.
public struct ReplyReference: Equatable, Sendable {
    public let messageId: String
    public let authorName: String
    public let excerpt: String
    /// Whether the person wrote the message they reply to.
    public let isOwn: Bool

    public init(messageId: String, authorName: String, excerpt: String, isOwn: Bool = false) {
        self.messageId = messageId
        self.authorName = authorName
        self.isOwn = isOwn
        self.excerpt = Self.shortened(excerpt)
    }

    /// A bounded excerpt: whitespace collapsed, at most 200 characters.
    static func shortened(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 200 ? String(collapsed.prefix(199)) + "\u{2026}" : collapsed
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

/// TurnEndKind says how a turn that ended without an answer reads: as a
/// failure, or as a quieter note.
public enum TurnEndKind: Equatable, Sendable {
    case failed
    case roundLimit
    case repeatedFailure
    /// A stop the person asked for, or a wait for an answer already under way.
    case interruption

    init?(stopReason: String?) {
        switch stopReason {
        case "error": self = .failed
        case "round_limit": self = .roundLimit
        case "repeated_failure": self = .repeatedFailure
        default: return nil
        }
    }
}

/// TurnEndReason is the structured reason a turn ended, so the app words it
/// in the person's language. A `kind` the app does not know shows the row's
/// own sentence.
public struct TurnEndReason: Equatable, Sendable {
    public let kind: String
    /// `httpStatus`, `roundCount` or `toolName`, as the server sent them.
    public let parameters: [String: String]

    public init(kind: String, parameters: [String: String] = [:]) {
        self.kind = kind
        self.parameters = parameters
    }

    static let knownKinds: Set<String> = [
        "failed", "contextTooLong", "providerCredentials", "providerRateLimited", "providerUnavailable", "providerRefused",
        "connectionInterrupted", "roundLimit", "repeatedFailure", "stoppedByUser", "queuedBehindRun", "unreadableToolCall",
    ]

    public var isKnown: Bool { Self.knownKinds.contains(kind) }

    /// How the line reads: a failure in red, the rest as a quiet note.
    public var turnEndKind: TurnEndKind {
        switch kind {
        case "roundLimit": .roundLimit
        case "repeatedFailure": .repeatedFailure
        case "stoppedByUser", "queuedBehindRun", "unreadableToolCall": .interruption
        default: .failed
        }
    }

    init?(kind: String?, parameters: JSONValue?) {
        guard let kind, !kind.isEmpty else { return nil }
        var values: [String: String] = [:]
        var object = parameters
        if case .string(let text)? = object, let data = text.data(using: .utf8) { object = try? JSONDecoder().decode(JSONValue.self, from: data) }
        if case .object(let fields)? = object {
            for (key, value) in fields {
                if let text = value.stringValue {
                    values[key] = text
                } else if let number = value.numberValue {
                    values[key] = number == number.rounded() ? String(Int(number)) : String(number)
                }
            }
        }
        self.init(kind: kind, parameters: values)
    }
}

/// DepthKind says the assistant is working harder than usual.
public enum DepthKind: String, Equatable, Sendable {
    /// The effort judgment chose a closer look.
    case lookingClosely
    /// The quick model handed over with `think_harder`.
    case thinkingHarder
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
    /// The assistant started this conversation. `reason` is `onboarding`, `goal_needs_you`, `memory_check` or `idea`.
    case speakFirst(reason: String)
    /// A goal's own turn; `message` is the text the model was given.
    case goalCheckIn(title: String, message: String)
    /// The assistant is looking more closely or thinking harder; `reason` is its few words.
    case depth(DepthKind, reason: String, sentence: String)
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
    case turnEnd(id: String, kind: TurnEndKind, text: String, reason: TurnEndReason? = nil)
    case note(id: String, TranscriptNote)
    /// A goal is blocked and needs the person: the question, and the goal it is about.
    case goalNeedsYou(id: String, goalId: String, title: String, question: String)

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
        case .turnEnd(let id, _, _, _): "turnend:\(id)"
        case .goalNeedsYou(let id, _, _, _): "goalneedsyou:\(id)"
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
    private var replyQuotes: [String: ReplyReference] = [:]
    /// Why the assistant spoke first, by the message that carries "Not now" and "Stop these": its first answer.
    private var speakFirstReasons: [String: String] = [:]
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
        replyQuotes = [:]
        for message in messages {
            if let replyId = message.replyToMessageId, !replyId.isEmpty, let excerpt = message.replyToExcerpt, !excerpt.isEmpty {
                replyQuotes[message.id] = ReplyReference(messageId: replyId, authorName: message.replyToAuthorName ?? "", excerpt: excerpt)
            }
        }
        for message in messages where !(message.reactions ?? []).isEmpty { persistedReactions[message.id] = message.reactions }

        var rebuilt: [TranscriptEntry] = []
        var rebuiltSpeakFirstReasons: [String: String] = [:]
        var argumentsByCall: [String: String] = [:]
        var lastUserText: String?
        var speakFirstReasonAwaitingAnswer: String?
        for message in messages {
            switch message.role {
            case "user":
                let text = Self.text(of: message.content)
                guard !text.isEmpty else { continue }
                lastUserText = text
                if let note = Self.note(forUserText: text) {
                    if case .speakFirst(let reason) = note { speakFirstReasonAwaitingAnswer = reason }
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
                if let needsYou = Self.goalNeedsYou(text: text, metadata: message.metadata?.objectValue) {
                    rebuilt.append(.goalNeedsYou(id: message.id, goalId: needsYou.goalId, title: needsYou.title, question: needsYou.question))
                } else if !text.isEmpty {
                    rebuilt.append(.assistant(id: message.id, text: text, isStreaming: false))
                    if let reason = speakFirstReasonAwaitingAnswer {
                        rebuiltSpeakFirstReasons[message.id] = reason
                        speakFirstReasonAwaitingAnswer = nil
                    }
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
        speakFirstReasons = rebuiltSpeakFirstReasons
        for text in pendingUserTexts { entries.append(.user(id: "pending:\(text)", text: text, viewing: nil)) }

        for card in questions where !entries.contains(where: { $0.id == "question:\(card.id)" }) { entries.append(.question(card)) }
        for card in approvals where !entries.contains(where: { $0.id == "approval:\(card.id)" }) { entries.append(.approval(card)) }

        // Keep live entries the history does not hold.
        let persistedTurnEnds = rebuilt.compactMap { entry -> TurnEndKind? in
            if case .turnEnd(_, let kind, _, _) = entry { return kind }
            return nil
        }
        for entry in live where !entries.contains(where: { $0.id == entry.id }) {
            switch entry {
            case .assistant(let id, _, _) where persistedMessageIds.contains(id): continue
            case .tool(let activity) where persistedToolCallIds.contains(activity.id): continue
            case .turnEnd(_, let kind, _, _) where persistedTurnEnds.contains(kind): continue
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

    /// The message a sent message replied to, for the quote above its text.
    /// Nothing is returned for a reply to the message directly above it: the quote would only repeat it.
    public func replyQuote(for messageId: String) -> ReplyReference? {
        guard let quote = replyQuotes[messageId] else { return nil }
        let displayed = displayEntries
        if let index = displayed.firstIndex(where: { $0.id == "user:\(messageId)" }), index > 0 {
            switch displayed[index - 1] {
            case .assistant(let id, _, _), .user(let id, _, _): if id == quote.messageId { return nil }
            default: break
            }
        }
        return quote
    }

    /// Why the assistant spoke first, when `messageId` is the first answer after it did.
    public func speakFirstReason(for messageId: String) -> String? {
        speakFirstReasons[messageId]
    }

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
            let sentence = event.runComplete?.turnEndReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let structured = TurnEndReason(kind: event.runComplete?.reasonKind, parameters: event.runComplete?.reasonParameters)
            if let structured, structured.kind != "failed" || !sentence.isEmpty {
                appendLiveTurnEnd(kind: structured.turnEndKind, text: sentence, reason: structured, runId: event.runId)
            } else if !sentence.isEmpty, let kind = TurnEndKind(stopReason: event.runComplete?.stopReason) {
                appendLiveTurnEnd(kind: kind, text: sentence, reason: nil, runId: event.runId)
            }
        case .runError:
            finishStreaming()
            isRunning = false
            // The operator's text is not for the person; the bounded sentence is.
            let sentence = event.runError?.turnEndReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let structured = TurnEndReason(kind: event.runError?.reasonKind, parameters: event.runError?.reasonParameters)
            appendLiveTurnEnd(kind: structured?.turnEndKind ?? .failed, text: sentence, reason: structured, runId: event.runId)
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
        case .conversationUpdated, .chatSaid, .chatEdited, .chatDeleted, .chatReacted, .chatMembers, .chatTyping, .chatRead, .chatLinkPreview, nil:
            // Chat events belong to ChatTimeline.
            return
        }
    }

    private mutating func appendLiveTurnEnd(kind: TurnEndKind, text: String, reason: TurnEndReason?, runId: String?) {
        noticeCount += 1
        let id = "\(runId ?? "run"):\(noticeCount)"
        entries.append(.turnEnd(id: id, kind: kind, text: text, reason: reason))
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
        // Every answer has one "What it did", however many stretches of tool calls it took.
        var turnGroupIndex: Int?
        func flush() {
            guard !group.isEmpty else { return }
            if let index = turnGroupIndex, case .toolGroup(let id, let earlier) = result[index] {
                result[index] = .toolGroup(id: id, tools: earlier + group)
            } else {
                result.append(.toolGroup(id: group[0].id, tools: group))
                turnGroupIndex = result.count - 1
            }
            for item in group.flatMap(\.producedItems) { result.append(.produced(item)) }
            group = []
        }
        for entry in entries {
            if case .tool(let activity) = entry {
                // Handing the turn to the main model is no line of its own, while it runs or after.
                if !activity.isThinkingHarder { group.append(activity) }
            } else {
                flush()
                if case .user = entry { turnGroupIndex = nil }
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
        if let reason = title(after: "[Speaking first:") { return .speakFirst(reason: reason) }
        if let name = title(after: "[Goal check-in:") { return .goalCheckIn(title: name, message: rest) }
        return nil
    }

    /// The entry a system row stands for: the note that ended a turn, the
    /// notice that finished work could not wake the assistant, or a
    /// compaction summary. Other system rows are not shown.
    static func entry(forSystem message: ConversationMessage) -> TranscriptEntry? {
        let metadata = message.metadata?.objectValue
        let text = Self.text(of: message.content).trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = TurnEndReason(kind: metadata?["reasonKind"]?.stringValue, parameters: metadata?["reasonParameters"])
        if metadata?["turnEnd"]?.boolValue == true {
            if let reason { return .turnEnd(id: message.id, kind: reason.turnEndKind, text: text, reason: reason) }
            if let kind = TurnEndKind(stopReason: message.stopReason) { return .turnEnd(id: message.id, kind: kind, text: text) }
            if message.stopReason == "cancelled" || message.stopReason == "queued" || message.stopReason == "unreadable_call", !text.isEmpty {
                return .turnEnd(id: message.id, kind: .interruption, text: text)
            }
        }
        if metadata?["depthNote"]?.boolValue == true, let depth = reason.flatMap({ DepthKind(rawValue: $0.kind) }) {
            return .note(id: message.id, .depth(depth, reason: reason?.parameters["reason"] ?? "", sentence: text))
        }
        if metadata?["backgroundNote"]?.boolValue == true, !text.isEmpty {
            return .note(id: message.id, .backgroundNotice(text: text))
        }
        if message.stopReason == "context_summary" {
            return .note(id: message.id, .compaction(summary: text))
        }
        return nil
    }

    /// The question of a blocked goal's message: `[Goal needs you: <title>]`,
    /// a repeat line, the question, then an answer hint ending `(goal id: <id>)`.
    static func goalNeedsYou(text: String, metadata: [String: JSONValue]?) -> (goalId: String, title: String, question: String)? {
        let marker = "[Goal needs you:"
        guard text.hasPrefix(marker) else { return nil }
        let paragraphs = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = paragraphs.first, first.hasSuffix("]") || first.contains("]") else { return nil }
        let title = String(first.dropFirst(marker.count).prefix { $0 != "]" }).trimmingCharacters(in: .whitespaces)
        var goalId = metadata?["goalNeedsYou"]?["goalId"]?.stringValue ?? ""
        if goalId.isEmpty, let hint = paragraphs.last, let open = hint.range(of: "(goal id: "), let close = hint.range(of: ")", range: open.upperBound..<hint.endIndex) {
            goalId = String(hint[open.upperBound..<close.lowerBound])
        }
        // The second paragraph repeats the marker's idea; the question follows it.
        let question = paragraphs.count > 2 ? paragraphs[2] : (paragraphs.count > 1 ? paragraphs[1] : "")
        return (goalId, title, question)
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
