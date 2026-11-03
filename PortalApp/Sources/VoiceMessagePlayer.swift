@preconcurrency import AVFoundation
import Foundation
import Observation
import PortalKit

/// VoiceMessagePlayer plays one voice message at a time, for the whole app: starting another stops the first. It plays
/// from the server with the account's token, as the video player does, and tells the bubbles which message is playing, where, and
/// whether its audio could not be played at all.
@MainActor
@Observable
final class VoiceMessagePlayer {
    static let shared = VoiceMessagePlayer()

    private(set) var playingMessageId: String?
    private(set) var isPlaying = false
    /// The message the position belongs to: the one playing, or the one paused.
    private(set) var currentMessageId: String?
    private(set) var position: TimeInterval = 0
    /// Messages whose audio the player refused, such as a browser's WebM recording.
    private(set) var unplayableMessageIds: Set<String> = []
    private(set) var playedMessages: PlayedVoiceMessages

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var demoTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let playedKey = "playedVoiceMessages"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.playedKey), let saved = try? JSONDecoder().decode(PlayedVoiceMessages.self, from: data) {
            playedMessages = saved
        } else {
            playedMessages = PlayedVoiceMessages()
        }
    }

    func hasPlayed(_ messageId: String) -> Bool { playedMessages.hasPlayed(messageId) }

    func position(of messageId: String) -> TimeInterval { currentMessageId == messageId ? position : 0 }

    func markPlayedForDemo(_ messageId: String) { playedMessages.markPlayed(messageId) }

    func markUnplayable(_ messageId: String) { unplayableMessageIds.insert(messageId) }

    /// Plays, pauses or resumes a message.
    func toggle(messageId: String, attachmentId: String, duration: TimeInterval, connection: Connection, isDemo: Bool) {
        if currentMessageId == messageId, isPlaying {
            pause()
            return
        }
        if currentMessageId == messageId, player != nil || demoTask != nil || position > 0 {
            resume(duration: duration, isDemo: isDemo)
            return
        }
        start(messageId: messageId, attachmentId: attachmentId, duration: duration, connection: connection, isDemo: isDemo, from: 0)
    }

    func seek(messageId: String, attachmentId: String, to seconds: TimeInterval, duration: TimeInterval, connection: Connection, isDemo: Bool) {
        if currentMessageId == messageId {
            position = seconds
            player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            // A message not playing only remembers where it will start.
            stop()
            currentMessageId = messageId
            position = seconds
        }
    }

    func pause() {
        player?.pause()
        demoTask?.cancel()
        demoTask = nil
        isPlaying = false
        playingMessageId = nil
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation = nil
        demoTask?.cancel()
        demoTask = nil
        isPlaying = false
        playingMessageId = nil
        currentMessageId = nil
        position = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resume(duration: TimeInterval, isDemo: Bool) {
        isPlaying = true
        playingMessageId = currentMessageId
        if isDemo {
            runDemo(duration: duration)
        } else {
            player?.play()
        }
    }

    private func start(messageId: String, attachmentId: String, duration: TimeInterval, connection: Connection, isDemo: Bool, from start: TimeInterval) {
        let resumeAt = currentMessageId == messageId ? position : start
        stop()
        currentMessageId = messageId
        position = resumeAt
        isPlaying = true
        playingMessageId = messageId
        markPlayed(messageId)
        if isDemo {
            runDemo(duration: duration)
            return
        }
        loadTask = Task { [weak self] in
            guard let token = try? await connection.accessToken() else { self?.fail(messageId); return }
            let url = await connection.server.endpoint("/api/v1/attachment/\(attachmentId)")
            guard let self, !Task.isCancelled else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {}
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
            let item = AVPlayerItem(asset: asset)
            let created = AVPlayer(playerItem: item)
            self.player = created
            self.statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                guard observed.status == .failed else { return }
                Task { @MainActor in self?.fail(messageId) }
            }
            self.timeObserver = created.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, self.currentMessageId == messageId, time.seconds.isFinite else { return }
                    self.position = time.seconds
                }
            }
            self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finished(messageId) }
            }
            if resumeAt > 0 { _ = await created.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600)) }
            created.play()
        }
    }

    private func fail(_ messageId: String) {
        unplayableMessageIds.insert(messageId)
        stop()
    }

    private func finished(_ messageId: String) {
        guard currentMessageId == messageId else { return }
        stop()
    }

    private func markPlayed(_ messageId: String) {
        playedMessages.markPlayed(messageId)
        if let data = try? JSONEncoder().encode(playedMessages) { defaults.set(data, forKey: Self.playedKey) }
    }

    /// The demo has no audio: the position moves as it would.
    private func runDemo(duration: TimeInterval) {
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.isPlaying else { return }
                self.position += 0.1
                if self.position >= duration {
                    self.stop()
                    return
                }
            }
        }
    }
}
