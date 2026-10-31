import Foundation
import Testing

@testable import PortalKit

@Suite struct VoiceProtocolTests {
    @Test func theHelloNamesTheSurfaceAndOptionallyTheVoice() throws {
        let hello = try JSONDecoder().decode(JSONValue.self, from: Data(VoiceClientEvent.hello(surface: "ios", speechVoice: nil).encoded().utf8))
        #expect(hello["voiceEvent"]?.stringValue == "hello")
        #expect(hello["surface"]?.stringValue == "ios")
        #expect(hello["speechVoice"] == nil)
        let withVoice = try JSONDecoder().decode(JSONValue.self, from: Data(VoiceClientEvent.hello(surface: "ios", speechVoice: "nova").encoded().utf8))
        #expect(withVoice["speechVoice"]?.stringValue == "nova")
    }

    @Test func speakAndCancelCarryTheirSegmentIDs() throws {
        let speak = try JSONDecoder().decode(JSONValue.self, from: Data(VoiceClientEvent.speakAnswer(answerSegmentId: "a-0", answerText: "Hi.").encoded().utf8))
        #expect(speak["answerSegmentId"]?.stringValue == "a-0")
        #expect(speak["answerText"]?.stringValue == "Hi.")
        let cancel = try JSONDecoder().decode(JSONValue.self, from: Data(VoiceClientEvent.cancelAnswer(answerSegmentIds: ["a-0", "a-1"]).encoded().utf8))
        #expect(cancel["answerSegmentIds"]?.arrayValue?.compactMap(\.stringValue) == ["a-0", "a-1"])
    }

    @Test func serverEventsAreReadByTheirNames() {
        #expect(
            VoiceServerEvent(decoding: #"{"voiceEvent":"ready","sampleRateHertz":24000,"frameDurationMS":100,"isSpeechAvailable":true,"maximumSessionSeconds":1800,"silenceTimeoutSeconds":60}"#)
                == .ready(isSpeechAvailable: true, maximumSessionSeconds: 1800, silenceTimeoutSeconds: 60))
        #expect(VoiceServerEvent(decoding: #"{"voiceEvent":"transcriptFinal","utteranceId":"u1","utteranceSequence":2,"transcriptText":"Hello there"}"#) == .transcriptFinal(utteranceId: "u1", sequence: 2, text: "Hello there"))
        #expect(VoiceServerEvent(decoding: #"{"voiceEvent":"answerAudio","answerSegmentId":"a-0","answerAudioBase64":"AAEC"}"#) == .answerAudio(answerSegmentId: "a-0", pcm: Data([0, 1, 2])))
        #expect(VoiceServerEvent(decoding: #"{"voiceEvent":"nothingWeKnow"}"#) == nil)
        #expect(VoiceServerEvent(decoding: "not json") == nil)
    }

    @Test func aRefusalNamesItsReasonSoNotConfiguredFallsBack() {
        let refused = VoiceServerEvent(decoding: #"{"voiceEvent":"refused","refusalReason":"not_configured","errorMessage":"No streaming transcription."}"#)
        #expect(refused?.refusalReason == .notConfigured)
        #expect(VoiceServerEvent(decoding: #"{"voiceEvent":"error","refusalReason":"session_time_limit","errorMessage":"Time is up."}"#)?.refusalReason == .sessionTimeLimit)
        #expect(VoiceServerEvent(decoding: #"{"voiceEvent":"error","refusalReason":"provider_refused","errorMessage":"x"}"#)?.refusalReason == .providerRefused)
    }

    @Test func theSocketAddressIsSecureAndOnTheVoicePath() throws {
        #expect(try ServerAddress("https://portal.example.test").voiceEndpoint.absoluteString == "wss://portal.example.test/api/v1/agent/voice")
    }

    @Test func aFrameIsOneHundredMillisecondsOf24kHzSixteenBitAudio() {
        #expect(VoiceAudio.bytesPerFrame == VoiceAudio.samplesPerFrame * VoiceAudio.bytesPerSample)
        #expect(VoiceAudio.samplesPerFrame == VoiceAudio.sampleRateHertz * VoiceAudio.frameDurationMS / 1_000)
        #expect(VoiceAudio.bytesPerFrame < VoiceAudio.maximumFrameBytes)
    }
}

@Suite struct VoiceSegmenterTests {
    @Test func theFirstPieceIsOneSentenceAndLaterOnesAreLonger() {
        var segmenter = VoiceAnswerSegmenter(idPrefix: "r1")
        let first = segmenter.feed("Sure. Here is the plan for the morning shift, with the pick stations first and the packing lines after that. Then", isFinal: false)
        #expect(first.first == SpeechPiece(id: "r1-0", text: "Sure."))
        #expect(first.count == 2)
        #expect(first[1].text.hasSuffix("after that."))
        #expect(first[1].text.count >= VoiceAnswerSegmenter.minimumLength)
        let rest = segmenter.feed("Sure. Here is the plan for the morning shift, with the pick stations first and the packing lines after that. Then we check.", isFinal: true)
        #expect(rest == [SpeechPiece(id: "r1-2", text: "Then we check.")])
    }

