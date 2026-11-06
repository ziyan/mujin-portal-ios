import AVFoundation
import Foundation
import Observation
import PortalKit
import SwiftUI

extension Notification.Name {
    /// Posted when a message is about to be read aloud, so anything holding the microphone lets go of it first.
    static let readAloudWillStart = Notification.Name("readAloudWillStart")
}

/// SpokenAudioPlayer plays one piece of spoken audio (the MP3 the server answers with) and says when it has finished.
@MainActor
final class SpokenAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Error>?

    /// Plays the audio and returns when it has played to its end. Throws `CancellationError` when `stop` or the task cut it short.
    func play(_ audio: Data) async throws {
        let created = try AVAudioPlayer(data: audio)
        created.delegate = self
        player = created
        guard created.prepareToPlay(), created.play() else {
            player = nil
            throw PortalError.refused("The spoken message could not be played.")
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    /// Stops what is playing. A `play` still waiting for its end throws `CancellationError`.
    func stop() {
        player?.stop()
        player = nil
        let waiting = continuation
        continuation = nil
        waiting?.resume(throwing: CancellationError())
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished(isSuccessful: flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in self.finished(isSuccessful: false) }
    }

    private func finished(isSuccessful: Bool) {
        player = nil
        let waiting = continuation
        continuation = nil
        if isSuccessful {
            waiting?.resume()
        } else {
            waiting?.resume(throwing: PortalError.refused("The spoken message could not be played."))
        }
    }
}

/// ReadAloudController reads one message aloud at a time, whichever screen asked. The message is cut into pieces of whole sentences;
/// the first is asked for at once, and the next while one plays, so the first sound comes quickly. The server speaks with the voice
/// the person chose. Audio plays in the playback category, which the ringer switch does not silence.
@MainActor
@Observable
final class ReadAloudController {
    enum Phase: Equatable {
        case idle
        /// The first piece has been asked for and has not come yet.
        case preparing
        case playing
    }

    private(set) var phase = Phase.idle
    /// The message being read, from the tap until its last piece ends.
    private(set) var messageId: String?
    /// Why the reading stopped, when it did not finish: the server's reason or a note on what went wrong.
    private(set) var errorMessage: String?

    private let connection: Connection
    private let player = SpokenAudioPlayer()
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Data, Error>?
    /// Counts the readings, so a reading that was stopped never changes what the next one shows.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var interruptionObserver: (any NSObjectProtocol)?

    init(connection: Connection) {
        self.connection = connection
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                // A phone call or another app taking the sound ends the reading.
                if typeValue == AVAudioSession.InterruptionType.began.rawValue { self?.stop() }
            }
        }
    }

    /// Whether the bar has something to say: a reading under way, or why one stopped.
    var isShowingBar: Bool { phase != .idle || errorMessage != nil }

    /// Whether the message is the one being read now.
    func isReading(_ messageId: String) -> Bool { phase != .idle && self.messageId == messageId }

    /// Reads the message, or stops when it is the one being read. Starting another message stops the first.
    func toggle(messageId: String, markdown: String, isDemo: Bool) {
        let wasReadingIt = isReading(messageId)
        stop()
        errorMessage = nil
        guard !wasReadingIt else { return }
        let pieces = ReadAloudText.pieces(of: markdown)
        guard !pieces.isEmpty else { return }
        generation += 1
        self.messageId = messageId
        phase = .preparing
        let current = generation
        NotificationCenter.default.post(name: .readAloudWillStart, object: nil)
        if isDemo {
            readTask = Task { [weak self] in await self?.playDemo(generation: current) }
        } else {
            readTask = Task { [weak self] in await self?.read(pieces, generation: current) }
        }
    }

    /// Stops the reading at once.
    func stop() {
        generation += 1
        readTask?.cancel()
        readTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        player.stop()
        if phase != .idle { deactivateSession() }
        phase = .idle
        messageId = nil
    }

    func dismissError() { errorMessage = nil }

    /// The playing state for the screenshots, with nothing fetched and no sound.
    func stageDemo(messageId: String) {
        stop()
        generation += 1
        self.messageId = messageId
        phase = .playing
        let current = generation
        readTask = Task { [weak self] in await self?.playDemo(generation: current) }
    }

    // MARK: reading

    private func read(_ pieces: [String], generation current: Int) async {
        do {
            try activateSession()
            var fetch = startFetch(pieces[0])
            for index in pieces.indices {
                let audio = try await fetch.value
                try Task.checkCancellation()
                if index + 1 < pieces.count { fetch = startFetch(pieces[index + 1]) }
                guard current == generation else { return }
                phase = .playing
                try await player.play(audio)
            }
            guard current == generation else { return }
            finish()
        } catch {
            // A reading that was stopped, or replaced by another, says nothing.
            guard !Task.isCancelled, current == generation else { return }
            let message = error.userMessage
            stop()
            errorMessage = message
        }
    }

    private func startFetch(_ text: String) -> Task<Data, Error> {
        let connection = connection
        let created = Task { try await connection.synthesize(text: text, voice: nil) }
        fetchTask = created
        return created
    }

    private func playDemo(generation current: Int) async {
        phase = .playing
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled, current == generation else { return }
        finish()
    }

    private func finish() {
        deactivateSession()
        phase = .idle
        messageId = nil
        readTask = nil
        fetchTask = nil
    }

    // MARK: the audio session

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Playback ignores the ringer switch; spoken audio tells other apps' audio to pause and lets it resume after.
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// ReadAloudBar says that a message is being read, and stops it. It also says why a reading could not go on, until it is dismissed.
struct ReadAloudBar: View {
    let readAloud: ReadAloudController
    @Environment(\.accessibilityReduceMotion) private var isMotionReduced

    var body: some View {
        if readAloud.phase != .idle {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: readAloud.phase == .playing && !isMotionReduced)
                    .accessibilityHidden(true)
                (readAloud.phase == .preparing ? Text("Preparing to read…") : Text("Reading aloud"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    readAloud.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.footnote)
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 32, height: 32)
                        .background(Color.primary, in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop reading")
                .accessibilityIdentifier("readAloudStopButton")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .background(Color.portalCard.opacity(0.92), in: .capsule)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("readAloudBar")
        } else if let message = readAloud.errorMessage {
            HStack(spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("readAloudError")
                Button {
                    readAloud.dismissError()
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
        }
    }
}
