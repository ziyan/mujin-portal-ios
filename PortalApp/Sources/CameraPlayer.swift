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
/// the reconnects with backoff, and the windows of a recording. Live and
/// recorded video both come over a websocket; clips are only downloaded to be
/// shared. The screen reads its state and calls its controls.
///
/// Video is decoded by the system: the NVR's fragmented MP4 is cut into
/// frames (PortalKit) and handed to an `AVSampleBufferDisplayLayer`, whose
/// clock is the stream's time, so a pause is a rate of zero and a speed is a
/// rate. The sound, when asked for, is played on that same clock.
@MainActor
@Observable
final class CameraPlayer {
    enum Mode: Equatable {
        case live
        case recorded
    }

    let camera: Camera
    private(set) var mode = Mode.live
    private(set) var status = CameraStreamStatus.idle
    /// Where the picture is, in milliseconds since 1970. While live it is the newest frame shown.
    private(set) var playheadMS: Double
    private(set) var isPaused = false
    private(set) var speed = 1.0
    /// Whether the stream has sound that can be played. Known once the stream's first initialization segment is read.
    private(set) var hasSound = false
    /// Sound starts off, so opening a camera never interrupts what the person is listening to.
    private(set) var isSoundOn = false
    /// Whether the controller's software is too old to have recorded playback, so only live video and downloaded clips work.
    private(set) var isRecordingUnsupported = false
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

    private let connection: Connection
    private static var refusedNotice: String { String(localized: "Portal did not allow this camera's video. Ask an administrator for access.") }
    private let server: ServerAddress
    private let socketFactory: CameraSocketFactory
    private let isDemo: Bool

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var socket: (any CameraSocket)?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
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
    /// Whether the open window has brought footage that was not already shown by the window before it.
    @ObservationIgnored private var windowAddedFootage = false
    /// Whether the clock waits for footage that has not arrived yet.
    @ObservationIgnored private var isHoldingForFootage = false
    @ObservationIgnored private var suspendedAtMS: Double?
    @ObservationIgnored private var wasSuspendedPaused = false

    init(
        camera: Camera, clock: CameraClock, connection: Connection, server: ServerAddress, socketFactory: @escaping CameraSocketFactory, isDemo: Bool
    ) {
        self.camera = camera
        self.clock = clock
        self.connection = connection
        self.server = server
        self.socketFactory = socketFactory
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
        isRecordingUnsupported = false
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
        setSound(on: false)
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
        renderer.setRate(isHoldingForFootage ? 0 : speed)
    }

    // MARK: sound

    /// Turns the sound on or off. It is on only while the person asked for it, and only for a stream that has some.
    func toggleSound() {
        setSound(on: !isSoundOn)
    }

    private func setSound(on isOn: Bool) {
        guard isOn != isSoundOn, !isOn || hasSound else { return }
        isSoundOn = isOn
        renderer.setSound(on: isOn)
    }

    // MARK: live

    private func beginLive(keepingPicture: Bool) {
        mode = .live
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
            // One snapshot request tells a refusal from a camera that is down, so the person is told which.
            Task { [weak self] in
                guard let self else { return }
                if await self.connection.snapshotFailure(controllerId: self.camera.controllerId, cameraId: self.camera.originCameraId) == .notAllowed, self.status == .failed {
                    self.notice = Self.refusedNotice
                }
            }
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
        status = .connecting
        resetStream(removingImage: true)
        playheadMS = requestedMS
        requestedStartMS = requestedMS
        windows = CameraPlaybackWindows(startMS: requestedMS, endMS: Self.nowMS)
        // The first window opens on the next tick of the clock, which looks at what is buffered and what is still to ask for.
    }

