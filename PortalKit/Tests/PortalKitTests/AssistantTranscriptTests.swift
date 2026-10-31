import Foundation
import Testing

@testable import PortalKit

@Suite struct AssistantTranscriptTests {
    func load(_ messages: [ConversationMessage], isRunning: Bool = false) -> Transcript {
        var transcript = Transcript()
        transcript.load(messages: messages, questions: [], approvals: [], isRunning: isRunning)
        return transcript
    }

    func reacted(_ messageId: String, _ emoji: String, kind: String = "user", user: String? = "user01") -> ConversationEvent {
        ConversationEvent(type: "reacted", reacted: .init(messageId: messageId, emoji: emoji, reactorKind: kind, reactorUserId: user))
    }

    // MARK: reactions

    @Test func reactionsFoldByReactor() {
        var transcript = Transcript()
        transcript.apply(reacted("m1", "\u{1F440}", kind: "assistant", user: nil))
        transcript.apply(reacted("m1", "\u{1F44D}"))
        #expect(transcript.reactions(for: "m1").map(\.emoji) == ["\u{1F440}", "\u{1F44D}"])
        // The same person changes their mind: replaced in place.
        transcript.apply(reacted("m1", "\u{2764}\u{FE0F}"))
        #expect(transcript.reactions(for: "m1").map(\.emoji) == ["\u{1F440}", "\u{2764}\u{FE0F}"])
        // Another person adds theirs.
        transcript.apply(reacted("m1", "\u{1F389}", user: "user02"))
        #expect(transcript.reactions(for: "m1").count == 3)
        // An empty emoji takes the reaction back.
        transcript.apply(reacted("m1", "", user: "user01"))
        #expect(transcript.reactions(for: "m1").map(\.emoji) == ["\u{1F440}", "\u{1F389}"])
    }

    @Test func aReactionToAMessageNotLoadedYetWaitsForIt() {
        var transcript = Transcript()
        transcript.appendPendingUser("Hello")
        transcript.apply(reacted("m1", "\u{1F440}", kind: "assistant", user: nil))
        #expect(transcript.reactions(for: "m1").count == 1)
        transcript.load(messages: [ConversationMessage(id: "m1", role: "user", content: .string("Hello"))], questions: [], approvals: [], isRunning: true)
        #expect(transcript.reactions(for: "m1").map(\.emoji) == ["\u{1F440}"])
    }

    @Test func persistedReactionsShowAndALocalChangeWinsOverARefetch() {
        let persisted = [Reaction(emoji: "\u{1F44D}", reactorKind: "user", reactorUserId: "user01", isAcknowledgment: false)]
        var transcript = load([ConversationMessage(id: "m1", role: "assistant", content: .string("Hi"), reactions: persisted)])
        #expect(transcript.reactions(for: "m1") == persisted)
        let now = Date()
        transcript.setReactions([], for: "m1", now: now)
        // A replica that has not caught up still sends the old reaction.
        transcript.load(messages: [ConversationMessage(id: "m1", role: "assistant", content: .string("Hi"), reactions: persisted)], questions: [], approvals: [], isRunning: false)
        #expect(transcript.reactions(for: "m1").isEmpty)
        // After a reconnect, old local changes give way to the history.
        transcript.expireFoldedReactions(olderThan: 60, now: now.addingTimeInterval(120))
        #expect(transcript.reactions(for: "m1") == persisted)
    }

    @Test func reactionSummariesGroupByEmojiAndMarkTheirs() {
        let reactions = [
            Reaction(emoji: "\u{1F440}", reactorKind: "assistant"),
            Reaction(emoji: "\u{1F44D}", reactorKind: "user", reactorUserId: "user01"),
            Reaction(emoji: "\u{1F44D}", reactorKind: "user", reactorUserId: "user02"),
        ]
        let summaries = Reactions.summaries(reactions, currentUserId: "user01")
        #expect(summaries.map(\.emoji) == ["\u{1F440}", "\u{1F44D}"])
        #expect(summaries[0].isFromAssistant && !summaries[0].isMine)
        #expect(summaries[1].count == 2 && summaries[1].isMine)
    }

