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
    /// One active alarm in full, with the controller it is on when that is known.
    case alarm(SiteAlarm, controller: ControllerSummary?)
    case virtualController(VirtualControllerSummary)
    case incident(IncidentSummary)
    /// One specific site of an organization, which never changes to another site.
    case site(id: String, organizationId: String)
    /// One cell of a site: the site page narrowed to the cell's machines and cameras.
    case cell(id: String, siteId: String, organizationId: String?)
    case release(id: String)
    case releaseUsers(id: String, kind: ReleaseUsageKind)
    case releaseImage(id: String)
    case virtualControllerSnapshots(VirtualControllerSummary)
    case controllerBackups(ControllerSummary)
    case allControllers
    case allVirtualControllers
    case alarmSubscriptions(ControllerSummary)
    case controllerSettings(ControllerSummary)
    case virtualAlarmSubscriptions(VirtualControllerSummary)
    /// A camera, live or at a moment of its recording.
    case camera(CameraTarget)
    /// The camera wall of every site the person can see.
    case surveillance
}

/// ReleaseUsageKind is what a release's "See all" lists.
enum ReleaseUsageKind: Hashable {
    case controllers
    case virtualControllers
    case tickets
    case images
}

private struct PortalDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: PortalRoute.self) { route in
            PortalRouteView(route: route)
        }
    }
}

/// PortalRouteView is the screen a route stands for. A list pushes it through `portalDestinations()`; a tapped link shows it
/// at the root of a sheet.
struct PortalRouteView: View {
    @Environment(SessionModel.self) private var session
    let route: PortalRoute

    var body: some View {
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
        case .alarm(let alarm, let controller):
            AlarmDetailView(alarm: alarm, controller: controller)
        case .virtualController(let virtual):
            VirtualControllerDetailView(virtual: virtual)
        case .incident(let incident):
            IncidentDetailView(incident: incident)
        case .site(let id, let organizationId):
            SiteView(organizationId: organizationId, siteId: id, embedsNavigation: false)
        case .cell(let id, let siteId, let organizationId):
            CellView(cellId: id, siteId: siteId, organizationId: organizationId)
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
        case .allVirtualControllers:
            AllVirtualControllersView()
        case .alarmSubscriptions(let controller):
            AlarmSubscriptionsView(controller: controller)
        case .controllerSettings(let controller):
            ControllerSettingsView(controller: controller)
        case .virtualAlarmSubscriptions(let virtual):
            AlarmSubscriptionsView(virtual: virtual)
        case .camera(let target):
            CameraDetailView(target: target)
        case .surveillance:
            SurveillanceView()
        }
    }
}

extension View {
    /// Registers where every `PortalRoute` goes. Apply it once, to the root of a `NavigationStack`.
    func portalDestinations() -> some View { modifier(PortalDestinations()) }
}
