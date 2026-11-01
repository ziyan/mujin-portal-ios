import Foundation

/// CameraTimeWindow is the stretch of time the timeline strip shows, in
/// milliseconds since 1970.
public struct CameraTimeWindow: Equatable, Sendable {
    public var startMS: Double
    public var endMS: Double

    public init(startMS: Double, endMS: Double) {
        self.startMS = startMS
        self.endMS = endMS
    }

    public var spanMS: Double { endMS - startMS }
}

/// CameraTimeline is the time arithmetic of the camera timeline: the visible
/// window, its zoom levels, the ruler's ticks and the moments a link or a
/// date jump lands on. It is the web player's, so both show the same thing.
public enum CameraTimeline {
    public static let minuteMS: Double = 60_000
    public static let hourMS: Double = 3_600_000
    public static let dayMS: Double = 24 * hourMS

    /// The zoom levels the strip offers.
    public static let zoomSpansMS: [Double] = [15 * minuteMS, hourMS, 4 * hourMS, dayMS]
    /// A stored clip of an incident is often under half a minute, so the strip may show as little as ten seconds.
    public static let minimumSpanMS: Double = 10_000
    public static let maximumSpanMS: Double = dayMS

    /// The strip of future kept to the right of now, so the live edge is not against the border.
    public static func nowMarginMS(spanMS: Double) -> Double { spanMS * 0.08 }

    public static func fraction(forTimeMS timeMS: Double, in window: CameraTimeWindow) -> Double {
        (timeMS - window.startMS) / window.spanMS
    }

    public static func timeMS(forFraction fraction: Double, in window: CameraTimeWindow) -> Double {
        window.startMS + fraction * window.spanMS
    }

    /// The window with its right edge held to now plus the margin, keeping its span.
    static func clampedToNow(_ window: CameraTimeWindow, nowMS: Double) -> CameraTimeWindow {
        let margin = nowMarginMS(spanMS: window.spanMS)
        guard window.endMS > nowMS + margin else { return window }
        let end = nowMS + margin
        return CameraTimeWindow(startMS: end - window.spanMS, endMS: end)
    }

    /// The window resized to `spanMS` with `anchorMS` staying at the same place on the strip.
    public static func resized(_ window: CameraTimeWindow, spanMS: Double, anchorMS: Double, nowMS: Double) -> CameraTimeWindow {
        let span = max(minimumSpanMS, min(spanMS, maximumSpanMS))
        let anchor = fraction(forTimeMS: anchorMS, in: window)
        let start = anchorMS - anchor * span
        return clampedToNow(CameraTimeWindow(startMS: start, endMS: start + span), nowMS: nowMS)
    }

    public static func zoomed(_ window: CameraTimeWindow, factor: Double, anchorMS: Double, nowMS: Double) -> CameraTimeWindow {
        resized(window, spanMS: window.spanMS * factor, anchorMS: anchorMS, nowMS: nowMS)
    }

    public static func panned(_ window: CameraTimeWindow, byMS deltaMS: Double, nowMS: Double) -> CameraTimeWindow {
        clampedToNow(CameraTimeWindow(startMS: window.startMS + deltaMS, endMS: window.endMS + deltaMS), nowMS: nowMS)
    }

    /// The window of a given span centered on a moment, held to now.
    public static func centered(on timeMS: Double, spanMS: Double, nowMS: Double) -> CameraTimeWindow {
        clampedToNow(CameraTimeWindow(startMS: timeMS - spanMS / 2, endMS: timeMS + spanMS / 2), nowMS: nowMS)
    }

    /// The distance between ruler ticks for a visible span.
    public static func tickStepMS(forSpanMS spanMS: Double) -> Double {
        if spanMS >= 20 * hourMS { return 3 * hourMS }
        if spanMS >= 4 * hourMS { return hourMS }
        if spanMS >= hourMS { return 15 * minuteMS }
        if spanMS >= 15 * minuteMS { return 5 * minuteMS }
        if spanMS >= minuteMS { return minuteMS }
        if spanMS >= 20_000 { return 10_000 }
        return 5_000
    }

