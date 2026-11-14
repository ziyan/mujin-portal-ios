import AVFoundation
import Foundation
import Observation
import PortalKit

/// VoiceCallController is a spoken conversation. It opens the streaming voice
/// socket, sends the microphone to it, sends each final transcript as an
/// ordinary message with `voice: true`, reads the answer aloud piece by piece
/// as it streams in, and handles the person talking over it. When the
/// organization has no streaming transcription it records utterances and
/// uses the older transcribe and synthesize endpoints instead.
@MainActor
@Observable
final class VoiceCallController {
    enum Phase: Equatable {
        case idle
        case connecting
        case listening
        case speaking
        case failed(String)
    }

    private(set) var phase = Phase.idle
    /// What is being heard right now, word by word.
    private(set) var caption = ""
    private(set) var isMuted = false
    /// A note beside the call that does not end it, such as one utterance that failed.
    private(set) var notice: String?
    /// True when the call uses recorded utterances because streaming transcription is not set up.
    private(set) var isUsingOlderPath = false
    /// How loud the microphone is now, 0 to 1, smoothed, for the level meter.
    private(set) var inputLevel: Float = 0
    /// Whether the person can cut the answer short: only on the streaming socket.
    var canCutIn: Bool { !isUsingOlderPath && phase == .speaking }

    /// Cuts a playing answer short, as talking over it would.
    func cutAnswer() { if canCutIn { interruptAnswer() } }

    /// A call with no socket or microphone, for the screenshots.
    func startDemo() { phase = .listening }

    var isActive: Bool {
        switch phase {
        case .idle, .failed: false
        default: true
        }
    }

    private let model: ConversationModel
    private let connection: Connection
    private let socketFactory: VoiceSocketFactory
    private let audio = VoiceAudioEngine()

    private var socket: (any VoiceSocket)?
    private var readTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var frameContinuation: AsyncStream<Data>.Continuation?
    private var housekeepingTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?

    // The answer being read.
    private var segmenters: [String: VoiceAnswerSegmenter] = [:]
    private var answerTexts: [String: String] = [:]
    private var answerOrder: [String] = []
    private var ignoredMessageIds: Set<String> = []
    private var queue = VoicePlaybackQueue()
    private var ledger = VoicePlaybackLedger()
    private var unsent: [SpeechPiece] = []
    private var outstandingCount = 0
    private var receivedSamples: [String: Int] = [:]
    private var scheduledSampleCount = 0
    private var playedSampleCount = 0
    private var lastPlayedAt = Date.distantPast
    private var recentlyPlayedText = ""

    // Talking over the answer.
    private var judge = InterruptionJudge()
    private var isPersonSpeechReported = false
    private var isPausedForJudgement = false
    private var strongestLevelDuringSpeech: Float = 0
    private var pendingInterruption: InterruptedAnswer?

    // The microphone.
    private var mutedSince: Date?
    private var segmenter = UtteranceSegmenter()
    private var utteranceSequence = 0

    init(model: ConversationModel, connection: Connection, socketFactory: @escaping VoiceSocketFactory) {
        self.model = model
        self.connection = connection
        self.socketFactory = socketFactory
    }

    // MARK: starting and ending

    func start() async {
        guard !isActive else { return }
        guard await Self.requestMicrophone() else {
            phase = .failed(String(localized: "Allow the microphone in Settings to talk to the assistant."))
            return
        }
        phase = .connecting
        notice = nil
        model.onAssistantText = { [weak self] id, text, isFinal in self?.assistantText(id: id, text: text, isFinal: isFinal) }
        await openSocket()
    }

    func end() {
        print("CALLDIAG voice-end \(Thread.callStackSymbols.prefix(5).joined(separator: " | "))")
        if let socket { Task { try? await socket.send(VoiceClientEvent.stop.encoded()) } }
        shutDown()
        phase = .idle
        caption = ""
    }

    func toggleMute() {
        isMuted.toggle()
        mutedSince = isMuted ? Date() : nil
        if isMuted { segmenter.reset() }
    }

