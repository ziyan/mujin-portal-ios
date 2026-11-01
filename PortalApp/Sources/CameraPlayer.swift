import AVFoundation
import Observation
import PortalKit
import Foundation

/// CameraTarget is a camera to open and where to start looking: now, or at a
/// moment of the recording.
struct CameraTarget: Hashable {
    let camera: Camera
    /// Milliseconds since 1970 to start playing from, or nil to watch live.
    var startAtMS: Double?
    /// A moment to mark on the timeline, such as when an incident was detected.
    var markerMS: Double?
}

/// CameraPlayer plays one camera, live or from the recording, and owns
/// everything that can go wrong on the way: the sockets, the decoder's clock,
/// the reconnects with backoff, the windows of a recording, and the fallback to
/// downloaded clips for a controller without the playback socket. The screen
/// reads its state and calls its controls.
///
/// Video is decoded by the system: the NVR's fragmented MP4 is cut into
/// frames (PortalKit) and handed to an `AVSampleBufferDisplayLayer`, whose
/// clock is the stream's time, so a pause is a rate of zero and a speed is a
/// rate. Only the clip fallback uses an `AVPlayer`.
@MainActor
@Observable
final class CameraPlayer {
    enum Mode: Equatable {
        case live
        case recorded
    }

    /// What draws the picture: decoded frames, or the clip player of the fallback.
    enum Surface: Equatable {
        case frames
        case clips
    }

    let camera: Camera
    private(set) var mode = Mode.live
    private(set) var status = CameraStreamStatus.idle
    /// Where the picture is, in milliseconds since 1970. While live it is the newest frame shown.
    private(set) var playheadMS: Double
    private(set) var isPaused = false
    private(set) var speed = 1.0
    private(set) var surface = Surface.frames
    /// A sentence for the person when something is not as expected: no recording here, the controller is offline.
    private(set) var notice: String?
    private(set) var clock: CameraClock
    var quality = CameraQuality.medium {
        didSet {
            guard quality != oldValue, hasStarted else { return }
            start(atMS: mode == .live ? nil : playheadMS)
        }
    }

    let renderer = CameraRenderer()
    let clipPlayer = AVPlayer()

    private let connection: Connection
    private let server: ServerAddress
    private let socketFactory: CameraSocketFactory
    private let transports: CameraTransportMemory
    private let isDemo: Bool

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var socket: (any CameraSocket)?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var clipTask: Task<Void, Never>?
    @ObservationIgnored private var configuration: CameraVideoConfiguration?
    @ObservationIgnored private var stitcher: CameraStitcher?
    @ObservationIgnored private var lastFrameAt: Date?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var hasClockStarted = false
    @ObservationIgnored private var bufferedEndAxisSeconds = 0.0
    @ObservationIgnored private var requestedStartMS = 0.0
    @ObservationIgnored private var windows: CameraPlaybackWindows?
    @ObservationIgnored private var windowId = 0
    @ObservationIgnored private var isWindowOpen = false
    @ObservationIgnored private var windowOpenedAt = Date()
    @ObservationIgnored private var windowDeliveredFrames = false
    @ObservationIgnored private var windowCount = 0
    @ObservationIgnored private var sessionDeliveredFrames = false
    @ObservationIgnored private var isTransportResolved = false
    @ObservationIgnored private var suspendedAtMS: Double?
    @ObservationIgnored private var wasSuspendedPaused = false
    @ObservationIgnored private var clipActualStartMS = 0.0
    @ObservationIgnored private var clipFile: URL?
    @ObservationIgnored private var clipRequestedEndMS = 0.0
    @ObservationIgnored private var clipEmptyCount = 0

    init(
        camera: Camera, clock: CameraClock, connection: Connection, server: ServerAddress, socketFactory: @escaping CameraSocketFactory,
        transports: CameraTransportMemory, isDemo: Bool
    ) {
        self.camera = camera
        self.clock = clock
        self.connection = connection
        self.server = server
        self.socketFactory = socketFactory
        self.transports = transports
        self.isDemo = isDemo
        self.playheadMS = Self.nowMS
    }

    static var nowMS: Double { Date().timeIntervalSince1970 * 1000 }

    var channel: Int { quality.channelId(of: camera.channels) }
    var isLive: Bool { mode == .live }
    var qualitiesOffered: [CameraQuality] { CameraQuality.offered(by: camera.channels) }

