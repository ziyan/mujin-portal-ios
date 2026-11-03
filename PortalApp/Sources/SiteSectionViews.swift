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

    // MARK: overview

    /// The counts, each opening its full list. The site page lays them out as tiles. A cell page lists them as rows, one link to a row:
    /// links packed into one list row all fire on a single tap.
    @ViewBuilder
    static func overview(_ model: SiteModel) -> some View {
        if model.cellId != nil {
            cellOverview(model)
        } else {
            Section("Overview") {
                overviewTiles(model)
                    .placeholderWhileLoading(model.isLoadingStats && !model.hasLoadedStats)
            }
        }
    }

    /// A cell leaves out the kinds of machine it has none of, as the web page does.
    private static func cellOverview(_ model: SiteModel) -> some View {
        Section("Overview") {
            Group {
                if !model.controllers.isEmpty {
                    countRow("Controllers", count: model.controllers.count, kind: .controllers, model: model)
                }
                if !model.virtualControllers.isEmpty {
                    countRow("Virtual controllers", count: model.virtualControllers.count, kind: .virtualControllers, model: model)
                }
                if !model.cameras.isEmpty {
                    countRow("Cameras", count: model.cameras.count, kind: .cameras, model: model)
                }
                countRow("Active alarms", count: model.alarms.count, kind: .alarms, model: model, tint: model.alarms.isEmpty ? nil : Color.statusError)
                countRow("Incidents", count: model.incidents.count, kind: .incidents, model: model)
                countRow("Open tickets", count: model.openTickets.count, kind: .tickets, model: model)
            }
            .placeholderWhileLoading(model.isLoadingStats && !model.hasLoadedStats)
        }
    }

    private static func countRow(_ title: LocalizedStringKey, count: Int, kind: SiteListKind, model: SiteModel, tint: Color? = nil) -> some View {
        NavigationLink(value: PortalRoute.siteList(kind, organizationKey: model.sessionKey)) {
            LabeledContent(title) {
                Text(count.formatted()).monospacedDigit().foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            }
        }
    }

    @ViewBuilder
    private static func overviewTiles(_ model: SiteModel) -> some View {
        tileGrid {
            NavigationLink(value: PortalRoute.siteList(.controllers, organizationKey: model.sessionKey)) { StatTile(label: "Controllers", value: model.controllers.count.formatted(), symbol: "server.rack") }
                .buttonStyle(.plain)
                .navigationLinkIndicatorVisibility(.hidden)
            if model.virtualControllers.count > 0 {
                NavigationLink(value: PortalRoute.siteList(.virtualControllers, organizationKey: model.sessionKey)) { StatTile(label: "Virtual controllers", value: model.virtualControllers.count.formatted(), symbol: "square.stack.3d.up") }
                    .buttonStyle(.plain)
            }
            NavigationLink(value: PortalRoute.siteList(.alarms, organizationKey: model.sessionKey)) { StatTile(label: "Active alarms", value: model.alarms.count.formatted(), symbol: "bell.badge", tint: model.alarms.isEmpty ? nil : Color.statusError) }
                .buttonStyle(.plain)
            NavigationLink(value: PortalRoute.siteList(.incidents, organizationKey: model.sessionKey)) { StatTile(label: "Incidents", value: model.incidents.count.formatted(), symbol: "exclamationmark.triangle") }
                .buttonStyle(.plain)
            NavigationLink(value: PortalRoute.siteList(.tickets, organizationKey: model.sessionKey)) { StatTile(label: "Open tickets", value: model.openTickets.count.formatted(), symbol: "tray.full") }
                .buttonStyle(.plain)
                .navigationLinkIndicatorVisibility(.hidden)
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
                    NavigationLink(value: PortalRoute.controller(controller)) { SiteRows.controller(controller) }
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
            Section("Alarms") {
                ForEach(SiteSections.top(model.alarms)) { alarm in SiteRows.alarmLink(alarm, controllers: model.controllers) }
                showAll(.alarms, model: model, count: model.alarms.count, isShown: SiteSections.hasMore(model.alarms))
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

    @ViewBuilder
    static func tickets(_ model: SiteModel) -> some View {
        if !model.openTickets.isEmpty {
            Section("Tickets") {
                ForEach(SiteSections.top(model.openTickets)) { ticket in
                    NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) }
                }
                showAll(.tickets, model: model, count: model.openTickets.count, isShown: SiteSections.hasMore(model.openTickets))
            }
        }
    }
}