    @Test func anUnfinishedSentenceWaitsForItsEnd() {
        var segmenter = VoiceAnswerSegmenter()
        #expect(segmenter.feed("Hello th", isFinal: false).isEmpty)
        #expect(segmenter.feed("Hello there", isFinal: false).isEmpty)
        #expect(segmenter.feed("Hello there.", isFinal: false).isEmpty)
        #expect(segmenter.feed("Hello there. ", isFinal: false).map(\.text) == ["Hello there."])
    }

    @Test func codeAndTheSuggestionsCommentAreNotRead() {
        let text = "Run this.\n```sh\nls -la\n```\nThen look at the result.\n<!--suggestions:[\"a\",\"b\"]-->"
        #expect(VoiceAnswerSegmenter.speakableText(text) == "Run this.\nThen look at the result.\n")
        var segmenter = VoiceAnswerSegmenter()
        let pieces = segmenter.feed(text, isFinal: true)
        #expect(pieces.map(\.text).joined(separator: " ").contains("ls") == false)
        #expect(pieces.map(\.text).joined(separator: " ").contains("suggestions") == false)
    }

    @Test func anUnfinishedFenceHidesTheRest() {
        #expect(VoiceAnswerSegmenter.speakableText("Look.\n```python\nprint(1)") == "Look.")
    }

    @Test func markdownMarksAreStripped() {
        #expect(VoiceAnswerSegmenter.speakableText("## Plan\n- **Check** the `queue` and [read the docs](https://example.test/docs).") == "Plan\nCheck the queue and read the docs.")
    }

    @Test func aLongPieceIsSplitUnderTheServersLimit() {
        let long = Array(repeating: "word", count: 2_000).joined(separator: " ")
        let parts = VoiceAnswerSegmenter.splitToFit(long)
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.utf8.count <= VoiceAnswerSegmenter.maximumBytes })
    }
}

@Suite struct VoicePlaybackTests {
    @Test func laterPiecesWaitForEarlierOnes() {
        var queue = VoicePlaybackQueue()
        queue.asked("a-0")
        queue.asked("a-1")
        #expect(queue.received(Data([1]), for: "a-1").isEmpty)
        #expect(queue.received(Data([2]), for: "a-0") == [Data([2])])
        #expect(queue.audioDone("a-0") == [Data([1])])
        #expect(queue.openIds == ["a-1"])
        #expect(queue.audioDone("a-1").isEmpty)
        #expect(queue.openIds.isEmpty)
    }

    @Test func aCancelledPiecesAudioIsIgnored() {
        var queue = VoicePlaybackQueue()
        queue.asked("a-0")
        queue.asked("a-1")
        queue.cancel(["a-1"])
        #expect(queue.received(Data([9]), for: "a-1").isEmpty)
        #expect(queue.openIds == ["a-0"])
        #expect(queue.cancelAll() == ["a-0"])
        #expect(queue.received(Data([3]), for: "a-0").isEmpty)
    }

    @Test func aFailedPieceLetsTheNextOneGoOn() {
        var queue = VoicePlaybackQueue()
        queue.asked("a-0")
        queue.asked("a-1")
        _ = queue.received(Data([5]), for: "a-1")
        #expect(queue.audioFailed("a-0") == [Data([5])])
    }

    @Test func aCompletePieceIsHeardWholeAndACutOneOnlyUpToItsLastWholeWord() {
        var ledger = VoicePlaybackLedger()
        ledger.asked(id: "a-0", text: "Sure, I can do that.")
        ledger.asked(id: "a-1", text: "First check the pick station queue and then the packing lines.")
        ledger.played(id: "a-0", sampleCount: 48_000)
        ledger.audioComplete(id: "a-0", totalSampleCount: 48_000)
        // The second piece got a second of audio of roughly four: about a quarter of its words.
        ledger.played(id: "a-1", sampleCount: 24_000)
        let full = "Sure, I can do that. First check the pick station queue and then the packing lines."
        let split = ledger.split(fullSpeakableText: full)
        #expect(split.heard.hasPrefix("Sure, I can do that."))
        #expect(!split.heard.hasSuffix(" "))
        #expect(full.hasPrefix(split.heard))
        #expect(!split.heard.contains("packing"))
        #expect(split.unheard.hasSuffix("packing lines."))
        #expect(split.heard.count + split.unheard.count <= full.count)
    }

    @Test func nothingPlayedMeansEverythingIsUnheard() {
        var ledger = VoicePlaybackLedger()
        ledger.asked(id: "a-0", text: "Hello there.")
        let split = ledger.split(fullSpeakableText: "Hello there. More to say.")
        #expect(split.heard.isEmpty)
        #expect(split.unheard == "Hello there. More to say.")
    }