    /// The tick moments inside a window, in order. Fixed steps: a label can drift an hour across a clock change, as on the web.
    public static func ticks(in window: CameraTimeWindow) -> [Double] {
        let step = tickStepMS(forSpanMS: window.spanMS)
        var tick = (window.startMS / step).rounded(.up) * step
        var result: [Double] = []
        while tick <= window.endMS, result.count < 200 {
            result.append(tick)
            tick += step
        }
        return result
    }

    /// An epoch-millisecond value from a link or a field, tolerant of a number, a numeric string and an ISO date. Anything else is nil.
    public static func parseTimestamp(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let milliseconds = Double(trimmed), milliseconds.isFinite { return milliseconds }
        return PortalDate.parse(trimmed).map { $0.timeIntervalSince1970 * 1000 }
    }

    /// Landing on a moment: the playhead there (never later than now) in a one hour window centered on it.
    public static func viewForMoment(timeMS: Double, nowMS: Double) -> (window: CameraTimeWindow, playheadMS: Double) {
        let playhead = min(timeMS, nowMS)
        return (centered(on: playhead, spanMS: hourMS, nowMS: nowMS), playhead)
    }
}

/// CameraClip is the stretch of the recording a person shares.
public struct CameraClip: Equatable, Sendable {
    public static let lengthsMS: [Double] = [30_000, 60_000, 5 * 60_000, 15 * 60_000, 30 * 60_000]

    public let startMS: Double
    public let endMS: Double

    /// A clip of `lengthMS` that starts `leadMS` before the playhead and never reaches past now. When the clip would end after now, it ends at
    /// now instead and keeps its length by starting earlier.
    public init(aroundMS playheadMS: Double, lengthMS: Double, leadMS: Double = 10_000, nowMS: Double) {
        let length = min(lengthMS, CameraRoutes.maximumExportMS)
        let end = min(playheadMS - leadMS + length, nowMS)
        self.startMS = end - length
        self.endMS = end
    }

    public var durationMS: Double { endMS - startMS }
}

/// CameraDayJump is a jump on the controller's calendar.
public enum CameraDayJump {
    /// A time-of-day shortcut: where it starts, in hours after midnight, and how many hours the strip then shows.
    public struct Block: Equatable, Sendable {
        public let startHour: Int
        public let spanHours: Int
    }

    public static let morning = Block(startHour: 6, spanHours: 6)
    public static let afternoon = Block(startHour: 12, spanHours: 6)
    public static let evening = Block(startHour: 18, spanHours: 6)
    public static let night = Block(startHour: 0, spanHours: 6)

    /// Midnight of the day that holds a moment, on the calendar of `timeZone`.
    public static func dayStartMS(containing timeMS: Double, in timeZone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: Date(timeIntervalSince1970: timeMS / 1000)).timeIntervalSince1970 * 1000
    }

    /// The moment `hour` o'clock on the day that starts at `dayStartMS`, on the calendar of `timeZone` (so a clock-change day is the right length).
    public static func moment(dayStartMS: Double, hour: Int, in timeZone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = Date(timeIntervalSince1970: dayStartMS / 1000)
        // Setting the hour reads the wall clock; adding hours would count real ones and be an hour off after a clock change.
        let moment = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day.addingTimeInterval(Double(hour) * 3600)
        return moment.timeIntervalSince1970 * 1000
    }

    /// Where a jump to a day lands: the day's start, or the block's start hour, never in the future.
    public static func target(dayStartMS: Double, block: Block?, in timeZone: TimeZone, nowMS: Double) -> Double {
        let hour = block?.startHour ?? 0
        return min(moment(dayStartMS: dayStartMS, hour: hour, in: timeZone), nowMS)
    }
}
