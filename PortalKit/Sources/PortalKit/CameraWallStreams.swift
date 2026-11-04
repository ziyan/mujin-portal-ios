import Foundation

/// CameraWallStreams decides which tiles of a wall of cameras play live video. Every visible tile asks for a stream; the first ones asked
/// get one, up to a limit, and the rest keep showing their still picture. When a tile leaves the screen its stream goes to the tile that
/// has waited longest.
public struct CameraWallStreams: Equatable, Sendable {
    /// How many tiles stream at once. Each is a socket to the NVR and a video decoder, so a wall of dozens must not open them all.
    public static let defaultLimit = 6

    /// A tile plays the least sharp channel: it is a few hundred points wide, and the sharp channels cost several times the bandwidth.
    public static let tileQuality = CameraQuality.low

    public let limit: Int
    public private(set) var streamingIds: [String] = []
    public private(set) var waitingIds: [String] = []
    /// Tiles whose stream failed for good. They keep showing that, hold no stream and ask for none until they leave the screen.
    public private(set) var failedIds: [String] = []

    public init(limit: Int = CameraWallStreams.defaultLimit) {
        self.limit = max(0, limit)
    }

    public func isStreaming(_ cameraId: String) -> Bool { streamingIds.contains(cameraId) }

    /// Whether the tile is visible and has no stream because the limit is reached.
    public func isWaiting(_ cameraId: String) -> Bool { waitingIds.contains(cameraId) }

    /// Whether the tile's stream failed for good (refused, or no route) and is not tried again while the tile stays on screen.
    public func hasFailed(_ cameraId: String) -> Bool { failedIds.contains(cameraId) }

    /// A tile appeared. It gets a stream when one is free, and otherwise waits for one. Asking again changes nothing.
    public mutating func request(_ cameraId: String) {
        guard !isStreaming(cameraId), !isWaiting(cameraId), !hasFailed(cameraId) else { return }
        if streamingIds.count < limit {
            streamingIds.append(cameraId)
        } else {
            waitingIds.append(cameraId)
        }
    }

    /// A tile's stream failed for good. Its stream goes at once to the tile that has waited longest, and the tile asks for none again until it
    /// has left the screen and come back.
    public mutating func fail(_ cameraId: String) {
        guard isStreaming(cameraId) else { return }
        release(cameraId)
        failedIds.append(cameraId)
    }

    /// A tile left the screen. Its stream, if it had one, goes to the tile that has waited longest.
    public mutating func release(_ cameraId: String) {
        failedIds.removeAll { $0 == cameraId }
        waitingIds.removeAll { $0 == cameraId }
        guard let index = streamingIds.firstIndex(of: cameraId) else { return }
        streamingIds.remove(at: index)
        if !waitingIds.isEmpty { streamingIds.append(waitingIds.removeFirst()) }
    }
}
