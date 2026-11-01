import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// CameraRoutes builds the paths of Portal's UniFi Protect proxy
/// (`/api/v1/unifiprotect/{controllerId}/...`). Each takes the controller
/// that serves the camera and the NVR's own camera id.
public enum CameraRoutes {
    /// The characters allowed in one path segment.
    private static let segmentCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

    private static func segment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: segmentCharacters) ?? text
    }

    private static func base(_ controllerId: String) -> String { "/api/v1/unifiprotect/\(segment(controllerId))" }

    public static func bootstrapPath(controllerId: String) -> String { "\(base(controllerId))/bootstrap" }

    /// The still image of a camera. Without a moment it is the live frame; with one, the recorded frame at that moment (on the
    /// channel given). `cacheBust` makes a repeated live request ask for a new picture, since the NVR lets the old one be cached for an hour.
    public static func snapshotPath(controllerId: String, cameraId: String, atMS: Double? = nil, channel: Int? = nil, cacheBust: Int? = nil) -> String {
        var query: [String] = []
        if let atMS {
            query.append("ts=\(Int64(atMS.rounded()))")
            if let channel { query.append("channel=\(channel)") }
        }
        if let cacheBust { query.append("t=\(cacheBust)") }
        let suffix = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return "\(base(controllerId))/snapshot/\(segment(cameraId))\(suffix)"
    }

    /// The most a single clip export may cover; a longer selection is downloaded as consecutive clips.
    public static let maximumExportMS: Double = 30 * 60_000

    /// A clip of the recording, as an MP4 file.
    public static func exportPath(controllerId: String, cameraId: String, channel: Int, startMS: Double, endMS: Double, isDownload: Bool = false) -> String {
        var path = "\(base(controllerId))/video/export?camera=\(segment(cameraId))&channel=\(channel)&start=\(Int64(startMS.rounded()))&end=\(Int64(endMS.rounded()))"
        if isDownload { path += "&download=true" }
        return path
    }

    public static func livePath(controllerId: String, cameraId: String, channel: Int) -> String {
        "\(base(controllerId))/livestream/\(segment(cameraId))?channel=\(channel)"
    }

    public static func playbackPath(controllerId: String, cameraId: String, channel: Int, startMS: Double, endMS: Double) -> String {
        "\(base(controllerId))/playback/\(segment(cameraId))?channel=\(channel)&start=\(Int64(startMS.rounded()))&end=\(Int64(endMS.rounded()))"
    }

    /// The address a websocket dials for a path: the server's, with `wss` for `https`.
    public static func socketURL(server: ServerAddress, path: String) -> URL {
        var components = URLComponents(url: server.endpoint(path), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        return components.url!
    }

    /// Clips of a selection, none longer than the export allows, contiguous and in order.
    public static func exportClips(startMS: Double, endMS: Double) -> [(startMS: Double, endMS: Double)] {
        guard endMS > startMS else { return [] }
        var clips: [(startMS: Double, endMS: Double)] = []
        var clipStart = startMS
        while clipStart < endMS {
            clips.append((clipStart, min(clipStart + maximumExportMS, endMS)))
            clipStart += maximumExportMS
        }
        return clips
    }
}

// MARK: - socket

/// CameraSocket is the websocket under a camera stream: URLSession's in the
/// app, a recording in the demo and in tests.
public protocol CameraSocket: Sendable {
    /// The next message's bytes, or nil once the socket has ended, whoever ended it.
    func receive() async throws -> Data?
    func close()
}

/// Opens a socket to an address of the server with the bearer token on the upgrade request.
public typealias CameraSocketFactory = @Sendable (_ url: URL, _ accessToken: String) async throws -> any CameraSocket

#if canImport(Darwin)
    /// URLSessionCameraSocket is a camera socket on URLSession.
    public final class URLSessionCameraSocket: CameraSocket, @unchecked Sendable {
        private let task: URLSessionWebSocketTask

        init(task: URLSessionWebSocketTask) {
            self.task = task
        }

        public func receive() async throws -> Data? {
            do {
                switch try await task.receive() {
                case .data(let data): return data
                case .string(let text): return Data(text.utf8)
                @unknown default: return nil
                }
            } catch {
                return nil
            }
        }

        public func close() {
            task.cancel(with: .goingAway, reason: nil)
        }

        /// The real socket. The upgrade request carries the token, which is where Portal reads it; a native client sends no Origin.
        public static let factory: CameraSocketFactory = { url, accessToken in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let task = URLSession.shared.webSocketTask(with: request)
            // A key frame at a high bitrate is bigger than the default limit of one message.
            task.maximumMessageSize = 16 * 1024 * 1024
            task.resume()
            return URLSessionCameraSocket(task: task)
        }
    }
