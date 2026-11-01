import PortalKit
import SwiftUI

/// SiteSwitcher is the site's name in the middle of the navigation bar, as a menu of the sites to switch to: one section per
/// organization. When there are many sites the menu offers "All sites" instead, which opens a searchable list. Customers and
/// Mujin users share it; it only needs the groups to show.
struct SiteSwitcher: View {
    let title: String
    let groups: [SiteGroup]
    let selectedSiteId: String?
    let onSelect: (SiteSummary) -> Void

    @State private var isShowingAll = false

    /// More sites than this and the menu gives way to the searchable list.
    static let menuLimit = 16

    private var count: Int { groups.reduce(0) { $0 + $1.sites.count } }

    var body: some View {
        Menu {
            if count <= Self.menuLimit {
                ForEach(groups) { group in
                    if groups.count > 1 {
                        Section(group.organizationName ?? String(localized: "Unknown organization")) { rows(group) }
                    } else {
                        rows(group)
                    }
                }
            } else {
                // The group of the site on screen first, then the way to the rest.
                if let current = groups.first(where: { $0.sites.contains { $0.id == selectedSiteId } }) {
                    Section(current.organizationName ?? String(localized: "Unknown organization")) { rows(current) }
                }
                Button("All sites…") { isShowingAll = true }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.headline)
                Image(systemName: "chevron.down.circle.fill").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("siteSwitcher")
        .accessibilityLabel(Text("Change site"))
        .sheet(isPresented: $isShowingAll) {
            AllSitesPicker(groups: groups, selectedSiteId: selectedSiteId) { site in
                isShowingAll = false
                onSelect(site)
            }
        }
    }

    @ViewBuilder
    private func rows(_ group: SiteGroup) -> some View {
        ForEach(group.sites) { site in
            Button {
                onSelect(site)
            } label: {
                if site.id == selectedSiteId {
                    Label(site.name ?? site.id, systemImage: "checkmark")
                } else {
                    Text(site.name ?? site.id)
                }
            }
        }
    }
}

/// AllSitesPicker lists every site by organization with a search, for choosing one when the menu would be too long.
private struct AllSitesPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionModel.self) private var session
    let groups: [SiteGroup]
    let selectedSiteId: String?
    let onSelect: (SiteSummary) -> Void
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            let shown = SiteGroups.group(groups.flatMap(\.sites), organizationNames: Dictionary(groups.map { ($0.organizationId, $0.organizationName ?? "") }, uniquingKeysWith: { first, _ in first }), query: searchText)
            List { PortalRows {
                ForEach(shown) { group in
                    Section(group.organizationName ?? String(localized: "Unknown organization")) {
                        ForEach(group.sites) { site in
                            Button {
                                onSelect(site)
                            } label: {
                                HStack {
                                    Text(site.name ?? site.id).foregroundStyle(Color.primary)
                                    Spacer()
                                    if site.id == selectedSiteId { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } }
            .portalList()
            .navigationTitle("Sites")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sites")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
