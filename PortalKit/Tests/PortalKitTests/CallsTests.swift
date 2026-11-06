import Foundation
import Testing

@testable import PortalKit

@Suite struct VoiceMessageTests {
    @Test func aRecordingUnderHalfASecondSendsNothing() {
        #expect(VoiceMessageRules.isTooShort(0.49))
        #expect(!VoiceMessageRules.isTooShort(0.5))
    }

    @Test func theCountdownStartsAtOneFiftyAndSendsAtTwoMinutes() {
        #expect(VoiceMessageRules.countdownSecondsLeft(elapsed: 109.9) == nil)
        #expect(VoiceMessageRules.countdownSecondsLeft(elapsed: 110) == 10)
        #expect(VoiceMessageRules.countdownSecondsLeft(elapsed: 118.2) == 2)
        #expect(!VoiceMessageRules.isAtLimit(119.9))
        #expect(VoiceMessageRules.isAtLimit(120))
    }

    @Test func slidingUpEightyPointsCancels() {
        #expect(!VoiceMessageRules.isCancelling(upward: 79))
        #expect(VoiceMessageRules.isCancelling(upward: 80))
    }

    @Test func theLevelsAreFortyEightValuesFromZeroToTwoFiftyFive() {
        let amplitudes = (0..<480).map { Float($0 % 100) / 100 }
        let levels = VoiceMessageRules.levels(fromAmplitudes: amplitudes)
        #expect(levels.count == 48)
        #expect(VoiceMessageRules.areValid(levels))
        #expect(levels.max() == 255)
    }

    @Test func aQuietRecordingIsNotMadeToLookLoud() {
        let levels = VoiceMessageRules.levels(fromAmplitudes: Array(repeating: 0.05, count: 96))
        #expect(levels.allSatisfy { $0 < 64 })
        #expect(VoiceMessageRules.levels(fromAmplitudes: []) == Array(repeating: 0, count: 48))
    }

    @Test func aShortRecordingStillFillsAllTheBars() {
        let levels = VoiceMessageRules.levels(fromAmplitudes: [0.2, 0.9, 0.4])
        #expect(levels.count == 48)
        #expect(levels.max() == 255)
    }

    @Test func decibelsBecomeAHeightAndSilenceIsFlat() {
        #expect(VoiceMessageRules.amplitude(decibels: -160) == 0)
        #expect(VoiceMessageRules.amplitude(decibels: 0) == 1)
        #expect(VoiceMessageRules.amplitude(decibels: -25) == 0.5)
        #expect(VoiceMessageRules.amplitude(decibels: -.infinity) == 0)
    }

    @Test func levelsOutsideTheBoundsAreNotValid() {
        #expect(!VoiceMessageRules.areValid(Array(repeating: 10, count: 47)))
        #expect(!VoiceMessageRules.areValid(Array(repeating: 256, count: 48)))
        #expect(!VoiceMessageRules.areValid(Array(repeating: -1, count: 48)))
    }

    @Test func clocksShowMinutesAndSeconds() {
        #expect(VoiceMessageRules.clockText(0) == "0:00")
        #expect(VoiceMessageRules.clockText(65.9) == "1:05")
        #expect(VoiceMessageRules.timeLeftText(duration: 30, position: 12.2) == "0:18")
        #expect(VoiceMessageRules.timeLeftText(duration: 30, position: 40) == "0:00")
    }

    @Test func theWaveformPlaysAndSeeksByFraction() {
        #expect(VoiceMessageRules.playedBarCount(progress: 0.5) == 24)
        #expect(VoiceMessageRules.playedBarCount(progress: 2) == 48)
        #expect(VoiceMessageRules.seekPosition(fraction: 0.25, duration: 40) == 10)
        #expect(VoiceMessageRules.seekPosition(fraction: -1, duration: 40) == 0)
    }

    @Test func aBrowserRecordingTheyPhoneCannotPlayIsRecognized() {
        #expect(!VoiceMessageRules.canPlayOnPhone(contentType: "audio/webm;codecs=opus", filename: "voice.webm"))
        #expect(!VoiceMessageRules.canPlayOnPhone(contentType: nil, filename: "voice.OGG"))
        #expect(VoiceMessageRules.canPlayOnPhone(contentType: "audio/mp4", filename: "voice.m4a"))
    }

