import SwiftUI
import UIKit

/// TopPresenter shows a SwiftUI screen over whatever is on top of the app.
///
/// SwiftUI's `.sheet` and `.fullScreenCover` present from the view they are attached to, and UIKit refuses to present from a
/// view controller that is already presenting. So a cover attached near the root of the app silently shows nothing while any
/// sheet is up, and the state that asked for it stays set. A presenter that starts from the top-most view controller works
/// from any depth, and closing what it shows returns to the screen below.
///
/// A screen that fills the display uses `.overFullScreen`, never `.fullScreen`. `.fullScreen` takes the screen below out of the
/// window, and SwiftUI stops updating a view that is out of the window: the state that closes this screen is watched by the root
/// of the app, so with nothing but the root below, the close button would change the state and nothing would ever close the screen.
/// It also makes the screen below disappear and appear again, which runs its tasks a second time and loses its place.
@MainActor
final class TopPresenter {
    private weak var shown: PresentedHostingController?
    private var pending: Task<Void, Never>?

    /// Shows `rootView` over the top screen. The same `id` again only updates what is shown; a different one is shown over it.
    /// `onUserDismiss` runs when the person (or the system, with the screen under it) closes the screen.
    func present(id: AnyHashable, style: UIModalPresentationStyle, rootView: AnyView, onUserDismiss: @escaping () -> Void) {
        pending?.cancel()
        if let shown, shown.presentationID == id, shown.presentingViewController != nil {
            shown.rootView = rootView
            shown.onUserDismiss = onUserDismiss
            return
        }
        let controller = PresentedHostingController(rootView: rootView)
        controller.presentationID = id
        controller.onUserDismiss = onUserDismiss
        controller.modalPresentationStyle = style
        controller.modalPresentationCapturesStatusBarAppearance = true
        controller.view.accessibilityViewIsModal = true
        controller.view.backgroundColor = .systemBackground
        // The screen under it is closed by the person, so asking again must not close it with a state that is no longer its own.
        shown?.onUserDismiss = nil
        shown = controller
        // The task keeps the controller alive until UIKit does: `shown` is weak, so nothing else holds it before it is presented.
        pending = Task {
            guard let top = await Self.settledTopViewController(), !Task.isCancelled else { return }
            // The screen below stays in the window, and its text field would keep the keyboard over this one. A sheet leaves it alone.
            if style == .overFullScreen { top.view.window?.endEditing(true) }
            top.present(controller, animated: true)
        }
    }

    /// Closes what was shown, when the state that asked for it is cleared by the app.
    func dismiss() {
        pending?.cancel()
        pending = nil
        guard let controller = shown else { return }
        shown = nil
        controller.onUserDismiss = nil
        if controller.presentingViewController != nil { controller.dismiss(animated: true) }
    }

    /// The view controller that anything shown over the screen is presented from.
    static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// The top view controller once it is not in the middle of appearing or disappearing, since UIKit refuses to present from one
    /// that is: a sheet that was just closed, or one that is still opening.
    private static func settledTopViewController() async -> UIViewController? {
        for _ in 0..<100 {
            if let top = topViewController(), !top.isBeingPresented, !top.isBeingDismissed, top.transitionCoordinator == nil { return top }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }
}

/// PresentedHostingController is a SwiftUI screen shown by `TopPresenter`. It says when the person closed it.
final class PresentedHostingController: UIHostingController<AnyView> {
    var presentationID: AnyHashable = 0
    var onUserDismiss: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Not when another screen covers this one: then it is still presented.
        if isBeingDismissed || presentingViewController == nil { onUserDismiss?() }
    }
}

/// CoveredChange tells a screen when one that fills the display opens over it or closes, in place of `onDisappear` and `onAppear`.
private struct CoveredChange: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: appModel.isCoveredByScreen) { _, isCovered in action(isCovered) }
    }
}

extension View {
    /// Runs `action` with true when a screen that fills the display opens over the app, and with false when it closes. What must not go
    /// on unseen, such as a microphone, a live picture or the feed that says the person is reading, stops here.
    func onCoveredChange(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(CoveredChange(action: action))
    }
}

/// HostedEnvironment gives a screen shown by `TopPresenter` the environment it would have inherited from a sheet, since a view
/// hosted from UIKit does not carry the screen's environment.
struct HostedEnvironment: ViewModifier {
    let appModel: AppModel
    let session: SessionModel?

    func body(content: Content) -> some View {
        content
            .environment(appModel)
            .environment(\.openURL, OpenURLAction { url in appModel.handleLink(url) })
            .modifier(OptionalSession(session: session))
    }

    private struct OptionalSession: ViewModifier {
        let session: SessionModel?

        @ViewBuilder
        func body(content: Content) -> some View {
            if let session { content.environment(session) } else { content }
        }
    }
}

private struct TopPresentation<Item: Identifiable, Screen: View>: ViewModifier {
    @Binding var item: Item?
    let style: UIModalPresentationStyle
    let screen: (Item) -> Screen
    @State private var presenter = TopPresenter()

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id, initial: true) { _, _ in
                if let item {
                    presenter.present(id: AnyHashable(item.id), style: style, rootView: AnyView(screen(item))) { self.item = nil }
                } else {
                    presenter.dismiss()
                }
            }
            // UIKit holds what was shown, so nothing closes it with the screen that asked for it, as at signing out.
            .onDisappear { presenter.dismiss() }
    }
}

extension View {
    /// Shows a screen for the item over whatever is on top of the app, even a sheet, and clears the item when it is closed.
    /// The screen carries its own environment, see `HostedEnvironment`.
    func topPresentation<Item: Identifiable, Screen: View>(
        item: Binding<Item?>, style: UIModalPresentationStyle, @ViewBuilder screen: @escaping (Item) -> Screen
    ) -> some View {
        modifier(TopPresentation(item: item, style: style, screen: screen))
    }

    /// The same for a screen that has no item, only a switch.
    func topPresentation<Screen: View>(
        isPresented: Binding<Bool>, style: UIModalPresentationStyle, @ViewBuilder screen: @escaping () -> Screen
    ) -> some View {
        topPresentation(
            item: Binding<TopPresentationFlag?>(
                get: { isPresented.wrappedValue ? TopPresentationFlag() : nil },
                set: { isPresented.wrappedValue = $0 != nil }),
            style: style
        ) { _ in screen() }
    }
}

/// TopPresentationFlag is the item of a screen that has only a switch.
struct TopPresentationFlag: Identifiable {
    let id = 0
}
