import PortalKit
import SwiftUI

/// SiteSectionViews draws the sections the site page and the cell page share. Both read a `SiteModel`; a cell's model holds only the
/// machines, cameras and reports of that cell, so the same section shows the cell's rows.
@MainActor
enum SiteSectionViews {
    // MARK: telemetry

    /// The last 24 hours, as the web page's telemetry cards show them. The site page adds a "View all" row to the per-cell breakdown.
    @ViewBuilder
    static func telemetry(_ model: SiteModel, showsViewAll: Bool) -> some View {
        if let telemetry = model.telemetry, telemetry.machinesTotal > 0 {
            Section {
                tileGrid { telemetryTiles(telemetry) }
            } header: {
                Text("Last 24 hours")
            }
            // "View all" is a row of its own, below the tiles.
            if showsViewAll, !model.cells.isEmpty {
                Section {
                    NavigationLink(value: PortalRoute.siteList(.telemetry, organizationKey: model.sessionKey)) { Text("View all").foregroundStyle(.tint) }
                }
            }
        } else if model.telemetry == nil, model.isLoadingStats {
            // The real layout, redacted, until the numbers arrive.
            Section {
                tileGrid { telemetryTiles(SiteTelemetry.placeholder) }
                    .placeholderWhileLoading(true)
            } header: {
                Text("Last 24 hours")
            }
        }
    }

    @ViewBuilder
    static func telemetryTiles(_ telemetry: SiteTelemetry) -> some View {
        StatTile(label: "Picked parts", value: telemetry.pickedParts.formatted(), detail: "\(telemetry.pickOperations) pick operations", symbol: "shippingbox")
        StatTile(label: "Error rate", value: telemetry.errorRateText(), detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
        StatTile(label: "Robot throughput", value: telemetry.throughputText(), detail: "parts per hour", symbol: "speedometer")
        StatTile(label: "Machines", value: telemetry.machinesTotal.formatted(), detail: "\(telemetry.machinesReporting) reporting", symbol: "server.rack")
    }

    // MARK: what the views leave out

    /// Says which controller the site's totals and alarms come from, on a site, and which controllers this view leaves out, so a controller
    /// that was excluded by mistake is noticed. Each id opens its controller.
    @ViewBuilder
    static func viewNotes(_ model: SiteModel) -> some View {
        let sourceId = model.cellId == nil ? model.sourceControllerId : nil
        if sourceId != nil || !model.excludedControllerIds.isEmpty {
            Section {
                if let sourceId {
                    controllerNote("Site totals and alarms come from:", ids: [sourceId], model: model)
                }
                if !model.excludedControllerIds.isEmpty {
                    controllerNote("Excluded from this view:", ids: model.excludedControllerIds, model: model)
                }
            }
        }
    }

    private static func controllerNote(_ label: LocalizedStringKey, ids: [String], model: SiteModel) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Text(label).foregroundStyle(.secondary)
                controllerLinks(ids, model: model)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).foregroundStyle(.secondary)
                controllerLinks(ids, model: model)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func controllerLinks(_ ids: [String], model: SiteModel) -> some View {
        HStack(spacing: 10) {
            ForEach(ids, id: \.self) { id in ControllerNoteLink(controllerId: id, model: model) }
        }
    }

    // MARK: overview

    /// The counts, each a tile that opens its full list. Each tile is its own tap target (`StatTile(route:)`), so a tap opens
    /// that tile's list only. A cell leaves out the kinds of machine it has none of, as the web page does, and adds its cameras.
    static func overview(_ model: SiteModel) -> some View {
        Section("Overview") {
            overviewTiles(model)
                .placeholderWhileLoading(model.isLoadingStats && !model.hasLoadedStats)
        }
    }

    @ViewBuilder
    private static func overviewTiles(_ model: SiteModel) -> some View {
        let isCell = model.cellId != nil
        // The count is of the levels the person has on, Critical and Error until they choose others.
        let shownAlarms = AlarmLevelPreference.shared.activeFilter.visible(model.alarms)
        tileGrid {
            if !isCell || !model.controllers.isEmpty {
                StatTile(label: "Controllers", value: model.controllers.count.formatted(), symbol: "server.rack",
                    route: .siteList(.controllers, organizationKey: model.sessionKey), identifier: "statTile.controllers")
            }
            if !model.virtualControllers.isEmpty {
                StatTile(label: "Virtual controllers", value: model.virtualControllers.count.formatted(), symbol: "square.stack.3d.up",
                    route: .siteList(.virtualControllers, organizationKey: model.sessionKey), identifier: "statTile.virtualControllers")
            }
            if isCell && !model.cameras.isEmpty {
                StatTile(label: "Cameras", value: model.cameras.count.formatted(), symbol: "video",
                    route: .siteList(.cameras, organizationKey: model.sessionKey), identifier: "statTile.cameras")
            }
            StatTile(label: "Active alarms", value: shownAlarms.count.formatted(), symbol: "bell.badge", tint: shownAlarms.isEmpty ? nil : Color.statusError,
                route: .siteList(.alarms, organizationKey: model.sessionKey), identifier: "statTile.alarms")
            StatTile(label: "Incidents", value: model.incidents.count.formatted(), symbol: "exclamationmark.triangle",
                route: .siteList(.incidents, organizationKey: model.sessionKey), identifier: "statTile.incidents")
            StatTile(label: "Open tickets", value: model.openTickets.count.formatted(), symbol: "tray.full",
                route: .siteList(.tickets, organizationKey: model.sessionKey), identifier: "statTile.tickets")
        }
    }