    private func shutDown() {
        model.onAssistantText = nil
        readTask?.cancel()
        frameTask?.cancel()
        housekeepingTask?.cancel()
        pauseTask?.cancel()
        readTask = nil
        frameTask = nil
        housekeepingTask = nil
        pauseTask = nil
        frameContinuation?.finish()
        frameContinuation = nil
        socket?.close()
        socket = nil
        audio.onFrame = nil
        audio.stop()
        resetAnswer()
        isMuted = false
        mutedSince = nil
    }

    private static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    private func openSocket() async {
        do {
            let token = try await connection.accessToken()
            let server = await connection.server
            let opened = try await socketFactory(server, token)
            socket = opened
            try await opened.send(VoiceClientEvent.hello(surface: "ios", speechVoice: nil).encoded())
            readTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let frame = try? await opened.receive(), !Task.isCancelled else { break }
                    guard let self else { return }
                    switch frame {
                    case .closed:
                        self.socketClosed()
                        return
                    case .text(let text):
                        if let event = VoiceServerEvent(decoding: text) { await self.handle(event) }
                    }
                }
            }
        } catch {
            phase = .failed(error.userMessage)
        }
    }

    private func socketClosed() {
        guard isActive else { return }
        if !isUsingOlderPath { fail(String(localized: "The call ended.")) }
    }

    private func fail(_ message: String) {
        shutDown()
        phase = .failed(message)
    }

    // MARK: the microphone

    private func startAudio() {
        guard !audio.isCapturing else { return }
        let (frames, continuation) = AsyncStream<Data>.makeStream()
        frameContinuation = continuation
        audio.onFrame = { frame in continuation.yield(frame) }
        do {
            try audio.start()
        } catch {
            fail(String(localized: "The microphone could not be started."))
            return
        }
        phase = .listening
        // Frames are handled one at a time, in order.
        frameTask = Task { [weak self] in
            for await frame in frames {
                guard let self else { return }
                await self.microphoneFrame(frame)
            }
        }
        housekeepingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(VoiceAudio.stillHereInterval * 1_000_000_000))
                await self?.sayStillHere()
            }
        }
    }

    private func sayStillHere() async {
        guard isMuted, let socket else { return }
        try? await socket.send(VoiceClientEvent.stillHere.encoded())
    }

    private func microphoneFrame(_ frame: Data) async {
        let level = InterruptionJudge.level(ofPCM: frame)
        inputLevel = inputLevel * 0.6 + min(1, level * 4) * 0.4
        let isAnswerPlaying = scheduledSampleCount > playedSampleCount
        if isUsingOlderPath {
            await olderPathFrame(frame, level: level, isAnswerPlaying: isAnswerPlaying)
            return
        }
        if isAnswerPlaying, !isPersonSpeechReported { judge.learnEcho(frameLevel: level) }
        if isPersonSpeechReported { strongestLevelDuringSpeech = max(strongestLevelDuringSpeech, level) }
        guard let socket else { return }
        if isMuted {
            // A muted microphone sends silence for six seconds, so the server hears a pause end, then nothing.
            guard let mutedSince, Date().timeIntervalSince(mutedSince) < VoiceAudio.mutedSilenceSeconds else { return }
            try? await socket.sendAudio(Data(count: VoiceAudio.bytesPerFrame))
        } else {
            try? await socket.sendAudio(frame)
        }
    }

    // MARK: events from the server

    private func handle(_ event: VoiceServerEvent) async {
        switch event {
        case .ready:
            startAudio()
        case .refused, .error:
            await handleRefusal(event)
        case .speechStarted:
            personStartedSpeaking()
        case .speechStopped:
            isPersonSpeechReported = false
        case .transcriptDelta(_, let text):
            caption = text
            if isPausedForJudgement, !InterruptionJudge.isEcho(transcript: text, justPlayed: recentlyPlayedText) { interruptAnswer() }
        case .transcriptFinal(_, _, let text):
            caption = ""
            await transcriptFinal(text)
        case .transcriptFailed:
            caption = ""
            isPersonSpeechReported = false
            resumeAfterEcho()
        case .problem(let message):
            notice = message
        case .answerAudio(let id, let pcm):
            receivedSamples[id, default: 0] += pcm.count / VoiceAudio.bytesPerSample
            play(queue.received(pcm, for: id))
        case .answerAudioDone(let id):
            ledger.audioComplete(id: id, totalSampleCount: receivedSamples[id] ?? 0)
            play(queue.audioDone(id))
            pieceFinished()
        case .answerAudioFailed(let id, _):
            play(queue.audioFailed(id))
            pieceFinished()
        }
    }

    private func handleRefusal(_ event: VoiceServerEvent) async {
        let message: String
        switch event {
        case .refused(_, let text), .error(_, let text): message = text
        default: message = ""
        }
        switch event.refusalReason {
        case .notConfigured:
            // No streaming transcription for this organization: record utterances instead.
            socket?.close()
            socket = nil
            readTask?.cancel()
            isUsingOlderPath = true
            startAudio()
        case .sessionTimeLimit:
            // A call lasts 30 minutes at most: open a new one.
            let wasMuted = isMuted
            shutDown()
            phase = .connecting
            model.onAssistantText = { [weak self] id, text, isFinal in self?.assistantText(id: id, text: text, isFinal: isFinal) }
            await openSocket()
            if wasMuted { isMuted = true; mutedSince = Date() }
        default:
            fail(message.isEmpty ? String(localized: "The call could not be set up.") : message)
        }
    }

    // MARK: talking over the answer

    private func personStartedSpeaking() {
        isPersonSpeechReported = true
        strongestLevelDuringSpeech = 0
        guard phase == .speaking else { return }
        // Duck at once; pause after 0.6 s if they keep on.
        audio.duck()
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.pauseIfStillSpeaking()
        }
    }

    private func pauseIfStillSpeaking() {
        guard isPersonSpeechReported, phase == .speaking else { return }
        audio.pause()
        isPausedForJudgement = true
        // By the level first: well above the echo's own level is a person.
        if judge.isPerson(frameLevel: strongestLevelDuringSpeech) { interruptAnswer() }
    }

    /// The person is talking over the answer: end it, cancel the pieces not
    /// yet complete, and remember what they heard for the message they send.
    private func interruptAnswer() {
        pauseTask?.cancel()
        isPausedForJudgement = false
        let ids = queue.cancelAll()
        if !ids.isEmpty, let socket { Task { try? await socket.send(VoiceClientEvent.cancelAnswer(answerSegmentIds: ids).encoded()) } }
        let full = answerOrder.compactMap { answerTexts[$0] }.map(VoiceAnswerSegmenter.speakableText).joined(separator: " ")
        let split = ledger.split(fullSpeakableText: full)
        if !split.heard.isEmpty || !split.unheard.isEmpty {
            pendingInterruption = InterruptedAnswer(heardText: split.heard, unheardText: split.unheard)
        }
        ignoredMessageIds.formUnion(answerOrder)
        audio.flushPlayback()
        resetAnswer()
        phase = .listening
    }

    /// The pause turned out to be the answer's own echo: go on speaking.
    private func resumeAfterEcho() {
        pauseTask?.cancel()
        guard isPausedForJudgement || phase == .speaking else { return }
        isPausedForJudgement = false
        audio.resume()
    }

    private func transcriptFinal(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isPersonSpeechReported = false
        guard !trimmed.isEmpty else {
            resumeAfterEcho()
            return
        }
        let wasSpeaking = phase == .speaking || Date().timeIntervalSince(lastPlayedAt) < 2
        if wasSpeaking, InterruptionJudge.isEcho(transcript: trimmed, justPlayed: recentlyPlayedText) {
            // The answer heard through the microphone. Nothing is sent.
            resumeAfterEcho()
            return
        }
        if phase == .speaking { interruptAnswer() }
        let interrupted = pendingInterruption
        pendingInterruption = nil
        await model.sendVoice(trimmed, interruptedAnswer: interrupted)
    }

    // MARK: reading the answer aloud

    /// The answer so far, from the conversation's live stream.
    private func assistantText(id: String, text: String, isFinal: Bool) {
        guard isActive, !ignoredMessageIds.contains(id) else { return }
        if segmenters[id] == nil {
            segmenters[id] = VoiceAnswerSegmenter(idPrefix: id)
            answerOrder.append(id)
        }
        answerTexts[id] = text
        let pieces = segmenters[id]?.feed(text, isFinal: isFinal) ?? []
        for piece in pieces {
            ledger.asked(id: piece.id, text: piece.text)
            recentlyPlayedText += " " + piece.text
            unsent.append(piece)
        }
        if recentlyPlayedText.count > 1_500 { recentlyPlayedText = String(recentlyPlayedText.suffix(1_000)) }
        askForMore()
    }

    /// Asks for pieces, never more than four at once.
    private func askForMore() {
        while outstandingCount < 4, !unsent.isEmpty {
            let piece = unsent.removeFirst()
            outstandingCount += 1
            queue.asked(piece.id)
            if isUsingOlderPath {
                Task { await self.speakOnOlderPath(piece) }
            } else if let socket {
                Task { try? await socket.send(VoiceClientEvent.speakAnswer(answerSegmentId: piece.id, answerText: piece.text).encoded()) }
            }
        }
    }

    private func pieceFinished() {
        outstandingCount = max(0, outstandingCount - 1)
        askForMore()
    }

    private func play(_ chunks: [VoicePlaybackQueue.Chunk]) {
        for chunk in chunks {
            scheduledSampleCount += chunk.pcm.count / VoiceAudio.bytesPerSample
            phase = .speaking
            let id = chunk.answerSegmentId
            audio.play(pcm: chunk.pcm) { [weak self] samples in
                Task { @MainActor in self?.played(samples, id: id) }
            }
        }
    }

    private func played(_ samples: Int, id: String) {
        playedSampleCount += samples
        lastPlayedAt = Date()
        ledger.played(id: id, sampleCount: samples)
        if playedSampleCount >= scheduledSampleCount, unsent.isEmpty, outstandingCount == 0, phase == .speaking {
            phase = .listening
            judge.resetEcho()
        }
    }

    private func resetAnswer() {
        segmenters = [:]
        answerTexts = [:]
        answerOrder = []
        queue = VoicePlaybackQueue()
        ledger = VoicePlaybackLedger()
        unsent = []
        outstandingCount = 0
        receivedSamples = [:]
        scheduledSampleCount = 0
        playedSampleCount = 0
    }

    // MARK: the older path

    /// Recorded utterances: the microphone is listened to only while nothing is being spoken.
    private func olderPathFrame(_ frame: Data, level: Float, isAnswerPlaying: Bool) async {
        guard !isMuted, !isAnswerPlaying, phase != .speaking else {
            segmenter.reset()
            return
        }
        switch segmenter.feed(frame: frame, level: level) {
        case .nothing: break
        case .speechStarted: caption = String(localized: "Listening…")
        case .utterance(let pcm):
            caption = String(localized: "Working…")
            do {
                let text = try await connection.transcribe(wav: WAVFile.encode(pcm: pcm))
                caption = ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { await model.sendVoice(trimmed, interruptedAnswer: nil) }
            } catch {
                caption = ""
                notice = error.userMessage
            }
        }
    }

    private func speakOnOlderPath(_ piece: SpeechPiece) async {
        do {
            // No voice named: the server reads the person's current choice for each piece, so a voice changed during the call is heard at once.
            let data = try await connection.synthesize(text: piece.text, voice: nil)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("spoken-\(UUID().uuidString).mp3")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            phase = .speaking
            try audio.play(file: url) { [weak self] samples in
                Task { @MainActor in
                    self?.pieceFinished()
                    self?.played(samples, id: piece.id)
                }
            }
        } catch {
            notice = error.userMessage
            pieceFinished()
        }
    }
}

extension VoiceAudioEngine {
    var isCapturing: Bool { onFrame != nil }
}