    @Test func theTranscriptIsWaitingThenWordsOrFailed() {
        #expect(VoiceMessage(transcriptState: "waiting").transcriptStatus == .waiting)
        #expect(VoiceMessage(transcriptText: "Hello there", transcriptState: "done").transcriptStatus == .text("Hello there"))
        #expect(VoiceMessage(transcriptState: "failed").transcriptStatus == .failed)
        #expect(VoiceMessage(transcriptText: "  ", transcriptState: "done").transcriptStatus == .failed)
        #expect(VoiceMessage(transcriptState: "off").transcriptStatus == .failed)
    }

    @Test func aMessageWithoutLevelsGetsAFlatLine() {
        #expect(VoiceMessage().levels.count == 48)
    }

    @Test func playedMessagesAreRememberedUpToACapacity() {
        var played = PlayedVoiceMessages()
        played.markPlayed("m1")
        played.markPlayed("m1")
        #expect(played.messageIds == ["m1"])
        for index in 0..<PlayedVoiceMessages.capacity + 5 { played.markPlayed("x\(index)") }
        #expect(played.messageIds.count == PlayedVoiceMessages.capacity)
        #expect(!played.hasPlayed("m1"))
        #expect(played.hasPlayed("x\(PlayedVoiceMessages.capacity + 4)"))
    }

    @Test func aVoiceMessageComesThroughAChatMessage() throws {
        let json = """
            {"id":"m1","role":"user","content":"","isChatMessage":true,"authorUserId":"user02",
             "voiceMessage":{"attachmentId":"a1","durationMS":4200,"waveformLevels":[1,2,3],"transcriptState":"waiting"}}
            """
        let row = try JSONDecoder().decode(ConversationMessage.self, from: Data(json.utf8))
        let message = ChatMessage(row)
        #expect(message.isVoiceMessage)
        #expect(message.voice?.duration == 4.2)
        #expect(message.voice?.transcriptStatus == .waiting)
    }