    @Test func aPersonIsLouderThanTheEchoButTheEchoItselfIsNot() {
        var judge = InterruptionJudge()
        for _ in 0..<10 { judge.learnEcho(frameLevel: 0.05) }
        #expect(!judge.isPerson(frameLevel: 0.06))
        #expect(judge.isPerson(frameLevel: 0.2))
        #expect(!InterruptionJudge().isPerson(frameLevel: 0.01))
        #expect(InterruptionJudge().isPerson(frameLevel: 0.1))
    }

    @Test func wordsTheAnswerJustSaidAreTheEchoAndNewWordsAreNot() {
        let played = "Check the pick station queue and then the packing lines."
        #expect(InterruptionJudge.isEcho(transcript: "check the pick station queue", justPlayed: played))
        #expect(!InterruptionJudge.isEcho(transcript: "wait stop and show the alarms", justPlayed: played))
        #expect(!InterruptionJudge.isEcho(transcript: "stop", justPlayed: played))
    }

    @Test func theLevelOfSilenceIsZeroAndOfAFullWaveIsHigh() {
        #expect(InterruptionJudge.level(ofPCM: Data(count: 4_800)) == 0)
        var loud = Data()
        for index in 0..<2_400 {
            let sample = Int16(index % 2 == 0 ? 20_000 : -20_000)
            loud.append(UInt8(truncatingIfNeeded: sample))
            loud.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        #expect(InterruptionJudge.level(ofPCM: loud) > 0.5)
    }
}

@Suite struct VoiceFallbackTests {
    static let frame = Data(count: VoiceAudio.bytesPerFrame)

    @Test func anUtteranceStartsAfterSomeLoudFramesAndEndsAfterAPause() {
        var segmenter = UtteranceSegmenter()
        var updates: [UtteranceSegmenter.Update] = []
        for _ in 0..<5 { updates.append(segmenter.feed(frame: Self.frame, level: 0.001)) }
        for _ in 0..<10 { updates.append(segmenter.feed(frame: Self.frame, level: 0.3)) }
        for _ in 0..<segmenter.endFrameCount { updates.append(segmenter.feed(frame: Self.frame, level: 0.001)) }
        #expect(updates.filter { $0 == .speechStarted }.count == 1)
        guard case .utterance(let pcm)? = updates.last else {
            Issue.record("no utterance")
            return
        }
        #expect(pcm.count >= 10 * VoiceAudio.bytesPerFrame)
        #expect(!segmenter.isSpeaking)
    }

    @Test func aBlipIsNotAnUtterance() {
        var segmenter = UtteranceSegmenter()
        var updates: [UtteranceSegmenter.Update] = []
        updates.append(segmenter.feed(frame: Self.frame, level: 0.3))
        for _ in 0..<20 { updates.append(segmenter.feed(frame: Self.frame, level: 0.001)) }
        #expect(updates.allSatisfy { $0 == .nothing })
    }

    @Test func theWaveFileHasItsHeaderAndTheAudio() {
        let wav = WAVFile.encode(pcm: Data([1, 2, 3, 4]))
        #expect(wav.count == 44 + 4)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        #expect(Array(wav.suffix(4)) == [1, 2, 3, 4])
    }

    @Test func transcribingPostsAMultipartFileAndReadsTheText() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["text": "show me the alarms"])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        let text = try await connection.transcribe(wav: WAVFile.encode(pcm: Data([0, 0])))
        #expect(text == "show me the alarms")
        let request = try #require(transport.requests.last)
        #expect(request.url?.path == "/api/v1/voice/transcribe")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }

    @Test func speakingParksTheTextAndClaimsTheAudioWithTheToken() async throws {
        let transport = ScriptedTransport { request in
            if request.url?.path == "/api/v1/voice/synthesize" { return (200, ScriptedTransport.json(["token": "tok1"])) }
            return (200, Data([7, 7, 7]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        let audio = try await connection.synthesize(text: "Hello.", voice: "nova")
        #expect(audio == Data([7, 7, 7]))
        let claim = try #require(transport.requests.last)
        #expect(claim.url?.path == "/api/v1/voice/stream")
        #expect(claim.url?.query == "token=tok1")
        #expect(claim.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aSpokenMessageCarriesTheVoiceFlagAndWhatWasHeard() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SendMessage": ["runId": "run1"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        _ = try await connection.sendMessage(
            conversationId: "c1", text: "Stop, show alarms", isVoice: true,
            interruptedAnswer: InterruptedAnswer(heardText: "First check", unheardText: "the queue."))
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["voice"] as? Bool == true)
        #expect(variables["surface"] as? String == "ios")
        let interrupted = variables["interruptedAnswer"] as? [String: Any]
        #expect(interrupted?["heardText"] as? String == "First check")
        #expect(interrupted?["unheardText"] as? String == "the queue.")
    }
}
