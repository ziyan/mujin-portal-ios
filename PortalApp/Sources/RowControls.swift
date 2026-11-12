import SwiftUI

/// Controls that sit beside other controls in one List row.
///
/// A List row is one hit target. When a row holds several `NavigationLink`s, or several `Button`s with the automatic
/// style, a tap anywhere in the row activates every one of them: a grid of tiles in a row pushes all of its screens at
/// once, and the one on top is the last tile's. A `.buttonStyle(.plain)` does not prevent it for a `NavigationLink`.
/// Button styles only change how the row decides, so nothing here depends on one.
///
/// A tap gesture is not a control the List knows about. Each view that carries one is hit tested on its own, so a tap
/// reaches only the view under the finger. `rowTapTarget` is that gesture plus the button trait VoiceOver needs. Any
/// tile, chip or badge that shares a List row with another control goes through it, and a screen it must open goes
/// through `RouteOpener`, because a `NavigationLink` cannot be used in such a row.
extension View {
    func rowTapTarget(perform action: @escaping () -> Void) -> some View {
        contentShape(.rect)
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}

/// RouteOpener opens a route on top of the screen that hosts it. A tile in a List row calls it instead of being a
/// `NavigationLink`. The host is the screen's List, which applies `routePushing()`.
struct RouteOpener: @unchecked Sendable {
    let push: @MainActor (PortalRoute) -> Void

    @MainActor
    func callAsFunction(_ route: PortalRoute) { push(route) }

    /// What a tile finds when no screen above it applied `routePushing()`: it fails loudly in a debug build, which is
    /// what the UI tests run, instead of a tap that does nothing.
    static let unavailable = RouteOpener { route in
        assertionFailure("Nothing hosts \(route): apply routePushing() to the List that holds the tile.")
    }
}

extension EnvironmentValues {
    @Entry var openRoute = RouteOpener.unavailable
    /// Appends a route to the path of the stack the view is in. Each stack that registers `portalDestinations` sets it.
    @Entry var stackRouteOpener: RouteOpener? = nil
}

/// A screen a tile opens goes on the stack's path, like a link's. Shown with `navigationDestination(item:)` instead, it
/// stays above everything the path holds: a link tapped on it pushes its screen underneath, so the tap seems to do
/// nothing and Back then shows that screen. The item is only for a stack that keeps no path of its own.
private struct RoutePushingHost: ViewModifier {
    @Environment(\.stackRouteOpener) private var stackRouteOpener
    @State private var requestedRoute: PortalRoute?

    func body(content: Content) -> some View {
        if let stackRouteOpener {
            content.environment(\.openRoute, stackRouteOpener)
        } else {
            let requestedRoute = $requestedRoute
            content
                .environment(\.openRoute, RouteOpener { route in requestedRoute.wrappedValue = route })
                .navigationDestination(item: requestedRoute) { route in PortalRouteView(route: route) }
        }
    }
}

extension View {
    /// Lets the tiles inside this view push a route with `\.openRoute`. Apply it to the List that holds them, which
    /// is on screen for as long as a screen it pushed is, unlike its rows.
    func routePushing() -> some View {
        modifier(RoutePushingHost())
    }

    /// Lets tiles anywhere in this stack push onto its path. Apply it to the `NavigationStack` itself, so the screens
    /// it pushes, of every kind, see it too.
    func pushesRoutes(_ push: @escaping @MainActor (PortalRoute) -> Void) -> some View {
        environment(\.stackRouteOpener, RouteOpener(push: push))
    }
}