    @Test func pickingTheEmojiYouAlreadyHaveTakesItBack() {
        let mine = [Reaction(emoji: "\u{1F44D}", reactorKind: "user", reactorUserId: "user01")]
        #expect(Reactions.emojiToSend(chosen: "\u{1F44D}", in: mine, currentUserId: "user01") == "")
        #expect(Reactions.emojiToSend(chosen: "\u{1F64F}", in: mine, currentUserId: "user01") == "\u{1F64F}")
        #expect(Reactions.emojiToSend(chosen: "\u{1F44D}", in: [], currentUserId: "user01") == "\u{1F44D}")
        #expect(Reactions.palette.count == 6)
    }

    @Test func onlyOneOrTwoEmojiAreAcceptable() {
        #expect(Reactions.isAcceptable("\u{1F44D}"))
        #expect(Reactions.isAcceptable("\u{1F44D}\u{1F44E}"))
        #expect(!Reactions.isAcceptable("\u{1F44D}\u{1F44E}\u{1F64F}"))
        #expect(!Reactions.isAcceptable("  "))
    }

    @Test func reactionsDecodeFromAMessage() throws {
        let json = #"{"id":"m1","role":"assistant","content":"Hi","reactions":[{"id":"r1","messageId":"m1","reactorKind":"assistant","reactorUserId":null,"emoji":"\#u{1F440}","isAcknowledgment":true}]}"#
        let message = try JSONDecoder().decode(ConversationMessage.self, from: Data(json.utf8))
        #expect(message.reactions?.first?.isAcknowledgment == true)
        #expect(message.reactions?.first?.isAssistant == true)
    }

    // MARK: model switch, retries, tool notes