    func updateClock(_ clock: CameraClock) { self.clock = clock }

    // MARK: controls

    /// Starts over at a moment of the recording, or live when `atMS` is nil or is as good as now.
    func start(atMS requestedMS: Double?) {
        hasStarted = true
        stopSessions()
        generation += 1
        notice = nil
        failures = 0
        isPaused = false
        let now = Self.nowMS
        if let requestedMS, requestedMS < now - 5_000 {
            beginRecorded(atMS: requestedMS)
        } else {
            beginLive(keepingPicture: false)
        }
        startTicking()
    }

    func goLive() { start(atMS: nil) }

    func seek(toMS timeMS: Double) { start(atMS: timeMS) }

    func skip(byMS deltaMS: Double) {
        seek(toMS: min(playheadMS + deltaMS, Self.nowMS))
    }

    /// Tries again after the stream gave up.
    func retry() {
        start(atMS: mode == .live ? nil : playheadMS)
    }

    func togglePause() {
        if isPaused { resumePlaying() } else { pause() }
    }

    func setSpeed(_ rate: Double) {
        speed = rate
        if mode == .recorded, !isPaused { applyRate() }
    }

    /// Stops everything: the screen is going away.
    func stop() {
        hasStarted = false
        stopSessions()
        tickTask?.cancel()
        tickTask = nil
        generation += 1
        status = .idle
        removeClipFile()
    }

    /// The app is leaving the foreground: the sockets close, and where the person was is remembered.
    func suspend() {
        guard hasStarted else { return }
        suspendedAtMS = mode == .live ? nil : playheadMS
        wasSuspendedPaused = isPaused
        hasStarted = false
        stopSessions()
        tickTask?.cancel()
        tickTask = nil
        generation += 1
        renderer.reset(removingImage: false)
        status = .idle
    }

    func resume() {
        guard !hasStarted, status == .idle else { return }
        let paused = wasSuspendedPaused
        start(atMS: suspendedAtMS)
        if paused, mode == .recorded { pause() }
    }

    private func pause() {
        isPaused = true
        if mode == .live {
            // A paused live picture is frozen where it is and the socket is let go; going on is a new connection, to the live edge.
            closeSocket()
            readTask?.cancel()
            reconnectTask?.cancel()
            renderer.setRate(0)
            status = .playing
        } else if surface == .clips {
            clipPlayer.pause()
        } else {
            renderer.setRate(0)
        }
    }

    private func resumePlaying() {
        if mode == .live {
            start(atMS: nil)
            return
        }
        isPaused = false
        applyRate()
    }

    private func applyRate() {
        if surface == .clips {
            clipPlayer.playImmediately(atRate: Float(speed))
        } else {
            renderer.setRate(speed)
        }
    }

    // MARK: live

