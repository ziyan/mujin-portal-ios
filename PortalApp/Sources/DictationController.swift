import AVFoundation
import Foundation
import Observation
import PortalKit
import SwiftUI

/// AudioSessionSnapshot is the audio session as it was before dictation took the microphone, so it can be put back.
private struct AudioSessionSnapshot {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    static func capture() -> AudioSessionSnapshot {
        let session = AVAudioSession.sharedInstance()
        return AudioSessionSnapshot(category: session.category, mode: session.mode, options: session.categoryOptions)
    }

    func restore() {
        try? AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
    }
}

/// DictationController puts what the person says into a message box as they speak. It opens the voice socket a call uses, with the
/// purpose of dictation, which only transcribes: the microphone goes up, the live words come back as a caption, and each final
/// transcript is handed to the box. Nothing is sent, and the words stay the person's to edit.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        /// The microphone has been asked for, or the socket has not said it is ready.
        case connecting
        case listening
        /// The person stopped it; the words still being said are waited for, a few seconds at most.
        case finishing
    }

    private(set) var phase = Phase.idle
    /// The words being heard, before they are final.
    private(set) var captionText = ""
    /// Why dictation did not start or stopped, in words for the person.
    private(set) var errorMessage: String?

    /// Whether the button shows dictation on: from the tap until the person or the clock stops it.
    var isListening: Bool { phase == .connecting || phase == .listening }

    /// Whether there is a line to show above the box: the words heard so far, or why dictation did not go on.
    var isShowingStatus: Bool { isListening || errorMessage != nil }

    /// How long the socket has to say it is ready.
    private static let readyLimitSeconds: TimeInterval = 25

    private let socketFactory: VoiceSocketFactory
    @ObservationIgnored private var audio: VoiceAudioEngine?
    @ObservationIgnored private var socket: (any VoiceSocket)?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var frameContinuation: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var tracker = DictationTracker(startedAt: Date())
    @ObservationIgnored private var onWords: ((String) -> Void)?
    @ObservationIgnored private var sessionBeforeDictation: AudioSessionSnapshot?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var isReady = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var isWaitingOnSpeech = false
    @ObservationIgnored private var stoppedAt = Date()
    /// Counts the dictations, so one that ended never changes what the next one shows.
    @ObservationIgnored private var generation = 0

    @ObservationIgnored nonisolated(unsafe) private var readAloudObserver: (any NSObjectProtocol)?

    init(socketFactory: @escaping VoiceSocketFactory = URLSessionVoiceSocket.factory) {
        self.socketFactory = socketFactory
        // The microphone and a spoken message cannot share the audio session: reading a message aloud ends dictation.
        readAloudObserver = NotificationCenter.default.addObserver(forName: .readAloudWillStart, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.abort() }
        }
    }

    deinit {
        if let readAloudObserver { NotificationCenter.default.removeObserver(readAloudObserver) }
    }

    // MARK: starting and stopping

    /// Starts dictating into the box through `onWords`, which gets each final transcript. When it is going already, the person's
    /// tap stops it.
    func toggle(place: DictationPlace, connection: Connection, isDemo: Bool, onWords: @escaping (String) -> Void) {
        switch phase {
        case .idle: start(place: place, connection: connection, isDemo: isDemo, onWords: onWords)
        case .connecting, .listening: stop()
        case .finishing: break
        }
    }

    /// Says why dictation cannot start, without starting it.
    func report(_ message: String) {
        errorMessage = message
    }

    func dismissError() { errorMessage = nil }

    private func start(place: DictationPlace, connection: Connection, isDemo: Bool, onWords: @escaping (String) -> Void) {
        errorMessage = nil
        captionText = ""
        self.onWords = onWords
        generation += 1
        let current = generation
        startedAt = Date()
        tracker = DictationTracker(startedAt: startedAt)
        if isDemo {
            phase = .listening
            demoTask = Task { [weak self] in await self?.playDemo(generation: current) }
            return
        }
        phase = .connecting
        startWatching(generation: current)
        startTask = Task { [weak self] in
            let isAllowed = await AVAudioApplication.requestRecordPermission()
            // The person may have stopped it while the system asked.
            guard let self, self.generation == current else { return }
            guard isAllowed else {
                self.fail(String(localized: "Allow the microphone in Settings to dictate."), generation: current)
                return
            }
            await self.openSocket(place: place, connection: connection, generation: current)
        }
    }

    /// The person's stop. The microphone goes on, silent, so the server hears the last utterance end, and `stop` is sent only once
    /// the last final transcript has landed: after about a second when nothing was being said, and after at most three seconds
    /// when something was, or when speech starts during the wait.
    func stop() {
        guard phase == .connecting || phase == .listening else { return }
        guard phase == .listening, isReady else {
            finish()
            return
        }
        isStopping = true
        phase = .finishing
        captionText = ""
        stoppedAt = Date()
        isWaitingOnSpeech = tracker.isSpeechPending
        let current = generation
        finishTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.generation == current else { return }
                if self.isFinishDue(at: Date()) {
                    self.finish(generation: current)
                    return
                }
            }
        }
    }

    /// Whether the wait after the person's stop is over: the limit has passed, or the speech waited on has all come.
    private func isFinishDue(at date: Date) -> Bool {
        let limit = DictationTiming.stopWaitSeconds(isSpeechPending: isWaitingOnSpeech)
        if date.timeIntervalSince(stoppedAt) >= limit { return true }
        return isWaitingOnSpeech && !tracker.isSpeechPending
    }

    /// Ends dictation at once and drops the words not yet final: the box they were for was sent, or is gone.
    func abort() {
        finish()
    }

    private func fail(_ message: String, generation current: Int) {
        guard current == generation, phase != .idle else { return }
        errorMessage = message
        finish()
    }

    private func finish(generation current: Int? = nil) {
        if let current, current != generation { return }
        guard phase != .idle else { return }
        generation += 1
        let openSocket = socket
        socket = nil
        if let openSocket {
            Task {
                try? await openSocket.send(VoiceClientEvent.stop.encoded())
                openSocket.close()
            }
        }
        startTask?.cancel()
        readTask?.cancel()
        frameTask?.cancel()
        watchTask?.cancel()
        finishTask?.cancel()
        demoTask?.cancel()
        startTask = nil
        readTask = nil
        frameTask = nil
        watchTask = nil
        finishTask = nil
        demoTask = nil
        frameContinuation?.finish()
        frameContinuation = nil
        audio?.stop()
        audio?.onFrame = nil
        audio = nil
        // The microphone changed the audio session; whoever had it before gets it back.
        if let sessionBeforeDictation {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionBeforeDictation.restore()
        }
        sessionBeforeDictation = nil
        isReady = false
        isStopping = false
        isWaitingOnSpeech = false
        onWords = nil
        captionText = ""
        phase = .idle
    }

    // MARK: the socket

    private func openSocket(place: DictationPlace, connection: Connection, generation current: Int) async {
        do {
            let token = try await connection.accessToken()
            let server = await connection.server
            let opened = try await socketFactory(server, token)
            guard current == generation, phase == .connecting else {
                opened.close()
                return
            }
            socket = opened
            try await opened.send(VoiceClientEvent.dictationHello(place: place).encoded())
            readTask = Task { [weak self] in
                while !Task.isCancelled {
                    let frame = try? await opened.receive()
                    guard !Task.isCancelled, let self else { return }
                    switch frame {
                    case .text(let text)?:
                        if let event = VoiceServerEvent(decoding: text) { self.handle(event, generation: current) }
                    case .closed?, nil:
                        self.socketClosed(generation: current)
                        return
                    }
                }
            }
        } catch {
            fail(error.userMessage, generation: current)
        }
    }

    private func socketClosed(generation current: Int) {
        guard current == generation, phase != .idle else { return }
        if isStopping {
            finish()
        } else {
            fail(String(localized: "Dictation lost its connection."), generation: current)
        }
    }

    private func handle(_ event: VoiceServerEvent, generation current: Int) {
        guard current == generation, phase != .idle else { return }
        switch event {
        case .ready(_, _, _, let sampleRateHertz, let frameDurationMS):
            guard !isReady else { return }
            isReady = true
            _ = tracker.accept(event, at: Date())
            startAudio(format: .named(sampleRateHertz: sampleRateHertz, frameDurationMS: frameDurationMS), generation: current)
        case .refused(_, let message), .error(_, let message):
            fail(message.isEmpty ? String(localized: "Dictation could not be set up.") : message, generation: current)
        default:
            let update = tracker.accept(event, at: Date())
            if !isStopping, let caption = update.captionText { captionText = caption }
            if let words = update.transcriptText { onWords?(words) }
            // Speech that starts during the wait is waited for too, up to the longer limit.
            if isStopping, tracker.isSpeechPending { isWaitingOnSpeech = true }
            if isStopping, isFinishDue(at: Date()) { finish() }
        }
    }

    // MARK: the microphone

    private func startAudio(format: DictationFormat, generation current: Int) {
        let engine = VoiceAudioEngine()
        let (frames, continuation) = AsyncStream<Data>.makeStream()
        frameContinuation = continuation
        engine.onFrame = { frame in continuation.yield(frame) }
        sessionBeforeDictation = AudioSessionSnapshot.capture()
        do {
            try engine.start(format: format)
        } catch {
            fail(String(localized: "The microphone could not be started."), generation: current)
            return
        }
        audio = engine
        phase = .listening
        frameTask = Task { [weak self] in
            for await frame in frames {
                guard let self else { return }
                await self.send(frame)
            }
        }
    }

    private func send(_ frame: Data) async {
        guard let socket else { return }
        // After the person's stop the microphone goes on, silent, so the server hears the last utterance end.
        try? await socket.sendAudio(isStopping ? Data(count: frame.count) : frame)
    }

    // MARK: watching the clock

    private func startWatching(generation current: Int) {
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tick(generation: current)
            }
        }
    }

    private func tick(generation current: Int) {
        guard current == generation else { return }
        let now = Date()
        switch phase {
        case .connecting:
            if now.timeIntervalSince(startedAt) > Self.readyLimitSeconds {
                fail(String(localized: "Dictation could not be set up."), generation: current)
            }
        case .listening:
            // A microphone left on with nobody speaking is not left on.
            if tracker.isSilent(at: now) { stop() }
        case .idle, .finishing:
            break
        }
    }

    // MARK: the demo

    /// A dictation with no microphone and no socket, for the UI tests: some words are heard, then they are final.
    private func playDemo(generation current: Int) async {
        let words = DemoSpeech.dictatedWords
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, current == generation else { return }
        captionText = DemoSpeech.firstCaption
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, current == generation else { return }
        captionText = words
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, current == generation else { return }
        captionText = ""
        onWords?(words)
    }

    /// The listening state for the screenshots, with a live caption and no microphone.
    func stageListening(captionText: String) {
        generation += 1
        phase = .listening
        self.captionText = captionText
    }
}

