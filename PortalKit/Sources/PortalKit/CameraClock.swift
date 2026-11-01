import Foundation

/// CameraClock is the clock a camera's recording is read on. A time stamp from
/// an NVR answers a question about the place the camera is in (when the
/// forklift crossed the aisle, which shift it was), so it is shown in the
/// NVR's zone and never the phone's. When the zone is not known, the phone's
/// is used and the screen says so.
public struct CameraClock: Equatable, Sendable {
    public let timeZone: TimeZone
    /// False when the zone is the phone's because the NVR's is unknown.
    public let isControllerZone: Bool

    public init(identifier: String?) {
        if let identifier, !identifier.isEmpty, let zone = TimeZone(identifier: identifier) {
            self.timeZone = zone
            self.isControllerZone = true
        } else {
            self.timeZone = .current
            self.isControllerZone = false
        }
    }

    public init(timeZone: TimeZone, isControllerZone: Bool = true) {
        self.timeZone = timeZone
        self.isControllerZone = isControllerZone
    }

    /// The zone's short name at a moment, such as `CST`, which follows daylight saving.
    public func zoneLabel(atMS timeMS: Double) -> String {
        timeZone.abbreviation(for: Date(timeIntervalSince1970: timeMS / 1000)) ?? timeZone.identifier
    }

    /// Hours, minutes and seconds past midnight on this clock, for ticks and tests.
    public func secondsSinceMidnight(atMS timeMS: Double) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: Date(timeIntervalSince1970: timeMS / 1000))
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    /// The offset from UTC in seconds at a moment.
    public func offsetSeconds(atMS timeMS: Double) -> Int {
        timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: timeMS / 1000))
    }
}
