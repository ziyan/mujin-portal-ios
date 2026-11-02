import Foundation
import Testing

@testable import PortalKit

@Suite struct ImageZoomMathTests {
    private let screen = CGSize(width: 400, height: 800)

    @Test func theFittingScaleShowsTheWholePictureOnATallAndAWideImage() {
        #expect(ImageZoomMath.fitScale(imageSize: CGSize(width: 800, height: 1600), boundsSize: screen) == 0.5)
        #expect(ImageZoomMath.fitScale(imageSize: CGSize(width: 1600, height: 800), boundsSize: screen) == 0.25)
        #expect(ImageZoomMath.fitScale(imageSize: CGSize(width: 200, height: 100), boundsSize: screen) == 2)
        #expect(ImageZoomMath.fitScale(imageSize: .zero, boundsSize: screen) == 1)
    }

    @Test func aPictureSmallerThanTheScreenIsCenteredAndALargerOneIsNot() {
        let wide = ImageZoomMath.centeringInset(contentSize: CGSize(width: 400, height: 200), boundsSize: screen)
        #expect(wide.horizontal == 0 && wide.vertical == 300)
        let zoomed = ImageZoomMath.centeringInset(contentSize: CGSize(width: 900, height: 1800), boundsSize: screen)
        #expect(zoomed.horizontal == 0 && zoomed.vertical == 0)
    }

    @Test func aDoubleTapZoomsInThenBackToFit() {
        let fit = 0.5
        #expect(ImageZoomMath.doubleTapScale(current: fit, fit: fit) == 1.5)
        #expect(ImageZoomMath.doubleTapScale(current: 1.5, fit: fit) == fit)
    }

    @Test func theZoomedPartFollowsTheTapAndStaysInsideThePicture() {
        let image = CGSize(width: 800, height: 1600)
        let middle = ImageZoomMath.zoomRect(around: CGPoint(x: 400, y: 800), scale: 1, boundsSize: screen, imageSize: image)
        #expect(middle == CGRect(x: 200, y: 400, width: 400, height: 800))
        let corner = ImageZoomMath.zoomRect(around: CGPoint(x: 10, y: 10), scale: 1, boundsSize: screen, imageSize: image)
        #expect(corner.origin == .zero)
        let far = ImageZoomMath.zoomRect(around: CGPoint(x: 790, y: 1590), scale: 1, boundsSize: screen, imageSize: image)
        #expect(far.maxX == 800 && far.maxY == 1600)
    }

    @Test func aSwipeDownClosesOnlyAtTheFittingScale() {
        #expect(ImageZoomMath.isAtFit(current: 0.5, fit: 0.5))
        #expect(!ImageZoomMath.isAtFit(current: 0.8, fit: 0.5))
    }
}