/// DictationStatus is the line above the message box while the microphone is on: the words heard so far, or that it is listening.
/// It also says why dictation did not start or stopped, until it is dismissed.
struct DictationStatus: View {
    let dictation: DictationController

    var body: some View {
        if let message = dictation.errorMessage {
            HStack(spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dictationError")
                Button {
                    dictation.dismissError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 20)
        } else if dictation.isListening {
            Text(dictation.captionText.isEmpty ? String(localized: "Listening…") : dictation.captionText)
                .font(.callout)
                .foregroundStyle(dictation.captionText.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("dictationCaption")
        }
    }
}

/// DemoSpeech is the words the demo dictates and the message the demo reads, all invented.
enum DemoSpeech {
    static let firstCaption = "Can you check the dock"
    static let dictatedWords = "Can you check the dock schedule for Friday"
}

/// SpeechLifecycle ends dictation and reading aloud where they must end: when the screen goes away, when a call starts, and, for
/// dictation, when the app leaves the foreground. (A screen that is covered by another ends them too, where it stops its feed.)
struct SpeechLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let dictation: DictationController

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { dictation.abort() }
            }
            .onChange(of: appModel.callCenter.isInCall) { _, isInCall in
                guard isInCall else { return }
                dictation.abort()
                session.readAloud.stop()
            }
            .onDisappear {
                dictation.abort()
                session.readAloud.stop()
            }
    }
}

extension View {
    func speechLifecycle(_ dictation: DictationController) -> some View {
        modifier(SpeechLifecycle(dictation: dictation))
    }
}