    private func beginLive(keepingPicture: Bool) {
        mode = .live
        surface = .frames
        status = failures > 0 ? .reconnecting : .connecting
        resetStream(removingImage: !keepingPicture)
        playheadMS = Self.nowMS
        requestedStartMS = playheadMS
        guard camera.isStreamable else {
            status = .failed
            notice = camera.isControllerConnected == true
                ? String(localized: "This camera is offline.") : String(localized: "The controller is offline.")
            return
        }
        lastFrameAt = Date()
        let id = generation
        let path = CameraRoutes.livePath(controllerId: camera.controllerId, cameraId: camera.originCameraId, channel: channel)
        readTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.readSocket(path: path, generation: id)
            self.liveSocketEnded(generation: id)
        }
    }

    private func liveSocketEnded(generation id: Int) {
        guard id == generation, mode == .live, !isPaused else { return }
        failSession()
    }

    /// The live stream broke or stalled: try again after a pause that grows, until the attempts are used up.
    private func failSession() {
        guard mode == .live, !isPaused else { return }
        // The reader of the broken socket is let go for good, so its ending is not counted a second time.
        generation += 1
        closeSocket()
        failures += 1
        guard CameraStreamHealth.canReconnectAutomatically(consecutiveFailures: failures) else {
            status = .failed
            notice = String(localized: "The camera could not be reached.")
            return
        }
        status = .reconnecting
        let delay = CameraStreamHealth.reconnectDelay(consecutiveFailures: failures)
        let id = generation
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, id == self.generation, self.mode == .live else { return }
            self.generation += 1
            self.beginLive(keepingPicture: true)
        }
    }

    // MARK: recorded, over the playback socket

    private func beginRecorded(atMS requestedMS: Double) {
        mode = .recorded
        surface = .frames
        status = .connecting
        resetStream(removingImage: true)
        playheadMS = requestedMS
        requestedStartMS = requestedMS
        windows = CameraPlaybackWindows(startMS: requestedMS, endMS: Self.nowMS)
        isTransportResolved = false
        sessionDeliveredFrames = false
        windowCount = 0
        let id = generation
        readTask = Task { [weak self] in
            guard let self else { return }
            let transport = await self.resolveTransport()
            guard id == self.generation else { return }
            switch transport {
            case .webSocket:
                self.isTransportResolved = true
            case .exportClips:
                self.isTransportResolved = true
                self.beginClips(atMS: requestedMS)
            case nil:
                self.status = .failed
                self.notice = String(localized: "The controller is offline.")
            }
        }
    }

    /// The controller's transport: remembered, or found out with one GET. Nil when the controller cannot be asked.
    private func resolveTransport() async -> CameraPlaybackTransport? {
        if let known = transports.transport(forController: camera.controllerId) { return known }
        switch await connection.probePlaybackTransport(controllerId: camera.controllerId, cameraId: camera.originCameraId) {
        case .found(let transport):
            transports.remember(transport, forController: camera.controllerId)
            return transport
        case .unreachable:
            return nil
        }
    }

    private func manageWindows() {
        guard mode == .recorded, surface == .frames, isTransportResolved, windows != nil else { return }
        if isWindowOpen {
            let quietFor = Date().timeIntervalSince(lastFrameAt ?? windowOpenedAt)
            let limit = windowDeliveredFrames ? CameraPlaybackWindows.idleSeconds : CameraPlaybackWindows.firstFrameTimeout
            if quietFor >= limit { endWindow() }
        }
        // Enough is queued for the decoder already: do not ask the NVR for more until it has been shown.
        guard renderer.pendingCount < 900 else { return }
        let bufferedEndMS = stitcher.map { $0.epochMS(forAxisSeconds: bufferedEndAxisSeconds) } ?? requestedStartMS
        guard let plan = windows?.plan(bufferedEndMS: bufferedEndMS, playheadMS: playheadMS, speed: speed, isWindowOpen: isWindowOpen) else { return }
        switch plan {
        case .open(let startMS, let endMS):
            openWindow(startMS: startMS, endMS: endMS)
        case .wait:
            break
        case .finished:
            // Everything up to now was asked for; once it has played, the live picture is next.
            if !isPaused, hasClockStarted, renderer.clockSeconds >= bufferedEndAxisSeconds - 0.3 { goLive() }
        case .noRecording:
            if status != .ended {
                status = .ended
                notice = String(localized: "No recording was found after this time.")
            }
        }
    }

    private func openWindow(startMS: Double, endMS: Double) {
        windowId += 1
        windowCount += 1
        isWindowOpen = true
        windowOpenedAt = Date()
        lastFrameAt = nil
        windowDeliveredFrames = false
        stitcher?.beginWindow()
        let id = windowId
        let generationAtOpen = generation
        let path = CameraRoutes.playbackPath(controllerId: camera.controllerId, cameraId: camera.originCameraId, channel: channel, startMS: startMS, endMS: endMS)
        readTask = Task { [weak self] in
            guard let self else { return }
            let didReceive = await self.readSocket(path: path, generation: generationAtOpen)
            self.windowSocketEnded(id: id, generation: generationAtOpen, didReceiveFrame: didReceive)
        }
    }

    /// The window's socket ended by itself: the NVR closed it, or it dropped, or it was refused.
    private func windowSocketEnded(id: Int, generation generationAtOpen: Int, didReceiveFrame: Bool) {
        guard generationAtOpen == generation, id == windowId, isWindowOpen else { return }
        if !sessionDeliveredFrames, windowCount == 1, CameraTransportRules.transportAfterDial(didReceiveFrame: didReceiveFrame) != nil {
            // Refused before a single frame: this controller may not have the playback socket after all. Ask again before believing it.
            let generationAtFailure = generation
            Task { [weak self] in
                guard let self else { return }
                let probe = await self.connection.probePlaybackTransport(controllerId: self.camera.controllerId, cameraId: self.camera.originCameraId)
                guard generationAtFailure == self.generation else { return }
                switch probe {
                case .found(.exportClips):
                    self.transports.remember(.exportClips, forController: self.camera.controllerId)
                    self.beginClips(atMS: self.requestedStartMS)
                case .found(.webSocket):
                    self.endWindow()
                case .unreachable:
                    self.status = .failed
                    self.notice = String(localized: "The controller is offline.")
                }
            }
            return
        }
        endWindow()
    }

    private func endWindow() {
        guard isWindowOpen else { return }
        isWindowOpen = false
        closeSocket()
        windows?.windowEnded(didDeliverFrames: windowDeliveredFrames)
        if !windowDeliveredFrames, status != .ended {
            notice = String(localized: "Looking for the next recording.")
        }
    }

    // MARK: recorded, over downloaded clips

    /// The fallback for a controller without the playback socket: a clip at a time from `video/export`, played by the system player.
    private func beginClips(atMS startMS: Double) {
        stopSessions()
        surface = .clips
        mode = .recorded
        status = .connecting
        clipEmptyCount = 0
        playheadMS = startMS
        requestedStartMS = startMS
        loadClip(startMS: startMS)
    }

    private func loadClip(startMS: Double) {
        let id = generation
        let length = min(10_000 * max(1, speed), 60_000) * pow(2, Double(clipEmptyCount))
        let endMS = min(startMS + min(length, 15 * 60_000), Self.nowMS)
        guard endMS - startMS > 1_500 else {
            goLive()
            return
        }
        clipRequestedEndMS = endMS
        let path = CameraRoutes.exportPath(controllerId: camera.controllerId, cameraId: camera.originCameraId, channel: channel, startMS: startMS, endMS: endMS)
        clipTask?.cancel()
        clipTask = Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await CameraFiles.download(path: path, connection: self.connection, isDemo: self.isDemo, startMS: startMS)
                guard !Task.isCancelled, id == self.generation else {
                    try? FileManager.default.removeItem(at: file.url)
                    return
                }
                self.clipEmptyCount = 0
                self.removeClipFile()
                self.clipFile = file.url
                self.clipActualStartMS = file.actualStartMS ?? startMS
                let item = AVPlayerItem(url: file.url)
                self.clipPlayer.replaceCurrentItem(with: item)
                let offset = max(0, (startMS - self.clipActualStartMS) / 1000)
                if offset > 0 { _ = await self.clipPlayer.seek(to: CMTime(seconds: offset, preferredTimescale: 600)) }
                guard id == self.generation else { return }
                self.status = .playing
                self.notice = nil
                if !self.isPaused { self.clipPlayer.playImmediately(atRate: Float(self.speed)) }
            } catch {
                guard !Task.isCancelled, id == self.generation else { return }
                self.clipFailed(error, startMS: startMS, endMS: endMS)
            }
        }
    }

    private func clipFailed(_ error: Error, startMS: Double, endMS: Double) {
        // A clip with nothing in it is a gap in the recording: go on past it, in longer steps.
        let isGap = (error as? PortalError) == .refused("HTTP 404")
        if isGap, clipEmptyCount < CameraPlaybackWindows.maximumEmptyWindows {
            clipEmptyCount += 1
            notice = String(localized: "Looking for the next recording.")
            loadClip(startMS: endMS)
        } else if isGap {
            status = .ended
            notice = String(localized: "No recording was found after this time.")
        } else {
            status = .failed
            notice = String(localized: "The recording could not be loaded.")
        }
    }

    private func advanceClip() {
        guard let item = clipPlayer.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0, clipPlayer.currentTime().seconds >= duration - 0.15 else { return }
        let nextStartMS = clipActualStartMS + duration * 1000
        clipPlayer.replaceCurrentItem(with: nil)
        loadClip(startMS: max(nextStartMS, clipRequestedEndMS))
    }

    private func removeClipFile() {
        if let clipFile { try? FileManager.default.removeItem(at: clipFile) }
        clipFile = nil
    }

    // MARK: the socket

    /// Reads one socket until it ends. Returns whether any bytes came.
    private func readSocket(path: String, generation id: Int) async -> Bool {
        let opened: any CameraSocket
        do {
            let token = try await connection.accessToken()
            opened = try await socketFactory(CameraRoutes.socketURL(server: server, path: path), token)
        } catch {
            return false
        }
        guard id == generation else {
            opened.close()
            return false
        }
        socket = opened
        var decoder = CameraFrameDecoder()
        var assembler = CameraSegmentAssembler()
        var didReceive = false
        while true {
            let message: Data?
            do {
                message = try await opened.receive()
            } catch {
                break
            }
            guard id == generation else {
                opened.close()
                return didReceive
            }
            guard let message else { break }
            didReceive = true
            sessionDeliveredFrames = true
            lastFrameAt = Date()
            for frame in decoder.append(message) {
                if let event = assembler.accept(frame) { handle(event) }
            }
        }
        return didReceive
    }

    private func closeSocket() {
        socket?.close()
        socket = nil
    }

    private func stopSessions() {
        readTask?.cancel()
        readTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        clipTask?.cancel()
        clipTask = nil
        closeSocket()
        isWindowOpen = false
        clipPlayer.pause()
        if surface == .clips { clipPlayer.replaceCurrentItem(with: nil) }
    }

    private func resetStream(removingImage: Bool) {
        configuration = nil
        stitcher = nil
        hasClockStarted = false
        bufferedEndAxisSeconds = 0
        renderer.reset(removingImage: removingImage)
    }

    // MARK: the frames

    private func handle(_ event: CameraStreamEvent) {
        switch event {
        case .codec:
            break
        case .initSegment(let data):
            // A window after the first repeats the initialization segment; the codec is the same within a session.
            guard configuration == nil else { return }
            do {
                guard let video = try CameraMP4.parseInitSegment(data).video else { throw CameraMP4Error.noVideoTrack }
                guard renderer.configure(video) else { throw CameraMP4Error.malformedConfiguration }
                configuration = video
                stitcher = CameraStitcher(configuration: video, expectedEpochMS: mode == .live ? Self.nowMS : requestedStartMS)
            } catch {
                unsupportedVideo()
            }
        case .fragment(let data):
            handleFragment(data)
        }
    }

    private func unsupportedVideo() {
        closeSocket()
        readTask?.cancel()
        status = .failed
        notice = String(localized: "This camera's video format is not supported.")
        generation += 1
    }

    private func handleFragment(_ data: Data) {
        guard let configuration, let samples = stitcher?.stitch(data), let first = samples.first, let last = samples.last else { return }
        windowDeliveredFrames = true
        failures = 0
        notice = nil
        let timescale = Double(configuration.timescale)
        let firstSeconds = Double(first.presentationTicks) / timescale
        if !hasClockStarted {
            hasClockStarted = true
            if mode == .live {
                renderer.setClock(seconds: firstSeconds - CameraLiveSync.cushionSeconds, rate: 1)
            } else {
                let askedSeconds = stitcher?.axisSeconds(forEpochMS: requestedStartMS) ?? firstSeconds
                renderer.setClock(seconds: max(askedSeconds, firstSeconds), rate: isPaused ? 0 : speed)
            }
        } else if mode == .live, let rebased = CameraLiveSync.rebasedSeconds(leadSeconds: firstSeconds - renderer.clockSeconds, firstFrameSeconds: firstSeconds) {
            renderer.setClock(seconds: rebased, rate: 1)
        }
        renderer.enqueue(samples)
        bufferedEndAxisSeconds = max(bufferedEndAxisSeconds, Double(last.presentationTicks + last.durationTicks) / timescale)
        if status != .playing { status = .playing }
        reconnectTask?.cancel()
    }

    // MARK: the clock

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard hasStarted else { return }
        if surface == .clips {
            if status == .playing, clipPlayer.currentItem != nil {
                playheadMS = min(clipActualStartMS + clipPlayer.currentTime().seconds * 1000, Self.nowMS)
                if !isPaused { advanceClip() }
            }
            return
        }
        if hasClockStarted, let stitcher, !(mode == .live && isPaused) {
            playheadMS = min(stitcher.epochMS(forAxisSeconds: renderer.clockSeconds), Self.nowMS)
        }
        switch mode {
        case .live:
            if !isPaused, status == .playing || status == .connecting,
                CameraStreamHealth.isStalled(lastFrameAt: lastFrameAt, now: Date())
            {
                status = .stalled
                failSession()
            }
        case .recorded:
            manageWindows()
        }
    }
}
