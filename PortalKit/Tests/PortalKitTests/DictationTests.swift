import Foundation
import Testing

@testable import PortalKit

@Suite struct DictationProtocolTests {
    @Test func theHelloAsksForDictationInThePlaceTheWordsGo() throws {
        let agent = try JSONDecoder().decode(JSONValue.self, from: Data(VoiceClientEvent.dictationHello(place: .agent).encoded().utf8))
        #expect(agent["voiceEvent"]?.stringValue == "hello")
        #expect(agent["surface"]?.stringValue == "ios")
        #expect(agent["purpose"]?.stringValue == "dictation")
        #expect(agent["dictationPlace"]?.stringValue == "agent")
        let chat = try JSONDecoder().decode(JSONValue.self, from: Data(VoiceClientEvent.dictationHello(place: .chat).encoded().utf8))
        #expect(chat["dictationPlace"]?.stringValue == "chat")
    }

    @Test func aCallHelloStaysACall() throws {
        let hello = try JSONDecoder().decode(JSONValue.self, from: Data(VoiceClientEvent.hello(surface: "ios", speechVoice: nil).encoded().utf8))
        #expect(hello["purpose"] == nil)
        #expect(hello["dictationPlace"] == nil)
    }

    @Test func theReadyEventNamesTheAudioFormat() {
        let ready = VoiceServerEvent(decoding: #"{"voiceEvent":"ready","sampleRateHertz":16000,"frameDurationMS":40}"#)
        #expect(ready == .ready(isSpeechAvailable: false, maximumSessionSeconds: 0, silenceTimeoutSeconds: 0, sampleRateHertz: 16_000, frameDurationMS: 40))
    }

    @Test func theWordsAndTheErrorsAreReadByTheirNames() {
        #expect(
            VoiceServerEvent(decoding: #"{"voiceEvent":"transcriptDelta","utteranceId":"u1","transcriptText":"check the"}"#)
                == .transcriptDelta(utteranceId: "u1", text: "check the"))
        #expect(
            VoiceServerEvent(decoding: #"{"voiceEvent":"transcriptFinal","utteranceId":"u1","utteranceSequence":1,"transcriptText":"check the dock"}"#)
                == .transcriptFinal(utteranceId: "u1", sequence: 1, text: "check the dock"))
        #expect(
            VoiceServerEvent(decoding: #"{"voiceEvent":"refused","refusalReason":"billing","errorMessage":"The limit is reached."}"#)
                == .refused(reason: "billing", message: "The limit is reached."))
        #expect(
            VoiceServerEvent(decoding: #"{"voiceEvent":"error","errorMessage":"Transcription stopped."}"#)
                == .error(reason: "", message: "Transcription stopped."))
    }
}

@Suite struct DictationTextTests {
    @Test func heardWordsGoAtTheEndWithASpaceBetween() {
        #expect(DictationText.appending("check the dock", to: "Please") == "Please check the dock")
        #expect(DictationText.appending("check the dock", to: "") == "check the dock")
        #expect(DictationText.appending("  check the dock \n", to: "") == "check the dock")
    }

    @Test func aBoxThatEndsInWhiteSpaceGetsNoSecondOne() {
        #expect(DictationText.appending("check", to: "Please ") == "Please check")
        #expect(DictationText.appending("check", to: "Line one\n") == "Line one\ncheck")
    }

    @Test func wordsThatAreOnlyWhiteSpaceChangeNothing() {
        #expect(DictationText.appending("   ", to: "Please") == "Please")
        #expect(DictationText.appending("", to: "") == "")
    }

    @Test func eachFinalTranscriptFollowsTheLast() {
        var box = "Hello"
        for words in ["can you", "check the dock", "schedule"] { box = DictationText.appending(words, to: box) }
        #expect(box == "Hello can you check the dock schedule")
    }
}

@Suite struct DictationFormatTests {
    @Test func theStandardFormatIsTheCallsFrame() {
        #expect(DictationFormat.standard.bytesPerFrame == VoiceAudio.bytesPerFrame)
    }

