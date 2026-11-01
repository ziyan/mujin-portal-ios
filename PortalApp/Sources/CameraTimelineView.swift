import PortalKit
import SwiftUI

/// CameraText formats the camera's times. They are read on the NVR's clock
/// (the place the camera is in), never the phone's, and always say which.
enum CameraText {
    static func style(_ clock: CameraClock) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: clock.timeZone)
    }

    static func date(_ timeMS: Double) -> Date { Date(timeIntervalSince1970: timeMS / 1000) }

    /// "Tue, Mar 3, 10:42:07 AM".
    static func stamp(_ timeMS: Double, clock: CameraClock) -> String {
        date(timeMS).formatted(style(clock).weekday(.abbreviated).month(.abbreviated).day().hour().minute().second())
    }

    static func time(_ timeMS: Double, clock: CameraClock, showsSeconds: Bool = false) -> String {
        let base = style(clock).hour().minute()
        return date(timeMS).formatted(showsSeconds ? base.second() : base)
    }

    static func day(_ timeMS: Double, clock: CameraClock) -> String {
        date(timeMS).formatted(style(clock).month(.abbreviated).day())
    }

    /// "Camera time, CST", or a plain statement that the phone's time is shown when the NVR's zone is not known.
    static func zoneCaption(_ timeMS: Double, clock: CameraClock) -> String {
        let label = clock.zoneLabel(atMS: timeMS)
        return clock.isControllerZone
            ? String(localized: "Camera time, \(label)") : String(localized: "Your phone's time, \(label). The camera's time zone is not known.")
    }
}

/// CameraTimelineView is the strip to scrub through the recording: a ruler of
/// the camera's clock with the playhead fixed in the middle. Dragging moves the
/// recording under it and lets go at a new moment; pinching changes how much
/// time the strip shows. The part after now is shaded.
struct CameraTimelineView: View {
    let centerMS: Double
    @Binding var spanMS: Double
    let nowMS: Double
    let markerMS: Double?
    let clock: CameraClock
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var dragOriginMS: Double?
    @State private var pinchOriginSpanMS: Double?
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 64

    var body: some View {
        GeometryReader { geometry in
            let window = CameraTimeWindow(startMS: centerMS - spanMS / 2, endMS: centerMS + spanMS / 2)
            ZStack {
                Canvas { context, size in
                    CameraTimelineDrawing.draw(into: &context, size: size, window: window, nowMS: nowMS, markerMS: markerMS, clock: clock)
                }
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let origin = dragOriginMS ?? centerMS
                        dragOriginMS = origin
                        onScrub(CameraTimelineDrawing.time(afterDragging: value.translation.width, from: origin, spanMS: spanMS, width: geometry.size.width, nowMS: nowMS))
                    }
                    .onEnded { value in
                        let origin = dragOriginMS ?? centerMS
                        dragOriginMS = nil
                        onCommit(CameraTimelineDrawing.time(afterDragging: value.translation.width, from: origin, spanMS: spanMS, width: geometry.size.width, nowMS: nowMS))
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let origin = pinchOriginSpanMS ?? spanMS
                        pinchOriginSpanMS = origin
                        spanMS = CameraTimeline.resized(window, spanMS: origin / max(value.magnification, 0.1), anchorMS: centerMS, nowMS: nowMS).spanMS
                    }
                    .onEnded { _ in pinchOriginSpanMS = nil }
            )
        }
        .frame(height: height)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(Text("Timeline"))
        .accessibilityValue(Text(CameraText.stamp(centerMS, clock: clock)))
        .accessibilityAdjustableAction { direction in
            let step = max(spanMS / 10, 1_000)
            switch direction {
            case .increment: onCommit(min(centerMS + step, nowMS))
            case .decrement: onCommit(centerMS - step)
            @unknown default: break
            }
        }
    }
}

/// CameraTimelineDrawing is the strip's arithmetic and picture, apart from the view so the canvas can call it from anywhere.
enum CameraTimelineDrawing {
    /// Dragging to the right pulls earlier footage under the playhead; the playhead never goes past now.
    static func time(afterDragging translation: CGFloat, from originMS: Double, spanMS: Double, width: CGFloat, nowMS: Double) -> Double {
        guard width > 0 else { return originMS }
        return min(originMS - Double(translation) / Double(width) * spanMS, nowMS)
    }

    static func draw(into context: inout GraphicsContext, size: CGSize, window: CameraTimeWindow, nowMS: Double, markerMS: Double?, clock: CameraClock) {
        // The future is shaded.
        let nowX = CGFloat(CameraTimeline.fraction(forTimeMS: nowMS, in: window)) * size.width
        if nowX < size.width {
            context.fill(Path(CGRect(x: max(nowX, 0), y: 0, width: size.width - max(nowX, 0), height: size.height)), with: .color(Color.secondary.opacity(0.18)))
        }
        let step = CameraTimeline.tickStepMS(forSpanMS: window.spanMS)
        let showsSeconds = step < CameraTimeline.minuteMS
        for tick in CameraTimeline.ticks(in: window) {
            let x = CGFloat(CameraTimeline.fraction(forTimeMS: tick, in: window)) * size.width
            let isMidnight = clock.secondsSinceMidnight(atMS: tick) == 0
            let tickHeight: CGFloat = isMidnight ? size.height * 0.5 : size.height * 0.28
            var line = Path()
            line.move(to: CGPoint(x: x, y: size.height))
            line.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
            context.stroke(line, with: .color(Color.secondary.opacity(0.7)), lineWidth: 1)
            let label = isMidnight ? CameraText.day(tick, clock: clock) : CameraText.time(tick, clock: clock, showsSeconds: showsSeconds)
            context.draw(Text(label).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x, y: 6), anchor: .top)
        }
        if let markerMS {
            let x = CGFloat(CameraTimeline.fraction(forTimeMS: markerMS, in: window)) * size.width
            if x >= -4, x <= size.width + 4 {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height * 0.45))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Color.statusWarning), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: size.height * 0.45 - 5, width: 10, height: 10)), with: .color(Color.statusWarning))
            }
        }
    }
}