    private func manageWindows() {
        guard mode == .recorded, windows != nil else { return }
        if isWindowOpen {
            let quietFor = Date().timeIntervalSince(lastFrameAt ?? windowOpenedAt)
            let limit = windowDeliveredFrames ? CameraPlaybackWindows.idleSeconds : CameraPlaybackWindows.firstFrameTimeout
            if quietFor >= limit { endWindow() }
        }
        holdOrResumeClock()
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
        isWindowOpen = true
        windowOpenedAt = Date()
        lastFrameAt = nil
        windowDeliveredFrames = false
        windowAddedFootage = false
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
        guard !didReceiveFrame else {
            endWindow()
            return
        }
        // A socket that ended without a single byte was refused or never reached the controller. An empty stretch of the recording is
        // different: the NVR leaves that socket open and silent, and it is ended from here when it has been quiet long enough.
        isWindowOpen = false
        closeSocket()
        failRecordedSession()
    }

    /// The recorded stream cannot be had. One plain GET to the playback route, made only now that the dial failed, says why: Portal refused
    /// it, the controller's software has no such route, or the controller does not answer.
    private func failRecordedSession() {
        status = .failed
        notice = String(localized: "The controller is offline.")
        let generationAtFailure = generation
        Task { [weak self] in
            guard let self else { return }
            let failure = await self.connection.playbackFailure(controllerId: self.camera.controllerId, cameraId: self.camera.originCameraId)
            guard generationAtFailure == self.generation, self.status == .failed else { return }
            switch failure {
            case .notAllowed:
                self.notice = Self.refusedNotice
            case .unsupported:
                self.isRecordingUnsupported = true
                self.notice = String(localized: "Recorded video needs a newer controller version.")
            case .unreachable:
                break
            }
        }
    }

    private func endWindow() {
        guard isWindowOpen else { return }
        isWindowOpen = false
        closeSocket()
        let bufferedEndMS = stitcher.map { $0.epochMS(forAxisSeconds: bufferedEndAxisSeconds) }
        windows?.windowEnded(didDeliverFootage: windowAddedFootage, bufferedEndMS: bufferedEndMS)
        if !windowAddedFootage, status != .ended {
            notice = String(localized: "Looking for the next recording.")
        }
    }

    /// The clock stops when it has caught up with the footage that arrived while more is still coming, and goes on when a second of it is
    /// ahead again. Without this a window that is slow to start is shown by skipping the seconds the clock has run on meanwhile.
    private func holdOrResumeClock() {
        guard hasClockStarted, !isPaused, status != .failed, status != .ended, let windows else { return }
        let step = CameraPlaybackBuffering.step(
            isHolding: isHoldingForFootage, leadSeconds: bufferedEndAxisSeconds - renderer.clockSeconds,
            isMoreComing: windows.hasMoreComing(isWindowOpen: isWindowOpen))
        switch step {
        case .keep:
            break
        case .hold:
            isHoldingForFootage = true
            renderer.setRate(0)
            status = .connecting
        case .resume:
            isHoldingForFootage = false
            renderer.setRate(speed)
            status = .playing
        }
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
        closeSocket()
        isWindowOpen = false
    }

    private func resetStream(removingImage: Bool) {
        configuration = nil
        stitcher = nil
        hasClockStarted = false
        isHoldingForFootage = false
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
                let segment = try CameraMP4.parseInitSegment(data)
                guard let video = segment.video else { throw CameraMP4Error.noVideoTrack }
                guard renderer.configure(video) else { throw CameraMP4Error.malformedConfiguration }
                configuration = video
                renderer.configureAudio(segment.audio)
                // The demo's test pattern has no sound; it claims some so that the button can be photographed.
                hasSound = renderer.canPlaySound || isDemo
                if !hasSound { setSound(on: false) }
                stitcher = CameraStitcher(configuration: video, audio: segment.audio, expectedEpochMS: mode == .live ? Self.nowMS : requestedStartMS)
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
        guard let configuration, let stitched = stitcher?.stitchAll(data), let first = stitched.video.first, let last = stitched.video.last else { return }
        let samples = stitched.video
        windowDeliveredFrames = true
        if samples.contains(where: \.isDisplayed) { windowAddedFootage = true }
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
        renderer.enqueueAudio(stitched.audio)
        bufferedEndAxisSeconds = max(bufferedEndAxisSeconds, Double(last.presentationTicks + last.durationTicks) / timescale)
        if status != .playing, !isHoldingForFootage { status = .playing }
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