    @Test func aFormatTheServerNamesIsUsedWhenItIsSane() {
        let format = DictationFormat.named(sampleRateHertz: 16_000, frameDurationMS: 40)
        #expect(format == DictationFormat(sampleRateHertz: 16_000, frameDurationMS: 40))
        #expect(format.bytesPerFrame == 1_280)
    }

    @Test func aFormatThatIsMissingOrAbsurdFallsBackToTheStandardOne() {
        #expect(DictationFormat.named(sampleRateHertz: 0, frameDurationMS: 0) == .standard)
        #expect(DictationFormat.named(sampleRateHertz: 24_000, frameDurationMS: 5_000) == .standard)
        #expect(DictationFormat.named(sampleRateHertz: 1_000_000, frameDurationMS: 100) == .standard)
    }
}

@Suite struct DictationTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func event(_ text: String) -> VoiceServerEvent { VoiceServerEvent(decoding: text)! }

    @Test func theCaptionGrowsWithEachDeltaAndEndsAtTheFinalTranscript() {
        var tracker = DictationTracker(startedAt: start)
        #expect(tracker.accept(event(#"{"voiceEvent":"speechStarted","utteranceId":"one"}"#), at: start).captionText == "")
        #expect(tracker.accept(event(#"{"voiceEvent":"transcriptDelta","utteranceId":"one","transcriptText":"what is "}"#), at: start).captionText == "what is ")
        #expect(tracker.accept(event(#"{"voiceEvent":"transcriptDelta","utteranceId":"one","transcriptText":"open"}"#), at: start).captionText == "what is open")
        let final = tracker.accept(event(#"{"voiceEvent":"transcriptFinal","utteranceId":"one","transcriptText":" what is open "}"#), at: start)
        #expect(final == DictationTracker.Update(captionText: "", transcriptText: "what is open"))
    }

    @Test func aFinalTranscriptGoesThroughOnceWhateverTheSocketRepeats() {
        var tracker = DictationTracker(startedAt: start)
        let final = event(#"{"voiceEvent":"transcriptFinal","utteranceId":"one","transcriptText":"hello"}"#)
        #expect(tracker.accept(final, at: start).transcriptText == "hello")
        #expect(tracker.accept(final, at: start) == DictationTracker.Update())
        #expect(tracker.accept(event(#"{"voiceEvent":"transcriptDelta","utteranceId":"one","transcriptText":"late"}"#), at: start).captionText == nil)
    }

    @Test func theCaptionOfTheUtteranceStillBeingHeardSurvivesAnEarlierOnesEnd() {
        var tracker = DictationTracker(startedAt: start)
        _ = tracker.accept(event(#"{"voiceEvent":"speechStarted","utteranceId":"one"}"#), at: start)
        _ = tracker.accept(event(#"{"voiceEvent":"speechStarted","utteranceId":"two"}"#), at: start)
        _ = tracker.accept(event(#"{"voiceEvent":"transcriptDelta","utteranceId":"two","transcriptText":"and on"}"#), at: start)
        let update = tracker.accept(event(#"{"voiceEvent":"transcriptFinal","utteranceId":"one","transcriptText":"first"}"#), at: start)
        #expect(update == DictationTracker.Update(captionText: "and on", transcriptText: "first"))
    }

    @Test func aFailedUtteranceIsNotHeardAndPutsNothingInTheBox() {
        var tracker = DictationTracker(startedAt: start)
        let update = tracker.accept(event(#"{"voiceEvent":"transcriptFailed","utteranceId":"one","errorMessage":"x"}"#), at: start)
        #expect(update == DictationTracker.Update(captionText: "", isNotHeard: true))
    }

    @Test func anUtteranceOfSilenceSendsNothing() {
        var tracker = DictationTracker(startedAt: start)
        _ = tracker.accept(event(#"{"voiceEvent":"speechStarted","utteranceId":"one"}"#), at: start)
        let update = tracker.accept(event(#"{"voiceEvent":"transcriptFinal","utteranceId":"one","transcriptText":"  "}"#), at: start)
        #expect(update == DictationTracker.Update(captionText: ""))
    }

    @Test func speechIsPendingFromItsStartToItsFinalTranscript() {
        var tracker = DictationTracker(startedAt: start)
        #expect(!tracker.isSpeechPending)
        _ = tracker.accept(event(#"{"voiceEvent":"speechStarted","utteranceId":"one"}"#), at: start)
        #expect(tracker.isSpeechPending)
        _ = tracker.accept(event(#"{"voiceEvent":"transcriptFinal","utteranceId":"one","transcriptText":"ok"}"#), at: start)
        #expect(!tracker.isSpeechPending)
    }

    @Test func dictationIsSilentAfterThirtySecondsWithNoWords() {
        var tracker = DictationTracker(startedAt: start)
        #expect(!tracker.isSilent(at: start.addingTimeInterval(29)))
        #expect(!tracker.isSilent(at: start.addingTimeInterval(30)))
        #expect(tracker.isSilent(at: start.addingTimeInterval(31)))
        _ = tracker.accept(event(#"{"voiceEvent":"transcriptDelta","utteranceId":"one","transcriptText":"hi"}"#), at: start.addingTimeInterval(25))
        #expect(!tracker.isSilent(at: start.addingTimeInterval(54)))
        #expect(tracker.isSilent(at: start.addingTimeInterval(56)))
    }

    @Test func speechStillBeingTranscribedIsNotSilence() {
        var tracker = DictationTracker(startedAt: start)
        _ = tracker.accept(event(#"{"voiceEvent":"speechStarted","utteranceId":"one"}"#), at: start)
        #expect(!tracker.isSilent(at: start.addingTimeInterval(120)))
    }

    @Test func stopWaitsAboutASecondWhenQuietAndAtMostThreeWhenSpeechIsOpen() {
        #expect(DictationTiming.stopWaitSeconds(isSpeechPending: false) == 1)
        #expect(DictationTiming.stopWaitSeconds(isSpeechPending: true) == 3)
    }

    @Test func theLimitsAreThirtySecondsOfSilenceAndAFewSecondsForTheLastWords() {
        #expect(DictationTiming.silenceLimitSeconds == 30)
        #expect(DictationTiming.finalWordsLimitSeconds > 0 && DictationTiming.finalWordsLimitSeconds <= 5)
    }
}

@Suite struct VoiceAvailabilityTests {
    @Test func theCapabilitiesReadTheFieldsOfTheVoiceSetting() async {
        let (connection, transport) = scriptedConnection { _, _ in
            [
                "__schema": ["queryType": ["fields": [["name": "getAgentVoiceSetting", "args": []]]], "mutationType": NSNull(), "subscriptionType": NSNull()],
                "voiceSetting": ["fields": [["name": "speechVoice"], ["name": "isReadAloudAvailable"]]],
            ]
        }
        let capabilities = await connection.capabilities()
        #expect(capabilities.offersReadAloudAvailability)
        #expect(!capabilities.offersDictationAvailability)
        let body = String(decoding: transport.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("AgentVoiceSetting"))
    }

    @Test func anOlderServerHasNoVoiceSettingFieldsToAskFor() async {
        let (connection, _) = scriptedConnection { _, _ in
            ["__schema": ["queryType": ["fields": []], "mutationType": NSNull(), "subscriptionType": NSNull()], "voiceSetting": NSNull()]
        }
        let capabilities = await connection.capabilities()
        #expect(!capabilities.offersReadAloudAvailability)
        #expect(!capabilities.offersDictationAvailability)
        let (olderConnection, _) = scriptedConnection { _, _ in
            ["__schema": ["queryType": ["fields": []], "mutationType": NSNull(), "subscriptionType": NSNull()]]
        }
        #expect(await olderConnection.capabilities() == ServerCapabilities())
    }

    @Test func aServerWithoutTheFieldsIsNotAskedForThem() async {
        let (connection, transport) = scriptedConnection { _, _ in [:] }
        let capabilities = ServerCapabilities(queryNames: ["GetAgentVoiceSetting"], voiceSettingFieldNames: ["speechVoice", "speechVoices"])
        let availability = await connection.voiceAvailability(capabilities: capabilities)
        #expect(availability == .unavailable)
        #expect(!availability.isDictationAvailable)
        #expect(!availability.isReadAloudAvailable)
        #expect(transport.requests.isEmpty)
    }

    @Test func onlyTheFieldsTheSchemaHasAreAskedFor() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            operation == "GetAgentVoiceSetting" ? ["GetAgentVoiceSetting": ["isDictationAvailable": true]] : [:]
        }
        let capabilities = ServerCapabilities(voiceSettingFieldNames: ["isDictationAvailable"])
        let availability = await connection.voiceAvailability(capabilities: capabilities)
        #expect(availability == VoiceAvailability(isDictationAvailable: true, isReadAloudAvailable: false))
        let body = String(decoding: try #require(transport.requests.first?.httpBody), as: UTF8.self)
        #expect(body.contains("isDictationAvailable"))
        #expect(!body.contains("isReadAloudAvailable"))
    }

    @Test func bothFieldsAreAskedForWhenTheSchemaHasBoth() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["GetAgentVoiceSetting": ["isDictationAvailable": false, "isReadAloudAvailable": true]]
        }
        let capabilities = ServerCapabilities(voiceSettingFieldNames: ["isDictationAvailable", "isReadAloudAvailable"])
        let availability = await connection.voiceAvailability(capabilities: capabilities)
        #expect(availability == VoiceAvailability(isDictationAvailable: false, isReadAloudAvailable: true))
        let body = String(decoding: try #require(transport.requests.first?.httpBody), as: UTF8.self)
        #expect(body.contains("isDictationAvailable isReadAloudAvailable"))
    }

    @Test func aFailedAskLeavesBothUnavailable() async {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["errors": [["message": "not allowed"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        let capabilities = ServerCapabilities(voiceSettingFieldNames: ["isDictationAvailable", "isReadAloudAvailable"])
        #expect(await connection.voiceAvailability(capabilities: capabilities) == .unavailable)
    }
}

@Suite struct SpeechRefusalTests {
    private func refusal(status: Int, body: Data = Data()) async -> PortalError? {
        let transport = ScriptedTransport { _ in (status, body) }
        let connection = Connection(account: makeAccount(), transport: transport)
        do {
            _ = try await connection.synthesize(text: "Hello.", voice: nil)
            return nil
        } catch {
            return error as? PortalError
        }
    }

    @Test func aBillingLimitIsSaidInWords() async {
        #expect(await refusal(status: 402) == PortalError.refused("The limit for spoken messages has been reached."))
    }

    @Test func noSpeechProviderIsSaidInWords() async {
        #expect(await refusal(status: 404) == PortalError.refused("No speech provider is set up."))
    }

    @Test func theMessageInsideTheErrorObjectIsShownForA403() async {
        let body = ScriptedTransport.json(["error": ["message": "Your plan has no spoken messages."]])
        #expect(await refusal(status: 403, body: body) == PortalError.refused("Your plan has no spoken messages."))
    }

    @Test func aBare403SaysTheLimitNotTheStatus() async {
        #expect(await refusal(status: 403) == PortalError.refused("The limit for spoken messages has been reached."))
    }

    @Test func theServersOwnReasonComesFirst() async {
        #expect(await refusal(status: 402, body: ScriptedTransport.json(["message": "Your plan has no spoken messages."])) == PortalError.refused("Your plan has no spoken messages."))
    }

    @Test func noVoiceIsSentSoTheServerUsesThePersonsChoice() async throws {
        let transport = ScriptedTransport { request in
            request.url?.path == "/api/v1/voice/synthesize" ? (200, ScriptedTransport.json(["token": "tok1"])) : (200, Data([1]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        _ = try await connection.synthesize(text: "Hello.", voice: nil)
        let body = try #require(transport.requests.first?.httpBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["text"] as? String == "Hello.")
        #expect(sent["voice"] == nil)
    }
}