    @Test func aJudgedModelSwitchIsAThinkingHarderLineAndAToolOneIsNot() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(type: "model_switch", runId: "run01", modelSwitch: .init(switchCause: "tool", switchReason: "hard question")))
        #expect(transcript.entries.isEmpty)
        transcript.apply(ConversationEvent(type: "model_switch", runId: "run01", modelSwitch: .init(switchCause: "judgment", switchReason: "")))
        guard case .tool(let activity) = transcript.entries[0] else { Issue.record("no line"); return }
        #expect(activity.isThinkingHarder)
        #expect(!activity.isRunning)
        #expect(activity.thinkHarderReason == nil)
        // A second event of the same run adds no second line.
        transcript.apply(ConversationEvent(type: "model_switch", runId: "run01", modelSwitch: .init(switchCause: "judgment")))
        #expect(transcript.entries.count == 1)
    }

    @Test func theThinkHarderToolCallCarriesItsReason() {
        let activity = ToolActivity(id: "c1", name: "think_harder", arguments: #"{"switchReason":"needs a closer look"}"#)
        #expect(activity.thinkHarderReason == "needs a closer look")
        #expect(ToolActivity(id: "c2", name: "sites", arguments: #"{"switchReason":"x"}"#).thinkHarderReason == nil)
    }

    @Test func aRoundRetryDropsTheTextItStreamed() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(type: "text_delta", textDelta: .init(messageId: "message01", text: "Partial")))
        transcript.apply(ConversationEvent(type: "round_retry", roundRetry: .init(discardedMessageId: "message01")))
        #expect(transcript.entries.isEmpty)
        transcript.apply(ConversationEvent(type: "text_delta", textDelta: .init(messageId: "message02", text: "Whole answer")))
        #expect(transcript.entries == [.assistant(id: "message02", text: "Whole answer", isStreaming: true)])
    }

    @Test func aLiveToolResultKeepsItsNoteAndDuration() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(type: "tool_call", toolCall: .init(toolCallId: "c1", toolName: "controllers")))
        transcript.apply(ConversationEvent(type: "tool_result", toolResult: .init(toolCallId: "c1", result: "[]", toolNote: "3 controllers", durationMS: 850)))
        guard case .tool(let activity) = transcript.entries[0] else { Issue.record("no tool"); return }
        #expect(activity.note == "3 controllers")
        #expect(activity.durationMS == 850)
    }

    @Test func aStoredToolRowReadsItsNoteFromMetadataInEitherShape() {
        let asObject = ConversationMessage(
            id: "t1", role: "tool", content: .string("ok"), toolCallId: "c1", toolName: "sites",
            metadata: .object(["toolNote": .string("2 sites"), "durationMS": .number(1_200)]))
        let asString = ConversationMessage(
            id: "t2", role: "tool", content: .string("ok"), toolCallId: "c2", toolName: "sites",
            metadata: .string(#"{"toolNote":"5 sites","durationMS":40}"#))
        let transcript = load([asObject, asString])
        guard case .tool(let first) = transcript.entries[0], case .tool(let second) = transcript.entries[1] else { Issue.record("no tools"); return }
        #expect(first.note == "2 sites" && first.durationMS == 1_200)
        #expect(second.note == "5 sites" && second.durationMS == 40)
    }

    @Test func durationsReadAsMillisecondsSecondsAndMinutes() {
        func text(_ ms: Int?) -> String? { ToolActivity(id: "c", name: "sites", durationMS: ms).durationText }
        #expect(text(850) == "850 ms")
        #expect(text(2_400) == "2.4 s")
        #expect(text(65_000) == "1 min 5 s")
        #expect(text(nil) == nil)
        #expect(text(0) == nil)
        #expect(ToolActivity(id: "c", name: "list_controllers").displayName == "list controllers")
    }

    @Test func aStretchOfToolCallsFoldsIntoOneRow() {
        let transcript = load([
            ConversationMessage(id: "m1", role: "user", content: .string("Go")),
            ConversationMessage(id: "t1", role: "tool", content: .string("a"), toolCallId: "c1", toolName: "sites"),
            ConversationMessage(id: "t2", role: "tool", content: .string("b"), toolCallId: "c2", toolName: "controllers"),
            ConversationMessage(id: "m2", role: "assistant", content: .string("Done")),
            ConversationMessage(id: "t3", role: "tool", content: .string("c"), toolCallId: "c3", toolName: "sites"),
        ])
        let shown = transcript.displayEntries
        // One row for the whole turn: the user's message, the row, the answer.
        #expect(shown.count == 3)
        guard case .toolGroup(_, let tools) = shown[1] else { Issue.record("no group"); return }
        #expect(tools.map(\.name) == ["sites", "controllers", "sites"])
    }

    @Test func thinkingHarderIsNoLineAndDoesNotSplitTheGroup() {
        let transcript = load([
            ConversationMessage(id: "t1", role: "tool", content: .string("a"), toolCallId: "c1", toolName: "sites"),
            ConversationMessage(id: "t2", role: "tool", content: .string(""), toolCallId: "c2", toolName: "think_harder"),
            ConversationMessage(id: "t3", role: "tool", content: .string("c"), toolCallId: "c3", toolName: "sites"),
        ])
        let shown = transcript.displayEntries
        #expect(shown.count == 1)
        guard case .toolGroup(_, let tools) = shown[0] else { Issue.record("no group"); return }
        #expect(tools.map(\.id) == ["c1", "c3"])
    }

    @Test func oneAnswerHasOneWhatItDidEvenWhenTextSitsBetweenToolCalls() {
        let transcript = load([
            ConversationMessage(id: "u1", role: "user", content: .string("Compare the sites")),
            ConversationMessage(id: "t1", role: "tool", content: .string("a"), toolCallId: "c1", toolName: "sites"),
            ConversationMessage(id: "a1", role: "assistant", content: .string("Let me look closer.")),
            ConversationMessage(id: "t2", role: "tool", content: .string("b"), toolCallId: "c2", toolName: "metrics"),
            ConversationMessage(id: "u2", role: "user", content: .string("And site two?")),
            ConversationMessage(id: "t3", role: "tool", content: .string("c"), toolCallId: "c3", toolName: "sites"),
        ])
        let groups = transcript.displayEntries.compactMap { entry -> [String]? in
            if case .toolGroup(_, let tools) = entry { return tools.map(\.id) }
            return nil
        }
        #expect(groups == [["c1", "c2"], ["c3"]])
    }

    // MARK: artifacts and files

    @Test func theArtifactToolMakesACardAfterItsGroup() {
        let result = #"{"artifactId":"artifact01","attachmentId":"att01","title":"Weekly throughput","artifactKind":"html","sizeBytes":2048,"url":"/api/v1/artifact/artifact01"}"#
        let transcript = load([ConversationMessage(id: "t1", role: "tool", content: .string(result), toolCallId: "c1", toolName: "artifact")])
        let shown = transcript.displayEntries
        #expect(shown.count == 2)
        guard case .produced(.artifact(let artifact)) = shown[1] else { Issue.record("no card"); return }
        #expect(artifact == ArtifactReference(id: "artifact01", title: "Weekly throughput", kind: .html, sizeBytes: 2048))
    }

    @Test func aShellCommandsFilesAreListed() {
        let result = #"{"exitCode":0,"artifacts":[{"name":"report.csv","attachmentId":"att02","url":"/api/v1/attachment/att02","contentType":"text/csv","sizeBytes":120},{"name":"plot.png","attachmentId":"att03","contentType":"image/png"},{"name":"broken"}]}"#
        let items = ProducedItem.items(toolName: "shell", result: result)
        #expect(items.count == 2)
        guard case .file(let first) = items[0], case .file(let second) = items[1] else { Issue.record("no files"); return }
        #expect(first.name == "report.csv" && !first.isImage)
        #expect(second.isImage)
    }

    @Test func otherToolsAndUnreadableResultsProduceNothing() {
        #expect(ProducedItem.items(toolName: "sites", result: #"{"artifactId":"x","artifactKind":"html"}"#).isEmpty)
        #expect(ProducedItem.items(toolName: "artifact", result: "not json").isEmpty)
        #expect(ProducedItem.items(toolName: "artifact", result: #"{"artifactId":"x","artifactKind":"flash"}"#).isEmpty)
        #expect(ProducedItem.items(toolName: "artifact", result: nil).isEmpty)
    }

    // MARK: notes

    @Test func storedTurnEndNotesShowAfterAReload() {
        let transcript = load([
            ConversationMessage(
                id: "s1", role: "system", content: .string("The model did not answer."), stopReason: "error", metadata: .object(["turnEnd": .bool(true)])),
            ConversationMessage(
                id: "s2", role: "system", content: .string("It stopped after many steps."), stopReason: "round_limit",
                metadata: .string(#"{"turnEnd":true}"#)),
            ConversationMessage(
                id: "s3", role: "system", content: .string("A tool kept failing."), stopReason: "repeated_failure", metadata: .object(["turnEnd": .bool(true)])),
            ConversationMessage(id: "s4", role: "system", content: .string("hidden"), stopReason: "end_turn"),
        ])
        #expect(
            transcript.entries == [
                .turnEnd(id: "s1", kind: .failed, text: "The model did not answer."),
                .turnEnd(id: "s2", kind: .roundLimit, text: "It stopped after many steps."),
                .turnEnd(id: "s3", kind: .repeatedFailure, text: "A tool kept failing."),
            ])
    }

    @Test func aLiveTurnEndGivesWayToTheStoredOne() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(type: "run_error", runId: "run01", runError: .init(error: "x", turnEndReason: "The model did not answer.")))
        #expect(transcript.entries.count == 1)
        transcript.load(
            messages: [
                ConversationMessage(
                    id: "s1", role: "system", content: .string("The model did not answer."), stopReason: "error", metadata: .object(["turnEnd": .bool(true)]))
            ], questions: [], approvals: [], isRunning: false)
        #expect(transcript.entries == [.turnEnd(id: "s1", kind: .failed, text: "The model did not answer.")])
    }

    @Test func aRunThatTheRunnerEndedShowsItsSentence() {
        var transcript = Transcript()
        transcript.apply(
            ConversationEvent(type: "run_complete", runId: "run01", runComplete: .init(stopReason: "round_limit", turnEndReason: "It stopped after many steps.")))
        #expect(transcript.entries == [.turnEnd(id: "run01:1", kind: .roundLimit, text: "It stopped after many steps.")])
        var quiet = Transcript()
        quiet.apply(ConversationEvent(type: "run_complete", runComplete: .init(stopReason: "end_turn")))
        #expect(quiet.entries.isEmpty)
    }

    @Test func compactionBecomesANoteAndOtherSystemRowsStayHidden() {
        let transcript = load([ConversationMessage(id: "s1", role: "system", content: .string("Earlier: the plan."), stopReason: "context_summary")])
        #expect(transcript.entries == [.note(id: "s1", .compaction(summary: "Earlier: the plan."))])
    }

    @Test func aBackgroundNoteIsForThePersonOnly() {
        let transcript = load([
            ConversationMessage(
                id: "s1", role: "system", content: .string("Work finished, but it could not wake the assistant."),
                metadata: .object(["backgroundNote": .bool(true)]))
        ])
        #expect(transcript.entries == [.note(id: "s1", .backgroundNotice(text: "Work finished, but it could not wake the assistant."))])
    }

    @Test func theRestartMarkerBecomesANote() {
        let transcript = load([ConversationMessage(id: "m1", role: "user", content: .string("[Carrying on after a restart]\nContinue the task."))])
        #expect(transcript.entries == [.note(id: "m1", .restart)])
    }

    @Test func aScheduledTurnShowsTheJobNameAndOpensToItsMessage() {
        let transcript = load([ConversationMessage(id: "m1", role: "user", content: .string("[Scheduled: Morning check]\nLook at the alarms."))])
        #expect(transcript.entries == [.note(id: "m1", .scheduled(jobName: "Morning check", message: "Look at the alarms."))])
    }

    @Test func finishedBackgroundWorkShowsItsTitleAndReport() {
        let transcript = load([
            ConversationMessage(id: "m1", role: "user", content: .string("[Background work finished: Compare sites]\nSite one is faster.\nSite two is slower."))
        ])
        #expect(
            transcript.entries == [
                .note(id: "m1", .backgroundFinished(title: "Compare sites", report: "Site one is faster.\nSite two is slower."))
            ])
    }

    @Test func anOrdinaryMessageThatMentionsBracketsStaysABubble() {
        let transcript = load([ConversationMessage(id: "m1", role: "user", content: .string("[Scheduled maintenance] is tonight"))])
        #expect(transcript.entries == [.user(id: "m1", text: "[Scheduled maintenance] is tonight", viewing: nil)])
    }

    @Test func aMessageKeepsTheScreenItWasAskedAbout() {
        let transcript = load([
            ConversationMessage(
                id: "m1", role: "user", content: .string("Why is this red?"), viewingKind: "controller", viewingId: "controller01",
                viewingLabel: "controller01")
        ])
        #expect(transcript.entries == [.user(id: "m1", text: "Why is this red?", viewing: Viewing(kind: "controller", id: "controller01", label: "controller01"))])
    }

    // MARK: typed answers

    @Test func typedTextAnswersAnOpenQuestionWhileTheTurnRuns() {
        var transcript = Transcript()
        transcript.load(messages: [], questions: [QuestionCard(id: "q1", question: "Which?", askedAt: "2026-01-01T10:00:00Z")], approvals: [], isRunning: true)
        #expect(transcript.answerableQuestion(dismissedIds: [])?.id == "q1")
        #expect(transcript.answerableQuestion(dismissedIds: ["q1"]) == nil)
    }

    @Test func aQuestionOlderThanAnHourAnswersNothingOnceTheTurnIsOver() {
        var transcript = Transcript()
        transcript.load(messages: [], questions: [QuestionCard(id: "q1", question: "Which?", askedAt: "2026-01-01T10:00:00Z")], approvals: [], isRunning: false)
        let asked = PortalDate.parse("2026-01-01T10:00:00Z")!
        #expect(transcript.answerableQuestion(dismissedIds: [], now: asked.addingTimeInterval(1_800))?.id == "q1")
        #expect(transcript.answerableQuestion(dismissedIds: [], now: asked.addingTimeInterval(3_700)) == nil)
    }

    @Test func anApprovalIsNeverAnsweredByText() {
        var transcript = Transcript()
        transcript.load(messages: [], questions: [], approvals: [ApprovalCard(id: "a1", toolName: "shell")], isRunning: true)
        #expect(transcript.answerableQuestion(dismissedIds: []) == nil)
    }

    // MARK: paging

    @Test func theWindowGrowsBackwardsAndCountsWhatIsEarlier() {
        func rows(_ range: ClosedRange<Int>) -> [ConversationMessage] { range.map { ConversationMessage(id: "m\($0)", role: "user", content: .string("x")) } }
        var window = MessageWindow()
        window.replace(with: rows(71...100), totalCount: 100)
        #expect(window.earlierCount == 70)
        #expect(window.firstMessageId == "m71")
        #expect(window.reloadCount == 50)
        window.prepend(rows(41...75))
        #expect(window.messages.count == 60)
        #expect(window.messages.first?.id == "m41")
        #expect(window.earlierCount == 40)
        #expect(window.reloadCount == 80)
    }

    @Test func aWindowOfNothingHasNothingEarlier() {
        #expect(MessageWindow().earlierCount == 0)
        #expect(MessageWindow().reloadCount == MessageWindow.pageSize)
    }
}