    @Test func aServerWithoutVoiceMessagesStillDecodesMessages() throws {
        let row = try JSONDecoder().decode(ConversationMessage.self, from: Data(#"{"id":"m1","role":"user","content":"Hi"}"#.utf8))
        #expect(!ChatMessage(row).isVoiceMessage && !ChatMessage(row).isCallLine)
    }

    @Test func voiceFieldsAreAskedForOnlyWhereAMessageIsAsked() {
        let base = Documents.listMessages
        let withMedia = Documents.withChatMedia(base)
        #expect(!base.contains("call {") && !base.contains("voiceMessage {"))
        #expect(withMedia.contains("call {") && withMedia.contains("voiceMessage {"))
        #expect(!Documents.withChatMedia(base, hasVoice: false, hasCalls: true).contains("voiceMessage {"))
        #expect(Documents.withChatMedia(base, hasVoice: false, hasCalls: false) == base)
        #expect(Documents.withChatMedia(Documents.me) == Documents.me)
    }
}

@Suite struct ChatCallTests {
    func call(
        _ id: String = "call1", chatId: String = "chat1", endedAt: String? = nil, endReason: String? = nil, members: [ChatCallMember] = []
    ) -> ChatCall {
        ChatCall(
            id: id, chatId: chatId, startedByUserId: "user02", startedByUserName: "Sam Sample", startedAt: "2026-03-01T10:00:00Z", endedAt: endedAt,
            endReason: endReason, members: members)
    }

    let ringingMe = ChatCallMember(userId: "user01", userName: "Alex Example", ringState: "ringing", isInCall: false)
    let starter = ChatCallMember(userId: "user02", userName: "Sam Sample", ringState: "none", isInCall: true)

    @Test func aCallIsGoingUntilItHasAnEnd() {
        #expect(call().isGoing)
        #expect(!call(endedAt: "2026-03-01T10:05:00Z", endReason: "ended").isGoing)
    }

    @Test func aRingForThePersonIsReportedOnceAndStopsWhenAnswered() {
        var book = ChatCallBook()
        let ringing = ChatCallEvent(eventType: "joined", call: call(members: [starter, ringingMe]))
        #expect(book.apply(ringing, userId: "user01") == .ringing(call(members: [starter, ringingMe])))
        #expect(book.apply(ringing, userId: "user01") == .none)
        let answered = ChatCallMember(userId: "user01", userName: "Alex Example", ringState: "answered", isInCall: true)
        #expect(book.apply(ChatCallEvent(eventType: "joined", call: call(members: [starter, answered])), userId: "user01") == .stopped(callId: "call1"))
        #expect(book.goingCall(inChat: "chat1")?.id == "call1")
    }

    @Test func anEndedCallLeavesTheBookAndStopsARing() {
        var book = ChatCallBook()
        _ = book.apply(ChatCallEvent(eventType: "joined", call: call(members: [starter, ringingMe])), userId: "user01")
        let ended = call(endedAt: "2026-03-01T10:01:00Z", endReason: "missed", members: [starter, ringingMe])
        #expect(book.apply(ChatCallEvent(eventType: "ended", call: ended), userId: "user01") == .stopped(callId: "call1"))
        #expect(book.goingCall(inChat: "chat1") == nil)
    }

    @Test func aStopRingingEventStopsTheRing() {
        var book = ChatCallBook()
        #expect(book.apply(ChatCallEvent(eventType: "stop_ringing", callId: "call1"), userId: "user01") == .stopped(callId: "call1"))
    }

    @Test func anEventWithoutTheCallAsksForARead() {
        var book = ChatCallBook()
        #expect(book.apply(ChatCallEvent(eventType: "joined", callId: "call9"), userId: "user01") == .refetch(callId: "call9"))
        #expect(book.apply(ChatCallEvent(eventType: "joined"), userId: "user01") == .none)
    }

    @Test func theBookKeepsOnlyGoingCalls() {
        var book = ChatCallBook()
        book.replaceAll([call("a"), call("b", chatId: "chat2", endedAt: "2026-03-01T10:05:00Z", endReason: "ended")])
        #expect(book.goingCalls.keys.sorted() == ["a"])
        #expect(book.goingCall(inChat: "chat2") == nil)
        #expect(book.goingCall(inChat: nil) == nil)
    }

    @Test func thePeopleToRingAreThoseNotOnTheCallOrRinging() {
        let members = [
            ChatMember(id: "m1", userId: "user01"), ChatMember(id: "m2", userId: "user02"), ChatMember(id: "m3", userId: "user03"),
            ChatMember(id: "m4", userId: "user04"), ChatMember(id: "m5", userId: "user05", leftAt: "2026-01-01T00:00:00Z"),
        ]
        let current = call(members: [starter, ChatCallMember(userId: "user03", ringState: "ringing", isInCall: false)])
        #expect(current.membersToRing(among: members, excluding: "user01").map(\.userId) == ["user04"])
    }

    @Test func theLineOfAnEndedCallSaysHowItEnded() {
        #expect(ChatCallRules.outcome(of: call()) == .going)
        #expect(ChatCallRules.outcome(of: call(endedAt: "2026-03-01T10:05:00Z", endReason: "missed")) == .missed)
        #expect(ChatCallRules.outcome(of: call(endedAt: "2026-03-01T10:05:00Z", endReason: "declined")) == .declined)
        #expect(ChatCallRules.outcome(of: call(endedAt: "2026-03-01T10:05:00Z", endReason: "ended")) == .ended(duration: 300))
        #expect(ChatCallRules.outcome(of: call(endedAt: "2026-03-01T10:05:00Z", endReason: "failed")) == .failed)
    }

    @Test func theElapsedClockCountsMinutesThenHours() {
        #expect(ChatCallRules.elapsedText(0) == "0:00")
        #expect(ChatCallRules.elapsedText(75) == "1:15")
        #expect(ChatCallRules.elapsedText(3_725) == "1:02:05")
    }

    @Test func aChatWithOnlyThePersonCannotStartACall() {
        let alone = ChatRoom(id: "chat1", isReaderMember: true, members: [ChatMember(id: "m1", userId: "user01")])
        let together = ChatRoom(id: "chat1", isReaderMember: true, members: [ChatMember(id: "m1", userId: "user01"), ChatMember(id: "m2", userId: "user02")])
        #expect(!ChatCallRules.canStart(in: alone, userId: "user01"))
        #expect(ChatCallRules.canStart(in: together, userId: "user01"))
        #expect(!ChatCallRules.canStart(in: nil, userId: "user01"))
    }

    @Test func aDroppedCallTriesSoonThenLessOftenAndGivesUpAfterAMinute() {
        #expect((1...6).map(CallReconnectPlan.delay(afterFailedAttempts:)) == [1, 2, 4, 8, 8, 8])
        #expect(!CallReconnectPlan.shouldGiveUp(elapsed: 59))
        #expect(CallReconnectPlan.shouldGiveUp(elapsed: 60))
    }

    @Test func aCallThatIsOverSaysWhereItsTranscriptIs() {
        let ended = "2026-03-01T10:04:32Z"
        #expect(ChatCall(id: "c", endedAt: ended, transcriptState: "done").transcriptStatus == .ready)
        #expect(ChatCall(id: "c", endedAt: ended, transcriptState: "waiting").transcriptStatus == .transcribing)
        #expect(ChatCall(id: "c", endedAt: ended, transcriptState: "recording").transcriptStatus == .transcribing)
        #expect(ChatCall(id: "c", endedAt: ended, transcriptState: "failed").transcriptStatus == .failed)
        #expect(ChatCall(id: "c", endedAt: ended, transcriptState: "off").transcriptStatus == .none)
        #expect(ChatCall(id: "c", transcriptState: "recording").transcriptStatus == .none)
    }

    /// A call in a chat's history comes without its words, so the transcript is offered from its state alone.
    @Test func aCallFromTheHistoryOffersATranscriptItDoesNotHoldYet() {
        let call = ChatCall(id: "c", endedAt: "2026-03-01T10:04:32Z", transcriptState: "done")
        #expect(call.spokenSegments().isEmpty)
        #expect(call.transcriptStatus == .ready)
    }

    @Test func theCallDetailAsksForTheRecordings() {
        #expect(Documents.getChatCall.contains("recordingAttachments { id filename uploadedByUserId }"))
        #expect(!Documents.chatCallLineFields.contains("recordingAttachments"))
    }

    @Test func theTranscriptLeavesOutEmptySegments() {
        let withSegments = ChatCall(id: "c", transcriptSegments: [ChatCallSegment(text: "Hello"), ChatCallSegment(text: "  "), ChatCallSegment(text: nil)])
        #expect(withSegments.spokenSegments().count == 1)
    }

    @Test func aCallEventDecodesFromTheFeed() throws {
        let json = #"{"eventType":"joined","callId":"call1","chatId":"chat1","actorUserName":"Sam","call":{"id":"call1","members":[{"userId":"user01","ringState":"ringing"}]}}"#
        let event = try JSONDecoder().decode(ChatCallEvent.self, from: Data(json.utf8))
        #expect(event.resolvedCallId == "call1")
        #expect(event.call?.member("user01")?.isRinging == true)
    }

    @Test func theCapabilitiesSayWhatTheServerOffers() {
        let none = ServerCapabilities()
        #expect(!none.offersChatCalls && !none.offersVoiceMessages && !none.offersChatMedia)
        let voice = ServerCapabilities(sendMessageArgumentNames: ["voiceMessage"])
        #expect(voice.offersVoiceMessages && voice.offersChatMedia && !voice.offersChatCalls)
        let calls = ServerCapabilities(
            mutationNames: ["StartChatCall", "JoinChatCallMedia"], subscriptionNames: ["OnChatCallEvent", "OnChatCallSignal"])
        #expect(calls.offersChatCalls && calls.offersChatMedia)
    }
}

@Suite struct CallSignalQueueTests {
    actor Recorder {
        var seen: [String] = []
        var active = 0
        var overlapped = false
        func begin(_ sdp: String) async {
            active += 1
            if active > 1 { overlapped = true }
            try? await Task.sleep(nanoseconds: 2_000_000)
            seen.append(sdp)
            active -= 1
        }
    }

    @Test func offersWaitForTheJoinAndThenRunInOrderOneAtATime() async {
        let recorder = Recorder()
        let queue = CallSignalQueue { signal in await recorder.begin(signal.offerSdp ?? "") }
        await queue.receive(ChatCallSignal(offerSdp: "one"))
        await queue.receive(ChatCallSignal(offerSdp: "two"))
        #expect(await recorder.seen.isEmpty)
        #expect(await queue.pendingCount == 2)
        await queue.joinCompleted()
        async let third: Void = queue.receive(ChatCallSignal(offerSdp: "three"))
        async let fourth: Void = queue.receive(ChatCallSignal(offerSdp: "four"))
        _ = await (third, fourth)
        let seen = await recorder.seen
        #expect(Array(seen.prefix(2)) == ["one", "two"])
        #expect(Set(seen) == ["one", "two", "three", "four"])
        #expect(await recorder.overlapped == false)
    }

    @Test func resetForgetsWhatWaited() async {
        let recorder = Recorder()
        let queue = CallSignalQueue { signal in await recorder.begin(signal.offerSdp ?? "") }
        await queue.receive(ChatCallSignal(offerSdp: "old"))
        await queue.reset()
        await queue.joinCompleted()
        #expect(await recorder.seen.isEmpty)
    }
}

@Suite struct VoipPushTests {
    @Test func aRingingPushNamesTheCallAndTheCaller() {
        let payload = VoipPushPayload(userInfo: [
            "portal": ["kind": "chat_call", "userId": "user01", "callId": "call1", "chatId": "chat1", "callerName": "Sam Sample", "isVideo": true]
        ])
        #expect(payload?.kind == .ringing)
        #expect(payload?.callId == "call1")
        #expect(payload?.shownName == "Sam Sample")
        #expect(payload?.isVideoOn == true)
    }

    @Test func aStopPushIsRecognizedAndAnotherKindIsNot() {
        #expect(VoipPushPayload(userInfo: ["portal": ["kind": "chat_call_stop", "userId": "u", "callId": "c"]])?.kind == .stopped)
        #expect(VoipPushPayload(userInfo: ["portal": ["kind": "chat_message", "userId": "u", "callId": "c"]]) == nil)
        #expect(VoipPushPayload(userInfo: ["portal": ["kind": "chat_call", "userId": "u"]]) == nil)
    }

    @Test func theChatNameStandsInForAMissingCaller() {
        let payload = VoipPushPayload(kind: .ringing, userId: "u", callId: "c", chatName: "Pick station team")
        #expect(payload.shownName == "Pick station team")
        #expect(VoipPushPayload(kind: .ringing, userId: "u", callId: "c").shownName == "Portal")
    }

    @Test func aCallAlertOpensTheChat() {
        let payload = PushPayload(userId: "u", kind: "chat_call", conversationId: "conv1")
        #expect(payload.route == .chat(conversationId: "conv1"))
    }

    @Test func thePushDeviceIdIsKeptPerAccount() {
        let defaults = UserDefaults(suiteName: "push-device-test")!
        defaults.removePersistentDomain(forName: "push-device-test")
        PushDeviceIdentity.store("device1", accountKey: "a", in: defaults)
        #expect(PushDeviceIdentity.stored(accountKey: "a", in: defaults) == "device1")
        #expect(PushDeviceIdentity.stored(accountKey: "b", in: defaults) == nil)
    }

    @Test func theVoipTokenIsStoredAsHex() {
        let defaults = UserDefaults(suiteName: "voip-token-test")!
        defaults.removePersistentDomain(forName: "voip-token-test")
        #expect(VoipDeviceToken.stored(in: defaults) == nil)
        VoipDeviceToken.store(Data([0xde, 0xad]), in: defaults)
        #expect(VoipDeviceToken.stored(in: defaults) == "dead")
    }
}
