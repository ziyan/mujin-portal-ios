import PortalKit
import SwiftUI

/// PortalRoute is every place a list can push on a tab's stack. It is one
/// type, registered once at the root of each stack by `portalDestinations()`,
/// so a push is never resolved against a destination registered by a screen
/// that happens to be embedded in the same stack, and no bare `String` is a
/// navigation value.
enum PortalRoute: Hashable {
    case ticket(id: String)
    case siteList(SiteListKind, organizationKey: String)
    case controller(ControllerSummary)
    case virtualController(VirtualControllerSummary)
    case incident(IncidentSummary)
    case organization(OrganizationSummary)
}

private struct PortalDestinations: ViewModifier {
    @Environment(SessionModel.self) private var session

    func body(content: Content) -> some View {
        content.navigationDestination(for: PortalRoute.self) { route in
            switch route {
            case .ticket(let id):
                TicketDetailView(ticketId: id)
            case .siteList(let kind, let organizationKey):
                if let model = session.existingSiteModel(key: organizationKey) {
                    if kind == .telemetry { SiteTelemetryView(model: model) } else { SiteListScreen(kind: kind, model: model) }
                }
            case .controller(let controller):
                ControllerDetailView(controller: controller)
            case .virtualController(let virtual):
                VirtualControllerDetailView(virtual: virtual)
            case .incident(let incident):
                IncidentDetailView(incident: incident)
            case .organization(let organization):
                OrganizationDetailView(organization: organization)
            }
        }
    }
}

extension View {
    /// Registers where every `PortalRoute` goes. Apply it once, to the root of a `NavigationStack`.
    func portalDestinations() -> some View { modifier(PortalDestinations()) }
}
