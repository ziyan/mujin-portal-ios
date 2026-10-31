import Foundation
import Testing

@testable import PortalKit

@Suite struct TranscriptTests {
    func delta(_ messageId: String, _ text: String) -> ConversationEvent {
        ConversationEvent(type: "text_delta", runId: "run01", textDelta: .init(messageId: messageId, text: text))
    }

    @Test func textDeltasBuildOneStreamingAnswer() {
        var transcript = Transcript()
        transcript.apply(delta("message01", "Hel"))
        transcript.apply(delta("message01", "lo"))
        #expect(transcript.entries == [.assistant(id: "message01", text: "Hello", isStreaming: true)])
        #expect(transcript.isRunning)
        transcript.apply(ConversationEvent(type: "run_complete", runComplete: .init(stopReason: "end_turn")))
        #expect(transcript.entries == [.assistant(id: "message01", text: "Hello", isStreaming: false)])
        #expect(!transcript.isRunning)
    }

    @Test func aToolCallClosesTheAnswerAndTheResultFillsItIn() {
        var transcript = Transcript()
        transcript.apply(delta("message01", "Let me look."))
        transcript.apply(ConversationEvent(type: "tool_call", toolCall: .init(toolCallId: "call01", toolName: "sites", arguments: #"{"a":1}"#)))
        #expect(transcript.entries.last == .tool(id: "call01", name: "sites", arguments: #"{"a":1}"#, result: nil))
        transcript.apply(ConversationEvent(type: "tool_result", toolResult: .init(toolCallId: "call01", result: "site01")))
        #expect(transcript.entries.last == .tool(id: "call01", name: "sites", arguments: #"{"a":1}"#, result: "site01"))
        #expect(transcript.entries.first == .assistant(id: "message01", text: "Let me look.", isStreaming: false))
        transcript.apply(delta("message02", "Found it."))
        #expect(transcript.entries.count == 3)
    }

    @Test func questionsAndApprovalsBecomeCardsOnce() {
        var transcript = Transcript()
        let question = ConversationEvent(
            type: "pending_question", pendingQuestion: .init(questionId: "q1", question: "Which site?", choices: ["site01", "site02"], allowOther: false))
        transcript.apply(question)
        transcript.apply(question)
        let approval = ConversationEvent(
            type: "pending_approval", pendingApproval: .init(approvalId: "a1", toolCallId: "call01", toolName: "shell", policyReason: "writes", risk: "high"))
        transcript.apply(approval)
        transcript.apply(approval)
        #expect(
            transcript.entries == [
                .question(QuestionCard(id: "q1", question: "Which site?", choices: ["site01", "site02"], allowOther: false)),
                .approval(ApprovalCard(id: "a1", toolCallId: "call01", toolName: "shell", policyReason: "writes", risk: "high")),
            ])
        transcript.removeQuestion(id: "q1")
        transcript.removeApproval(id: "a1")
        #expect(transcript.entries.isEmpty)
    }

    @Test func aRunErrorShowsANotice() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(type: "run_error", runId: "run01", runError: .init(error: "provider unavailable")))
        #expect(transcript.entries.count == 1)
        guard case .notice(_, let text, let isError) = transcript.entries[0] else { Issue.record("not a notice"); return }
        #expect(text == "provider unavailable")
        #expect(isError)
        #expect(!transcript.isRunning)
    }

