import Foundation

/// VideoQuality is how much of a person's video this phone wants: the whole stage, a small tile, or none.
public enum VideoQuality: String, Equatable, Sendable {
    case full
    case small
    case off
}

/// CallSubscriptionPlan says which video this phone wants from each other person, from what is on the screen: full for the main stage,
/// small for the strip tiles in view, off for tiles scrolled out of view and for everyone not shown. Outside the speaker view a tile asks
/// for full when it is at least 360 by 270 points, else small. A minimized call asks for nothing.
public enum CallSubscriptionPlan {
    /// The size of a tile on the screen, in points.
    public struct TileSize: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public static let fullTileWidth = 360.0
    public static let fullTileHeight = 270.0

    public static func plan(
        remoteUserIds: [String], mainUserId: String?, visibleStripUserIds: Set<String>, isSpeakerView: Bool, tileSizes: [String: TileSize] = [:],
        isMinimized: Bool = false
    ) -> [String: VideoQuality] {
        var result: [String: VideoQuality] = [:]
        for userId in remoteUserIds {
            if isMinimized {
                result[userId] = .off
            } else if !isSpeakerView {
                // The stage is large; a grid tile asks for full only when it is large enough to show it.
                if let size = tileSizes[userId] {
                    result[userId] = size.width >= fullTileWidth && size.height >= fullTileHeight ? .full : .small
                } else {
                    result[userId] = .full
                }
            } else if userId == mainUserId {
                result[userId] = .full
            } else {
                result[userId] = visibleStripUserIds.contains(userId) ? .small : .off
            }
        }
        return result
    }

    /// The most entries one request holds.
    public static let maximumEntriesPerRequest = 64

    /// Whether the error means the server has no such request, which is the only failure not worth trying again: anything else, such as
    /// a timeout on a poor network, would otherwise leave the phone on the small layer for the rest of the call.
    public static func isSelectionUnsupported(by error: Error) -> Bool {
        if case PortalError.refused(let message) = error { return message.contains("Cannot query field") }
        return false
    }

    /// How long to wait before asking again after this many failures in a row, or nil to stop asking until the choice changes: a request
    /// that keeps failing, such as one the person is no longer allowed to make, is not repeated for the rest of the call.
    public static func retryDelayNanoseconds(afterFailureCount failureCount: Int, error: Error) -> UInt64? {
        guard (error as? PortalError) != .notPermitted, failureCount >= 1, failureCount <= 5 else { return nil }
        return 2_000_000_000 << UInt64(failureCount - 1)
    }

    /// What to tell the server: only the people whose choice differs from what it already has (everyone starts at small), or every one when
    /// `resendAll` is set, as after a reconnect.
    public static func changes(from sent: [String: VideoQuality], to plan: [String: VideoQuality], resendAll: Bool = false) -> [(userId: String, videoQuality: VideoQuality)] {
        plan.keys.sorted().compactMap { userId in
            guard let wanted = plan[userId] else { return nil }
            if resendAll || (sent[userId] ?? .small) != wanted { return (userId, wanted) }
            return nil
        }
    }
}

/// ActiveSpeaker picks who is on the main stage while the phone follows the speaker. The person talking now is chosen, but a change
/// waits for a short while after the last one, so the stage does not jump at every word.
public struct ActiveSpeaker: Equatable, Sendable {
    /// The least time between two changes.
    public static let dwell: TimeInterval = 1.5

    public private(set) var userId: String?
    private var changedAt = Date.distantPast

    public init() {}

    /// `candidates` is everyone who could be on the stage, in a stable order; `speaking` is who is speaking now. Other people come
    /// before the person themself, who is shown only when nobody else is.
    public mutating func update(speaking: Set<String>, candidates: [String], selfUserId: String, now: Date = Date()) -> String? {
        let others = candidates.filter { $0 != selfUserId }
        if let current = userId, !candidates.contains(current) { userId = nil }
        let talking = others.filter { speaking.contains($0) }
        if userId == nil {
            userId = talking.first ?? others.first ?? candidates.first
            changedAt = now
            return userId
        }
        if let current = userId, speaking.contains(current) { return current }
        if let next = talking.first, next != userId, now.timeIntervalSince(changedAt) >= Self.dwell {
            userId = next
            changedAt = now
        }
        return userId
    }
}

extension CallTiling {
    /// From this many people on screen the stage shows one person large and the others in a strip.
    public static let speakerViewMinimum = 5

    public static func usesSpeakerView(count: Int) -> Bool { count >= speakerViewMinimum }
}
