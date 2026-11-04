import Foundation

/// CameraWallStreams decides which tiles of a wall of cameras play live video. A tile asks for a stream while it is on screen and gives
/// it back when it leaves, so only tiles that can be seen hold one. The first ones asked get a stream, up to a limit; the rest wait and
/// take a stream, longest waiting first, when one is given back.
public struct CameraWallStreams: Equatable, Sendable {
    /// How many tiles stream at once on a phone: a full screen of tiles at the largest layout, with a few to spare for a scroll. Each is a
    /// socket to the NVR and a video decoder.
    public static let phoneLimit = 12
    /// ... and on a tablet, which shows many more tiles at once. It is also the ceiling: a wall never streams more than this.
    public static let tabletLimit = 30

    /// A tile plays the least sharp channel: it is a few hundred points wide, and the sharp channels cost several times the bandwidth.
    public static let tileQuality = CameraQuality.low

    public let limit: Int
    public private(set) var streamingIds: [String] = []
    public private(set) var waitingIds: [String] = []
    /// Tiles whose stream failed for good (refused, or no route). They hold no stream and ask for none until they leave the screen.
    public private(set) var failedIds: [String] = []
    /// Tiles whose stream ran out of retries. They hold no stream; one is tried again when a tile leaving the screen frees a stream, or when
    /// the tile itself leaves and comes back.
    public private(set) var exhaustedIds: [String] = []

    public init(limit: Int = CameraWallStreams.phoneLimit) {
        self.limit = min(max(0, limit), Self.tabletLimit)
    }

    public func isStreaming(_ cameraId: String) -> Bool { streamingIds.contains(cameraId) }

    /// Whether the tile is on screen and has no stream because the limit is reached.
    public func isWaiting(_ cameraId: String) -> Bool { waitingIds.contains(cameraId) }

    /// Whether the tile's stream failed, for good or for want of retries, so it shows that and holds no stream.
    public func hasFailed(_ cameraId: String) -> Bool { failedIds.contains(cameraId) || exhaustedIds.contains(cameraId) }

    /// A tile came on screen. It gets a stream when one is free, and otherwise waits for one. Asking again changes nothing.
    public mutating func request(_ cameraId: String) {
        guard !isStreaming(cameraId), !isWaiting(cameraId), !hasFailed(cameraId) else { return }
        if streamingIds.count < limit {
            streamingIds.append(cameraId)
        } else {
            waitingIds.append(cameraId)
        }
    }

    /// A tile's stream failed. Its stream goes at once to the tile that has waited longest. A final failure (`isFinal`) is not tried again
    /// until the tile has left the screen and come back; one that only ran out of retries is tried again when a stream is freed by a tile
    /// leaving, and not by another tile's failure, so two bad tiles never hand one stream back and forth.
    public mutating func fail(_ cameraId: String, isFinal: Bool = true) {
        guard isStreaming(cameraId) else { return }
        streamingIds.removeAll { $0 == cameraId }
        if isFinal { failedIds.append(cameraId) } else { exhaustedIds.append(cameraId) }
        promoteWaiting()
    }

    /// A tile left the screen. Its stream, if it had one, goes to the tile that has waited longest, and then to a tile that ran out of retries.
    public mutating func release(_ cameraId: String) {
        failedIds.removeAll { $0 == cameraId }
        exhaustedIds.removeAll { $0 == cameraId }
        waitingIds.removeAll { $0 == cameraId }
        guard let index = streamingIds.firstIndex(of: cameraId) else { return }
        streamingIds.remove(at: index)
        promoteWaiting()
        while streamingIds.count < limit, !exhaustedIds.isEmpty { streamingIds.append(exhaustedIds.removeFirst()) }
    }

    /// Lets go of every tile that is not in `cameraIds`: the wall was filtered or reloaded and those tiles are gone, whether or not their
    /// views said so.
    public mutating func retain(_ cameraIds: Set<String>) {
        let gone = (streamingIds + waitingIds + failedIds + exhaustedIds).filter { !cameraIds.contains($0) }
        for cameraId in gone { release(cameraId) }
    }

    private mutating func promoteWaiting() {
        while streamingIds.count < limit, !waitingIds.isEmpty { streamingIds.append(waitingIds.removeFirst()) }
    }
}
