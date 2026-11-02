import Foundation

/// ImageZoomMath is the arithmetic of the full-screen picture viewer, kept apart from UIKit so it can be tested: the scale that
/// fits a picture to the screen, how far to inset it so it sits in the middle when it is smaller than the screen, and where a
/// double tap zooms to.
public enum ImageZoomMath {
    /// How many times larger than the fitting scale a picture may be zoomed.
    public static let maximumZoomFactor: Double = 5
    /// How far a double tap zooms in from the fitting scale.
    public static let doubleTapZoomFactor: Double = 3

    /// The scale at which the whole picture is visible: it touches the screen on its longer side.
    public static func fitScale(imageSize: CGSize, boundsSize: CGSize) -> Double {
        guard imageSize.width > 0, imageSize.height > 0, boundsSize.width > 0, boundsSize.height > 0 else { return 1 }
        return min(Double(boundsSize.width / imageSize.width), Double(boundsSize.height / imageSize.height))
    }

    /// The padding that keeps content centered on an axis where it is smaller than the screen, and none where it is larger.
    public static func centeringInset(contentSize: CGSize, boundsSize: CGSize) -> (horizontal: Double, vertical: Double) {
        (max(0, Double(boundsSize.width - contentSize.width) / 2), max(0, Double(boundsSize.height - contentSize.height) / 2))
    }

    /// Where a double tap goes: back to the fitting scale when already zoomed in, else in to a few times the fitting scale, never past the maximum.
    public static func doubleTapScale(current: Double, fit: Double) -> Double {
        if current > fit * 1.05 { return fit }
        return min(fit * maximumZoomFactor, fit * doubleTapZoomFactor)
    }

    /// The part of the picture, in the picture's own coordinates, to show when zooming to `scale` around `point` (also in the picture's coordinates):
    /// the point stays at the middle of the screen where the picture's edges allow it.
    public static func zoomRect(around point: CGPoint, scale: Double, boundsSize: CGSize, imageSize: CGSize) -> CGRect {
        let width = Double(boundsSize.width) / scale
        let height = Double(boundsSize.height) / scale
        var x = Double(point.x) - width / 2
        var y = Double(point.y) - height / 2
        x = min(max(0, x), max(0, Double(imageSize.width) - width))
        y = min(max(0, y), max(0, Double(imageSize.height) - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Whether the picture is at its fitting scale, within a hair, so a swipe down closes the viewer instead of panning.
    public static func isAtFit(current: Double, fit: Double) -> Bool { current <= fit * 1.01 }

    /// How far past the resting position a swipe down must pull to close the viewer, in points.
    public static let dismissDistance: Double = 90
}
