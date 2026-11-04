import ObjectiveC
import UIKit

/// SearchFieldFill puts a fill behind the search fields in navigation bars while a page slides in or out.
///
/// On iOS 26 the field's own fill is drawn only after the slide has finished, so during it the field showed
/// just a magnifier and the prompt. From the moment a page starts to appear, every search field in the bar,
/// including one the bar creates mid-slide, gets a capsule view of the color the field settles to as its
/// first subview. The capsule is taken away a moment after the page has appeared. The field itself is never
/// touched, so at rest it is exactly what the system draws, with its rim.
@MainActor
enum SearchFieldFill {
    /// The system's fill is drawn a little after the slide ends; the capsule stays until then.
    private static let settleDelay = Duration.milliseconds(500)

    /// A rounded fill as wide and tall as the field it sits in.
    private final class CapsuleView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = bounds.height / 2
        }
    }

    private static let capsules = NSMapTable<UISearchTextField, CapsuleView>.weakToStrongObjects()
    private static var isTransitionActive = false
    /// A page with a large title has a flat gray field; one with an inline title has the lighter glass one.
    private static var fillColorName = "SearchFieldFill"
    /// Counts the transitions, so a late take-away from an earlier one never removes the next one's capsules.
    private static var transitionCount = 0

    /// Must run after launch, not in `PortalApp.init`: looking up a named color that early made the whole app
    /// fall back to the system blue instead of the accent color.
    static func install() {
        exchange(UIViewController.self, #selector(UIViewController.viewWillAppear(_:)), #selector(UIViewController.portalSearchFillViewWillAppear(_:)))
        exchange(UIViewController.self, #selector(UIViewController.viewDidAppear(_:)), #selector(UIViewController.portalSearchFillViewDidAppear(_:)))
        exchange(UINavigationBar.self, #selector(UIView.layoutSubviews), #selector(UINavigationBar.portalSearchFillLayoutSubviews))
    }

    fileprivate static func transitionWillStart(in navigationController: UINavigationController?) {
        guard let navigationController else { return }
        transitionCount += 1
        isTransitionActive = true
        let isInline = navigationController.topViewController?.navigationItem.largeTitleDisplayMode == .never
        fillColorName = isInline ? "SearchFieldFill" : "SearchFieldFillLarge"
        fill(fieldsIn: navigationController.navigationBar)
    }

    fileprivate static func fill(fieldsIn navigationBar: UIView) {
        guard isTransitionActive else { return }
        let fillColor = UIColor(named: fillColorName)
        for field in searchFields(in: navigationBar) {
            let capsule = capsules.object(forKey: field) ?? CapsuleView()
            capsule.backgroundColor = fillColor
            guard capsule.superview == nil else { continue }
            capsule.isUserInteractionEnabled = false
            capsule.frame = field.bounds
            capsule.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            field.insertSubview(capsule, at: 0)
            capsules.setObject(capsule, forKey: field)
        }
    }

    fileprivate static func transitionDidEnd(in navigationController: UINavigationController?) {
        guard navigationController != nil else { return }
        let expectedCount = transitionCount
        Task { @MainActor in
            try? await Task.sleep(for: settleDelay)
            guard expectedCount == transitionCount else { return }
            isTransitionActive = false
            for capsule in capsules.objectEnumerator()?.allObjects.compactMap({ $0 as? CapsuleView }) ?? [] {
                capsule.removeFromSuperview()
            }
            capsules.removeAllObjects()
        }
    }

    private static func searchFields(in view: UIView) -> [UISearchTextField] {
        var fields: [UISearchTextField] = []
        if let field = view as? UISearchTextField { fields.append(field) }
        for subview in view.subviews { fields += searchFields(in: subview) }
        return fields
    }

    private static func exchange(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(type, original),
            let replacementMethod = class_getInstanceMethod(type, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

// After the exchange these names run the system's methods, and the system's names run these.
extension UIViewController {
    @objc fileprivate func portalSearchFillViewWillAppear(_ animated: Bool) {
        portalSearchFillViewWillAppear(animated)
        SearchFieldFill.transitionWillStart(in: navigationController)
    }

    @objc fileprivate func portalSearchFillViewDidAppear(_ animated: Bool) {
        portalSearchFillViewDidAppear(animated)
        SearchFieldFill.transitionDidEnd(in: navigationController)
    }
}

extension UINavigationBar {
    @objc fileprivate func portalSearchFillLayoutSubviews() {
        portalSearchFillLayoutSubviews()
        SearchFieldFill.fill(fieldsIn: self)
    }
}
