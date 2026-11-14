import Foundation

/// ComposerShape is the arithmetic behind when the message composer is a one-line pill and when it is a card, kept apart from UIKit so
/// it can be tested. The screens measure the words and the width; this decides what the measurement means.
public enum ComposerShape {
    /// How much taller than one line the words may be before they count as a second line.
    public static let secondLineFactor: Double = 1.5
    /// A change in the pill's width smaller than this is rounding, not a new width.
    public static let widthTolerance: Double = 1

    /// Whether words measured at `textHeight` need a second line, given the height of one line.
    public static func needsSecondLine(textHeight: Double, lineHeight: Double) -> Bool {
        textHeight > lineHeight * secondLineFactor
    }

    /// Whether a newly measured field width replaces the one the pill remembers. Words exactly as wide as the pill must not flip the shape
    /// back and forth on a sub-point change in the measurement.
    public static func acceptsPillWidth(_ measured: Double, replacing remembered: Double) -> Bool {
        abs(measured - remembered) >= widthTolerance
    }
}
