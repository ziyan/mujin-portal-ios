import PortalKit
import SwiftUI

/// CellView is one cell of a site: the site page narrowed to the cell's machines and cameras. Its model is a `SiteModel` scoped to the
/// cell, so the sections, rows and full lists are the site page's own.
struct CellView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let cellId: String
    let siteId: String
    let organizationId: String?
    @State private var model: SiteModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.cell.map { $0.name ?? $0.id } ?? String(localized: "Cell"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task(id: cellId) {
            // The model is the session's, so it keeps what it loaded across a push and a pop.
            let cellModel = session.siteModel(for: organizationId, siteId: siteId, cellId: cellId)
            model = cellModel
            await cellModel.loadSites()
        }
    }

    @ViewBuilder
    private func content(_ model: SiteModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load this cell", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.loadSites(force: true) } }
            }
        case .loaded:
            if model.cell == nil {
                if model.isLoadingStats {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("Cell not found", systemImage: "square.grid.2x2")
                    } description: {
                        Text("It may have been removed from the site.")
                    }
                }
            } else {
                cellList(model)
            }
        }
    }

    private func isEmpty(_ model: SiteModel) -> Bool {
        model.hasLoadedStats && model.controllers.isEmpty && model.virtualControllers.isEmpty && model.cameras.isEmpty
    }

    private func cellList(_ model: SiteModel) -> some View {
        ScrollViewReader { proxy in
            List { PortalRows {
                if let description = model.cell?.description, !description.isEmpty {
                    Section { Text(description) }
                }
                if isEmpty(model) {
                    Section {
                        Text("Nothing is assigned to this cell yet.").foregroundStyle(.secondary)
                    }
                }
                SiteSectionViews.telemetry(model, showsViewAll: false)
                SiteSectionViews.overview(model)
                SiteSectionViews.controllers(model)
                SiteSectionViews.virtualControllers(model)
                SiteSectionViews.cameras(model)
                Section("Resources") {
                    SiteSectionViews.orchestratorsRow(model)
                    SiteSectionViews.mobileRobotsRow(model)
                }
                SiteSectionViews.alarms(model)
                SiteSectionViews.incidents(model)
                SiteSectionViews.tickets(model)
            } }
            .portalList()
            .routePushing()
            .refreshable { await model.loadDetails(force: true) }
            .task { await scrollToCamerasInDemo(proxy) }
        }
    }

    /// The demo's lower screenshot starts scrolled to the cameras, since the page is longer than the screen.
    private func scrollToCamerasInDemo(_ proxy: ScrollViewProxy) async {
        guard appModel.isDemo, DemoOptions.screen == "cell-lower" else { return }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if let first = model?.cameras.first { proxy.scrollTo(first.id, anchor: UnitPoint(x: 0.5, y: 0.25)) }
    }
}