@Suite struct GapClosingTranscriptTests {
    func load(_ messages: [ConversationMessage]) -> Transcript {
        var transcript = Transcript()
        transcript.load(messages: messages, questions: [], approvals: [], isRunning: false)
        return transcript
    }

    @Test func aStoredTurnEndKeepsItsStructuredReason() {
        let transcript = load([
            ConversationMessage(
                id: "s1", role: "system", content: .string("The model provider refused the request (HTTP 402)."), stopReason: "error",
                metadata: .object([
                    "turnEnd": .bool(true), "reasonKind": .string("providerRefused"), "reasonParameters": .object(["httpStatus": .string("402")]),
                ])),
            ConversationMessage(
                id: "s2", role: "system", content: .string("Stopped."), stopReason: "cancelled",
                metadata: .object(["turnEnd": .bool(true), "reasonKind": .string("stoppedByUser")])),
            ConversationMessage(
                id: "s3", role: "system", content: .string("Something new."), stopReason: "error",
                metadata: .object(["turnEnd": .bool(true), "reasonKind": .string("aKindFromTheFuture")])),
        ])
        #expect(
            transcript.entries == [
                .turnEnd(id: "s1", kind: .failed, text: "The model provider refused the request (HTTP 402).", reason: TurnEndReason(kind: "providerRefused", parameters: ["httpStatus": "402"])),
                .turnEnd(id: "s2", kind: .interruption, text: "Stopped.", reason: TurnEndReason(kind: "stoppedByUser")),
                .turnEnd(id: "s3", kind: .failed, text: "Something new.", reason: TurnEndReason(kind: "aKindFromTheFuture")),
            ])
        guard case .turnEnd(_, _, _, let unknown?) = transcript.entries[2] else { return }
        #expect(!unknown.isKnown)
    }

    @Test func aLiveFailedRunCarriesItsReasonKindAndNotTheOperatorText() {
        var transcript = Transcript()
        transcript.apply(
            ConversationEvent(
                type: "run_error", runId: "run01",
                runError: .init(error: "upstream is down", turnEndReason: "The model provider is not available.", reasonKind: "providerUnavailable")))
        #expect(
            transcript.entries == [.turnEnd(id: "run01:1", kind: .failed, text: "The model provider is not available.", reason: TurnEndReason(kind: "providerUnavailable"))])
    }

    @Test func aDepthNoteReadsLookingCloselyOrThinkingHarder() {
        let transcript = load([
            ConversationMessage(
                id: "d1", role: "system", content: .string("Looking more closely: it is a hard question."),
                metadata: .object(["depthNote": .bool(true), "reasonKind": .string("lookingClosely"), "reasonParameters": .object(["reason": .string("a hard question")])])),
            ConversationMessage(
                id: "d2", role: "system", content: .string("Thinking harder."),
                metadata: .object(["depthNote": .bool(true), "reasonKind": .string("thinkingHarder"), "reasonParameters": .object([:])])),
        ])
        #expect(
            transcript.entries == [
                .note(id: "d1", .depth(.lookingClosely, reason: "a hard question", sentence: "Looking more closely: it is a hard question.")),
                .note(id: "d2", .depth(.thinkingHarder, reason: "", sentence: "Thinking harder.")),
            ])
    }

    @Test func speakFirstShowsANoteAndOffersChoicesUnderTheFirstAnswerOnly() {
        let transcript = load([
            ConversationMessage(id: "m1", role: "user", content: .string("[Speaking first: idea]\nStart with the person's open idea.")),
            ConversationMessage(id: "m2", role: "assistant", content: .string("I have an idea about your morning checks.")),
            ConversationMessage(id: "m3", role: "user", content: .string("Tell me more")),
            ConversationMessage(id: "m4", role: "assistant", content: .string("Sure.")),
        ])
        #expect(
            transcript.entries == [
                .note(id: "m1", .speakFirst(reason: "idea")),
                .assistant(id: "m2", text: "I have an idea about your morning checks.", isStreaming: false),
                .speakFirstChoices(id: "m2", reason: "idea"),
                .user(id: "m3", text: "Tell me more", viewing: nil),
                .assistant(id: "m4", text: "Sure.", isStreaming: false),
            ])
    }

    @Test func aMessageThatOnlyMentionsTheMarkerLaterIsThePersonsOwn() {
        let transcript = load([ConversationMessage(id: "m1", role: "user", content: .string("What does [Speaking first: idea] mean?"))])
        #expect(transcript.entries == [.user(id: "m1", text: "What does [Speaking first: idea] mean?", viewing: nil)])
    }

    @Test func aGoalCheckInIsAMutedNoteThatOpensToItsText() {
        let transcript = load([ConversationMessage(id: "m1", role: "user", content: .string("[Goal check-in: Keep the pick rate up]\nLook at today's numbers."))])
        #expect(transcript.entries == [.note(id: "m1", .goalCheckIn(title: "Keep the pick rate up", message: "Look at today's numbers."))])
    }

    @Test func aBlockedGoalBecomesACardWithItsQuestionAndGoal() {
        let text = "[Goal needs you: Keep the pick rate up]\n\nThe goal \"Keep the pick rate up\" is waiting for you.\n\nShould I stop the night shift reports?\n\nAnswer here and I will pass it on. (goal id: goal42)"
        let transcript = load([ConversationMessage(id: "m1", role: "assistant", content: .string(text), metadata: .object(["goalNeedsYou": .object(["goalId": .string("goal42"), "waitId": .string("wait7")])]))])
        #expect(transcript.entries == [.goalNeedsYou(id: "m1", goalId: "goal42", title: "Keep the pick rate up", question: "Should I stop the night shift reports?")])
        let hintOnly = Transcript.goalNeedsYou(text: text, metadata: nil)
        #expect(hintOnly?.goalId == "goal42")
    }
}


@Suite struct ReplyQuoteTests {
    @Test func aReplyToTheMessageJustAboveItShowsNoQuote() {
        var transcript = Transcript()
        transcript.load(messages: [
            ConversationMessage(id: "m1", role: "assistant", content: .string("Shall I check the alarms?")),
            ConversationMessage(id: "m2", role: "user", content: .string("Yes"), replyToMessageId: "m1", replyToExcerpt: "Shall I check the alarms?", replyToAuthorName: "Assistant"),
            ConversationMessage(id: "m3", role: "assistant", content: .string("Two are open.")),
            ConversationMessage(id: "m4", role: "assistant", content: .string("One more thing.")),
            ConversationMessage(id: "m5", role: "user", content: .string("About the first"), replyToMessageId: "m3", replyToExcerpt: "Two are open.", replyToAuthorName: "Assistant"),
        ], questions: [], approvals: [], isRunning: false)
        #expect(transcript.replyQuote(for: "m2") == nil)
        #expect(transcript.replyQuote(for: "m5")?.messageId == "m3")
    }
}
