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
    /// One specific site of an organization, which never changes to another site.
    case site(id: String, organizationId: String)
    case release(id: String)
    case releaseUsers(id: String, kind: ReleaseUsageKind)
    case releaseImage(id: String)
    case virtualControllerSnapshots(VirtualControllerSummary)
    case controllerBackups(ControllerSummary)
    case allControllers
    case alarmSubscriptions(ControllerSummary)
    /// A camera, live or at a moment of its recording.
    case camera(CameraTarget)
}

/// ReleaseUsageKind is what a release's "See all" lists.
enum ReleaseUsageKind: Hashable {
    case controllers
    case virtualControllers
    case tickets
    case images
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
                    switch kind {
                    case .telemetry: SiteTelemetryView(model: model)
                    case .cameras: CameraGridView(model: model)
                    default: SiteListScreen(kind: kind, model: model)
                    }
                }
            case .controller(let controller):
                ControllerDetailView(controller: controller)
            case .virtualController(let virtual):
                VirtualControllerDetailView(virtual: virtual)
            case .incident(let incident):
                IncidentDetailView(incident: incident)
            case .site(let id, let organizationId):
                SiteView(organizationId: organizationId, siteId: id, embedsNavigation: false)
            case .release(let id):
                ReleaseDetailView(releaseId: id)
            case .releaseUsers(let id, let kind):
                ReleaseUsersView(releaseId: id, kind: kind)
            case .releaseImage(let id):
                ReleaseImageView(imageId: id)
            case .virtualControllerSnapshots(let virtual):
                VirtualControllerSnapshotsView(virtual: virtual)
            case .controllerBackups(let controller):
                ControllerBackupsView(controller: controller)
            case .allControllers:
                AllControllersView()
            case .alarmSubscriptions(let controller):
                AlarmSubscriptionsView(controller: controller)
            case .camera(let target):
                CameraDetailView(target: target)
            }
        }
    }
}

extension View {
    /// Registers where every `PortalRoute` goes. Apply it once, to the root of a `NavigationStack`.
    func portalDestinations() -> some View { modifier(PortalDestinations()) }
}
