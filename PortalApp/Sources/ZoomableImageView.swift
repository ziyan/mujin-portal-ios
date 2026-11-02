import PortalKit
import SwiftUI
import UIKit

/// ZoomableImage is a picture in a UIScrollView: pinch zoom around the pinch point, pan while zoomed with bounce at the edges,
/// the picture centered whenever it is smaller than the screen, a double tap that zooms in at the tapped point and back, a
/// rotation that keeps the middle of what is shown, and a swipe down that closes the viewer, only at the fitting scale.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(image: image, onDismiss: onDismiss) }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scrollView = ZoomingScrollView()
        let coordinator = context.coordinator
        scrollView.delegate = coordinator
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.backgroundColor = .clear
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.addSubview(imageView)
        scrollView.contentSize = image.size
        coordinator.imageView = imageView
        coordinator.scrollView = scrollView
        scrollView.onLayout = { [weak coordinator] in coordinator?.layoutChanged() }
        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        context.coordinator.onDismiss = onDismiss
    }

    /// A scroll view that tells its owner when its size changes, which is when the fitting scale changes.
    final class ZoomingScrollView: UIScrollView {
        var onLayout: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: ZoomingScrollView?
        var onDismiss: () -> Void
        private let imageSize: CGSize
        private var lastBounds: CGSize = .zero
        private var fit: Double = 1

        init(image: UIImage, onDismiss: @escaping () -> Void) {
            imageSize = image.size
            self.onDismiss = onDismiss
        }

        /// Sets the scale limits for the current size. The first time the picture is shown whole; after a rotation the middle of what
        /// was shown stays in the middle, at the same zoom relative to the fitting scale.
        func layoutChanged() {
            guard let scrollView, scrollView.bounds.size != lastBounds, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            let hadLayout = lastBounds != .zero
            let oldFit = fit
            let relativeZoom = hadLayout ? Double(scrollView.zoomScale) / oldFit : 1
            let oldCenter = hadLayout ? visibleCenterInImage(scrollView) : CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
            lastBounds = scrollView.bounds.size
            fit = ImageZoomMath.fitScale(imageSize: imageSize, boundsSize: scrollView.bounds.size)
            scrollView.minimumZoomScale = fit
            scrollView.maximumZoomScale = fit * ImageZoomMath.maximumZoomFactor
            let scale = min(max(fit * relativeZoom, fit), fit * ImageZoomMath.maximumZoomFactor)
            scrollView.zoomScale = scale
            centerInset(scrollView)
            // Put the remembered center back in the middle of the screen, within the picture.
            let target = CGPoint(x: oldCenter.x * scale - scrollView.bounds.width / 2, y: oldCenter.y * scale - scrollView.bounds.height / 2)
            scrollView.contentOffset = clampedOffset(target, in: scrollView)
        }

        private func visibleCenterInImage(_ scrollView: UIScrollView) -> CGPoint {
            let scale = max(scrollView.zoomScale, 0.0001)
            return CGPoint(
                x: (scrollView.contentOffset.x + scrollView.bounds.width / 2) / scale,
                y: (scrollView.contentOffset.y + scrollView.bounds.height / 2) / scale)
        }

        private func clampedOffset(_ offset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
            let inset = scrollView.contentInset
            let minX = -inset.left
            let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
            let minY = -inset.top
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, minY), maxY))
        }

        /// Pads the content so that it sits in the middle of the screen when it is smaller than it.
        private func centerInset(_ scrollView: UIScrollView) {
            let padding = ImageZoomMath.centeringInset(contentSize: scrollView.contentSize, boundsSize: scrollView.bounds.size)
            scrollView.contentInset = UIEdgeInsets(top: padding.vertical, left: padding.horizontal, bottom: padding.vertical, right: padding.horizontal)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerInset(scrollView) }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            // A swipe down closes the viewer only when the whole picture is showing; zoomed in, it pans.
            guard ImageZoomMath.isAtFit(current: Double(scrollView.zoomScale), fit: fit) else { return }
            let pulled = -(scrollView.contentOffset.y + scrollView.contentInset.top)
            if Double(pulled) > ImageZoomMath.dismissDistance { onDismiss() }
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }
            let target = ImageZoomMath.doubleTapScale(current: Double(scrollView.zoomScale), fit: fit)
            if target <= fit * 1.01 {
                scrollView.setZoomScale(fit, animated: true)
                return
            }
            let point = recognizer.location(in: imageView)
            let rect = ImageZoomMath.zoomRect(around: point, scale: target, boundsSize: scrollView.bounds.size, imageSize: imageSize)
            scrollView.zoom(to: rect, animated: true)
        }
    }
}