#endif

// MARK: - playback transport

/// CameraPlaybackTransport is how a controller serves recorded footage.
public enum CameraPlaybackTransport: Equatable, Sendable {
    /// The `playback` websocket of newer controller software.
    case webSocket
    /// Older software has none: clips are downloaded from `video/export` and played one after another.
    case exportClips
}

/// CameraTransportProbe is what asking a controller whether it has the playback websocket found out.
public enum CameraTransportProbe: Equatable, Sendable {
    case found(CameraPlaybackTransport)
    /// The controller could not be asked (offline, or the network failed). Nothing is learned, so nothing is remembered.
    case unreachable
}

/// CameraTransportRules decides which transport a probe or a failed dial means.
public enum CameraTransportRules {
    /// A plain GET to a websocket route is answered 400 when the route exists (the upgrade header is missing). A controller
    /// without the route sends its page for any unknown address (200), and a Portal without the proxy route says 404. An offline
    /// controller is a 502, which says nothing about the route.
    public static func probe(statusCode: Int?) -> CameraTransportProbe {
        guard let statusCode else { return .unreachable }
        if statusCode == 400 { return .found(.webSocket) }
        if [502, 503, 504].contains(statusCode) { return .unreachable }
        return .found(.exportClips)
    }

    /// A socket the server refused to upgrade before sending a single frame means the route is not there after all, whatever the probe said.
    public static func transportAfterDial(didReceiveFrame: Bool) -> CameraPlaybackTransport? {
        didReceiveFrame ? nil : .exportClips
    }
}

/// CameraTransportMemory remembers, for the life of the process, which transport each controller has.
public final class CameraTransportMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [String: CameraPlaybackTransport] = [:]

    public init() {}

    public func transport(forController controllerId: String) -> CameraPlaybackTransport? {
        lock.lock()
        defer { lock.unlock() }
        return transports[controllerId]
    }

    public func remember(_ transport: CameraPlaybackTransport, forController controllerId: String) {
        lock.lock()
        defer { lock.unlock() }
        transports[controllerId] = transport
    }
}

extension Connection {
    /// Asks the controller whether it serves recorded footage over a websocket, with one cheap GET.
    public func probePlaybackTransport(controllerId: String, cameraId: String) async -> CameraTransportProbe {
        var request = URLRequest(url: server.endpoint(CameraRoutes.playbackPath(controllerId: controllerId, cameraId: cameraId, channel: 0, startMS: 1, endMS: 2)))
        request.timeoutInterval = 15
        let status = try? await send(authorizing: request).1.statusCode
        return CameraTransportRules.probe(statusCode: status)
    }
}

// MARK: - health

/// CameraStreamHealth holds the timing rules for noticing that a live stream
/// broke and for pacing the reconnects. They are the web player's.
public enum CameraStreamHealth {
    /// How long the socket may go quiet before the stream counts as broken.
    public static let stallTimeout: TimeInterval = 10
    /// How often the watch looks.
    public static let checkInterval: TimeInterval = 2
    /// Failures in a row after which the player stops trying by itself and waits for the person.
    public static let maximumAutomaticAttempts = 6
    public static let baseDelay: TimeInterval = 1
    public static let maximumDelay: TimeInterval = 30

    /// Whether the socket has been quiet too long. No frame yet is not a stall: there is nothing to measure from.
    public static func isStalled(lastFrameAt: Date?, now: Date) -> Bool {
        guard let lastFrameAt else { return false }
        return now.timeIntervalSince(lastFrameAt) >= stallTimeout
    }

    /// The pause before reconnecting, given how many failures in a row there have been, counting from one.
    public static func reconnectDelay(consecutiveFailures: Int) -> TimeInterval {
        let failures = max(1, consecutiveFailures)
        return min(baseDelay * pow(2, Double(failures - 1)), maximumDelay)
    }