    // MARK: resource rows

    @ViewBuilder
    static func mobileRobotsRow(_ model: SiteModel) -> some View {
        if model.robots.robotCount == 0 {
            LabeledContent("Mobile robots") { Text("None reported").foregroundStyle(.secondary) }
        } else {
            NavigationLink(value: PortalRoute.siteList(.mobileRobots, organizationKey: model.sessionKey)) {
                LabeledContent("Mobile robots") { Text("\(model.robots.onlineCount) of \(model.robots.robotCount) online").monospacedDigit() }
            }
        }
    }

    static func orchestratorsRow(_ model: SiteModel) -> some View {
        NavigationLink(value: PortalRoute.siteList(.orchestrators, organizationKey: model.sessionKey)) {
            LabeledContent("Orchestrators") {
                let summary = SiteOrchestratorSummary(model.orchestrators)
                HStack(spacing: 6) {
                    if summary.hasError { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusError).accessibilityLabel(Text("Has an error")) }
                    if summary.totalCount == 0 && summary.withoutOwnStatusCount == 0 {
                        Text("None reported").foregroundStyle(.secondary)
                    } else if summary.totalCount == 0 {
                        Text("\(summary.withoutOwnStatusCount) without a line status").foregroundStyle(.secondary)
                    } else {
                        Text("\(summary.runningCount) of \(summary.totalCount) running").monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: building blocks

    static func tileGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        StatGrid { content() }
            .navigationLinkIndicatorVisibility(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
    }

    /// The last row of a capped section: all of them on a page of their own.
    @ViewBuilder
    static func showAll(_ kind: SiteListKind, model: SiteModel, count: Int, isShown: Bool) -> some View {
        if isShown {
            NavigationLink(value: PortalRoute.siteList(kind, organizationKey: model.sessionKey)) { Text("Show all (\(count))").foregroundStyle(.tint) }
        }
    }

    // MARK: the few worst of each

    @ViewBuilder
    static func controllers(_ model: SiteModel) -> some View {
        if !model.controllers.isEmpty {
            Section("Controllers") {
                ForEach(SiteSections.top(model.controllers)) { controller in
                    NavigationLink(value: PortalRoute.controller(controller)) { SiteRows.controller(controller, isSiteTotal: controller.id == model.sourceControllerId) }
                }
                showAll(.controllers, model: model, count: model.controllers.count, isShown: SiteSections.hasMore(model.controllers))
            }
        }
    }

    @ViewBuilder
    static func virtualControllers(_ model: SiteModel) -> some View {
        if !model.virtualControllers.isEmpty {
            Section("Virtual controllers") {
                ForEach(SiteSections.top(model.virtualControllers)) { virtual in
                    NavigationLink(value: PortalRoute.virtualController(virtual)) { SiteRows.virtualController(virtual) }
                }
                showAll(.virtualControllers, model: model, count: model.virtualControllers.count, isShown: SiteSections.hasMore(model.virtualControllers))
            }
        }
    }

    @ViewBuilder
    static func alarms(_ model: SiteModel) -> some View {
        if !model.alarms.isEmpty {
            let shown = AlarmLevelPreference.shared.activeFilter.visible(model.alarms)
            Section("Alarms") {
                ActiveAlarmRows.rows(model.alarms, controllers: model.controllers, limit: SiteSections.shownCount)
                showAll(.alarms, model: model, count: shown.count, isShown: SiteSections.hasMore(shown))
            }
        }
    }

    /// The cameras: the first few with a picture, and all of them on a page of their own.
    @ViewBuilder
    static func cameras(_ model: SiteModel) -> some View {
        if !model.cameras.isEmpty {
            Section("Cameras") {
                ForEach(SiteSections.top(model.cameras)) { camera in
                    NavigationLink(value: PortalRoute.camera(CameraTarget(camera: camera))) { CameraRow(camera: camera) }
                }
                showAll(.cameras, model: model, count: model.cameras.count, isShown: SiteSections.hasMore(model.cameras))
            }
        }
    }

    @ViewBuilder
    static func incidents(_ model: SiteModel) -> some View {
        if !model.incidents.isEmpty {
            Section("Incidents") {
                ForEach(SiteSections.top(model.incidents)) { incident in
                    NavigationLink(value: PortalRoute.incident(incident)) { SiteRows.incident(incident) }
                }
                showAll(.incidents, model: model, count: model.incidents.count, isShown: SiteSections.hasMore(model.incidents))
            }
        }
    }
}

/// ControllerNoteLink is a controller's id in a note, which opens the controller. It is a tap target of its row and not a link, since
/// the note's row can hold several of them.
private struct ControllerNoteLink: View {
    @Environment(\.openRoute) private var openRoute
    let controllerId: String
    let model: SiteModel

    var body: some View {
        Text(controllerId)
            .foregroundStyle(.tint)
            .frame(minHeight: 44)
            .rowTapTarget {
                let controller = model.controllers.first { $0.id == controllerId }
                    ?? ControllerSummary(id: controllerId, siteId: model.selectedSiteId, organizationId: model.selectedSite?.organizationId)
                openRoute(.controller(controller))
            }
            .accessibilityIdentifier("controllerLink.\(controllerId)")
    }
}
