import Foundation
import Testing

@testable import PortalKit

@Suite struct ComposerShapeTests {
    private let lineHeight = 20.0

    @Test func wordsOnOneLineStayInThePill() {
        #expect(!ComposerShape.needsSecondLine(textHeight: lineHeight, lineHeight: lineHeight))
    }

    @Test func wordsOnASecondLineMakeTheCard() {
        #expect(ComposerShape.needsSecondLine(textHeight: lineHeight * 2, lineHeight: lineHeight))
    }

    /// A draft exactly one pill line wide measures one line high at the pill's width, and the card's wider field never replaces the
    /// remembered pill width, so the shape does not change from one evaluation to the next.
    @Test func aDraftExactlyOneLineWideDoesNotFlickerBetweenPillAndCard() {
        let pillWidth = 240.0
        var rememberedWidth = pillWidth
        var shapes: [Bool] = []
        for _ in 0..<6 {
            // The words are exactly as wide as the pill, so at that width they measure one line.
            shapes.append(ComposerShape.needsSecondLine(textHeight: lineHeight, lineHeight: lineHeight))
            // The measurement jitters by a fraction of a point on every layout pass.
            let measured = pillWidth + (shapes.count.isMultiple(of: 2) ? 0.3 : -0.3)
            if ComposerShape.acceptsPillWidth(measured, replacing: rememberedWidth) { rememberedWidth = measured }
        }
        #expect(Set(shapes) == [false])
        #expect(rememberedWidth == pillWidth)
    }

    @Test func aRealChangeOfWidthIsRemembered() {
        #expect(ComposerShape.acceptsPillWidth(200, replacing: 240))
        #expect(!ComposerShape.acceptsPillWidth(240.4, replacing: 240))
    }
}
