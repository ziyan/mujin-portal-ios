import Foundation

/// VideoQuality is how much of a person's video this phone wants: the whole stage, a small tile, or none.
public enum VideoQuality: String, Equatable, Sendable {
    case full
    case small
    case off
}

/// CallSubscriptionPlan says which video this phone wants from each other person, from what is on the screen: full for the main stage,
/// small for the strip tiles in view, off for tiles scrolled out of view and for everyone not shown.
public enum CallSubscriptionPlan {
    public static func plan(remoteUserIds: [String], mainUserId: String?, visibleStripUserIds: Set<String>, isSpeakerView: Bool) -> [String: VideoQuality] {
        var result: [String: VideoQuality] = [:]
        for userId in remoteUserIds {
            if !isSpeakerView {
                // The stage and the grid's tiles are large.
                result[userId] = .full
            } else if userId == mainUserId {
                result[userId] = .full
            } else {
                result[userId] = visibleStripUserIds.contains(userId) ? .small : .off
            }
        }
        return result
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