    @Test func unknownEventsAreIgnored() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(type: "something_new"))
        #expect(transcript.entries.isEmpty)
    }

    @Test func historyIsFoldedIntoUserAssistantAndToolEntries() {
        var transcript = Transcript()
        let messages = [
            ConversationMessage(id: "m1", role: "user", content: .string("How many sites?")),
            ConversationMessage(
                id: "m2", role: "assistant", content: .string("Checking."),
                toolCalls: .array([.object(["id": .string("call01"), "function": .object(["name": .string("sites"), "arguments": .string("{}")])])])),
            ConversationMessage(id: "m3", role: "tool", content: .string("3 sites"), toolCallId: "call01", toolName: "sites"),
            ConversationMessage(
                id: "m4", role: "assistant", content: .array([.object(["type": .string("text"), "text": .string("Three.\n<!--suggestions:[\"More\"]-->")])])),
            ConversationMessage(id: "m5", role: "system", content: .string("summary")),
        ]
        transcript.load(messages: messages, questions: [], approvals: [], isRunning: false)
        #expect(
            transcript.entries == [
                .user(id: "m1", text: "How many sites?"),
                .assistant(id: "m2", text: "Checking.", isStreaming: false),
                .tool(id: "call01", name: "sites", arguments: "{}", result: "3 sites"),
                .assistant(id: "m4", text: "Three.", isStreaming: false),
            ])
    }

    @Test func aToolCallWithoutAResultYetIsShownRunning() {
        var transcript = Transcript()
        let messages = [
            ConversationMessage(
                id: "m2", role: "assistant", content: .string(""),
                toolCalls: .string(#"[{"id":"call01","function":{"name":"sites","arguments":"{}"}}]"#))
        ]
        transcript.load(messages: messages, questions: [], approvals: [], isRunning: true)
        #expect(transcript.entries == [.tool(id: "call01", name: "sites", arguments: "{}", result: nil)])
        #expect(transcript.isRunning)
    }

    @Test func aReplayOfWhatTheHistoryHoldsAddsNothing() {
        var transcript = Transcript()
        transcript.load(
            messages: [
                ConversationMessage(id: "message01", role: "assistant", content: .string("Done.")),
                ConversationMessage(id: "m3", role: "tool", content: .string("ok"), toolCallId: "call01", toolName: "sites"),
            ], questions: [], approvals: [], isRunning: false)
        let before = transcript.entries
        transcript.apply(delta("message01", "Done."))
        transcript.apply(ConversationEvent(type: "tool_call", toolCall: .init(toolCallId: "call01", toolName: "sites")))
        #expect(transcript.entries == before)
    }

    @Test func reconnectingDropsLiveEntriesSoTheReplayDoesNotDoubleThem() {
        var transcript = Transcript()
        transcript.load(messages: [ConversationMessage(id: "m1", role: "user", content: .string("Hi"))], questions: [], approvals: [], isRunning: true)
        transcript.apply(delta("message01", "Hel"))
        transcript.apply(ConversationEvent(type: "tool_call", toolCall: .init(toolCallId: "call01", toolName: "sites")))
        transcript.dropLiveEntries()
        #expect(transcript.entries == [.user(id: "m1", text: "Hi")])
        // The server replays the running turn from its start.
        transcript.apply(delta("message01", "Hel"))
        transcript.apply(delta("message01", "lo"))
        transcript.apply(ConversationEvent(type: "tool_call", toolCall: .init(toolCallId: "call01", toolName: "sites")))
        #expect(transcript.entries.count == 3)
        #expect(transcript.entries[1] == .assistant(id: "message01", text: "Hello", isStreaming: false))
    }

    @Test func aSentMessageShowsAtOnceAndIsReplacedByTheRealRow() {
        var transcript = Transcript()
        transcript.appendPendingUser("Hello")
        #expect(transcript.entries == [.user(id: "pending:Hello", text: "Hello")])
        #expect(transcript.isRunning)
        transcript.load(messages: [ConversationMessage(id: "m1", role: "user", content: .string("Hello"))], questions: [], approvals: [], isRunning: true)
        #expect(transcript.entries == [.user(id: "m1", text: "Hello")])
    }

    @Test func aMessageThatFailedToSendIsTakenBack() {
        var transcript = Transcript()
        transcript.appendPendingUser("Hello")
        transcript.removePendingUser("Hello")
        #expect(transcript.entries.isEmpty)
        #expect(!transcript.isRunning)
    }

    @Test func waitingCardsComeFromTheServerOnLoad() {
        var transcript = Transcript()
        transcript.load(
            messages: [], questions: [QuestionCard(id: "q1", question: "Which?")], approvals: [ApprovalCard(id: "a1", toolName: "shell")], isRunning: true)
        #expect(transcript.entries.count == 2)
    }

    @Test func suggestionMarkersAreHidden() {
        #expect(Transcript.visibleText("Hello\n<!--suggestions:[\"a\"]-->") == "Hello")
        #expect(Transcript.visibleText("Hello <!--suggestions:[\"a") == "Hello")
        #expect(Transcript.visibleText("Plain") == "Plain")
    }
}