    public static func canReconnectAutomatically(consecutiveFailures: Int) -> Bool {
        consecutiveFailures <= maximumAutomaticAttempts
    }
}

/// CameraStreamStatus is what the picture's overlay says about the stream.
public enum CameraStreamStatus: Equatable, Sendable {
    case idle
    case connecting
    case playing
    /// The socket is open but has stopped carrying frames.
    case stalled
    /// The stream broke and the player is waiting to try again.
    case reconnecting
    /// It broke and automatic attempts are used up: only the person can retry.
    case failed
    /// A recorded window reached the end of what exists.
    case ended

    /// A stream in one of these states can only be rebuilt, not resumed.
    public var needsReconnect: Bool { self == .stalled || self == .failed }
}

// MARK: - playback windows

/// CameraPlaybackWindows plans which recorded window to ask for next. The NVR
/// sends a requested window as fast as the link allows and then leaves the
/// socket open and silent, never saying it is done. So a recording plays as
/// consecutive windows of a minute, one socket each, and the next one is
/// opened when the footage ahead of the playhead runs low.
public struct CameraPlaybackWindows: Equatable, Sendable {
    public static let windowMS: Double = 60_000
    /// Silence this long after a frame means the window has been delivered.
    public static let idleSeconds: TimeInterval = 2.5
    /// A window that has sent no frame by now is empty: there is no recording in it.
    public static let firstFrameTimeout: TimeInterval = 6
    /// Footage kept ahead of the playhead, in seconds of recording at 1x. Faster playback eats it faster, so it scales with the speed.
    public static let leadSeconds: Double = 20

    /// A window that sent nothing before the idle time ran out is a gap in the recording. The next one is asked for twice as long (up to
    /// this) so a gap is crossed quickly; the NVR only sends what exists, so a longer window costs nothing where there is no footage.
    public static let maximumGrowthMS: Double = 15 * 60_000
    /// After this many empty windows in a row there is no footage to be found ahead.
    public static let maximumEmptyWindows = 8

    public enum Plan: Equatable, Sendable {
        /// Ask the NVR for this window, in epoch milliseconds.
        case open(startMS: Double, endMS: Double)
        /// Enough is buffered, or a window is still arriving.
        case wait
        /// Everything up to the end has been asked for.
        case finished
        /// Several windows in a row held nothing: there is no recording here.
        case noRecording
    }

    public private(set) var nextStartMS: Double
    public private(set) var consecutiveEmptyWindows = 0
    public let endMS: Double

    /// `startMS` is where to begin; `endMS` is the end of what may be watched (now, or the end of a clip).
    public init(startMS: Double, endMS: Double) {
        self.nextStartMS = startMS
        self.endMS = endMS
    }

    /// Records how a window ended: with frames, or with none.
    public mutating func windowEnded(didDeliverFrames: Bool) {
        consecutiveEmptyWindows = didDeliverFrames ? 0 : consecutiveEmptyWindows + 1
    }

    /// The length of the next window: a minute, longer after empty windows.
    public var nextWindowMS: Double {
        min(Self.windowMS * pow(2, Double(consecutiveEmptyWindows)), Self.maximumGrowthMS)
    }

    /// `bufferedEndMS` is the recording moment up to which frames have arrived; `playheadMS` is where the picture is; `speed` is the playback rate.
    public mutating func plan(bufferedEndMS: Double, playheadMS: Double, speed: Double, isWindowOpen: Bool) -> Plan {
        if isWindowOpen { return .wait }
        if consecutiveEmptyWindows >= Self.maximumEmptyWindows { return .noRecording }
        if nextStartMS >= endMS - 250 { return .finished }
        // After an empty window there is nothing buffered to wait on: go on at once.
        let neededLeadMS = Self.leadSeconds * 1000 * max(1, speed)
        if consecutiveEmptyWindows == 0, bufferedEndMS - playheadMS >= neededLeadMS { return .wait }
        let windowStart = nextStartMS
        let windowEnd = min(windowStart + nextWindowMS, endMS)
        nextStartMS = windowEnd
        return .open(startMS: windowStart, endMS: windowEnd)
    }
}

/// CameraSpeed is the playback rates the speed menu offers.
public enum CameraSpeed {
    public static let rates: [Double] = [0.25, 0.5, 1, 1.5, 2, 4, 8, 16]
}
