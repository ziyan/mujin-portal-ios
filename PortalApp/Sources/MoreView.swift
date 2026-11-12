import PortalKit
import SwiftUI

/// MoreDestination is a screen pushed from More.
enum MoreDestination: Hashable {
    case automations
    case notificationSettings
    case about
    case goals
    case goal(String)
    case ideas
    case knowledge
    case memoryPage(MemoryPageReference)
    case dreams
    case assistantSettings
    case incidents
    case releases
    case surveillance
    case release(String)
    case releaseImage(String)
    /// A screen of the person's account or of an organization's people.
    case account(AccountDestination)
    /// A screen of Platform settings.
    case platform(PlatformDestination)
    case settings
    /// The feedback about Portal the person sent, with how far each has come.
    case myFeedback
    case tabBarEditor
    /// The places that are usually tabs, pushed here while the person keeps them off the tab bar.
    case sites
    case tickets
}

/// MoreDestinationView is the screen a MoreDestination names. More pushes it, and a tab that holds one of these screens as its root
/// shows it the same way.
struct MoreDestinationView: View {
    let destination: MoreDestination
    /// Whether the screen is the root of a tab, which keeps the tab bar.
    var isTabRoot = false

    var body: some View {
        switch destination {
        case .automations: AutomationsView()
        case .notificationSettings: NotificationPreferencesView()
        case .about: AboutView()
        case .goals: GoalsView()
        case .goal(let id): GoalDetailView(goalId: id)
        case .ideas: IdeasView()
        case .knowledge: KnowledgeView()
        case .memoryPage(let reference): MemoryPageView(reference: reference)
        case .dreams: DreamsView()
        case .assistantSettings: AssistantSettingsView()
        case .incidents: IncidentsView()
        case .releases: ReleasesView()
        case .surveillance: SurveillanceView(isTabRoot: isTabRoot)
        case .release(let id): ReleaseDetailView(releaseId: id)
        case .releaseImage(let id): ReleaseImageView(imageId: id)
        case .account(let destination): AccountDestinationView(destination: destination)
        case .platform(let destination): PlatformDestinationView(destination: destination)
        case .settings: SettingsView(isTabRoot: isTabRoot)
        case .myFeedback: MyFeedbackView()
        case .tabBarEditor: TabBarEditorView()
        case .sites: SitesDestination()
        case .tickets: TicketsView(embedsNavigation: false)
        }
    }
}

/// SitesDestination is the Sites screen of the person's kind, pushed on More's stack.
private struct SitesDestination: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        if session.persona == .staff {
            StaffSitesView(embedsNavigation: false)
        } else {
            SiteView(embedsNavigation: false)
        }
    }
}

/// MoreView is the last tab: the places the tab bar does not hold. Settings, with the account and the tab bar, is one of them.
struct MoreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    // Screens under More push their own kinds of value (a release opens controllers), so the path holds any of them.
    @State private var path = NavigationPath(DemoOptions.morePath)

    var body: some View {
        let onBar = session.tabSections
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            List { PortalRows {
                if !onBar.contains(.site) || !onBar.contains(.tickets) {
                    Section {
                        row(.site, onBar)
                        row(.tickets, onBar)
                    }
                }
                Section {
                    Button {
                        session.isShowingNotifications = true
                    } label: {
                        HStack {
                            Label("Notifications", systemImage: "bell")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if session.unreadCount > 0 {
                                Text("\(session.unreadCount)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                AccountMoreSections()
                PlatformMoreSection()
                Section("Assistant") {
                    row(.goals, onBar)
                    row(.ideas, onBar)
                    row(.knowledge, onBar)
                    row(.automations, onBar)
                    NavigationLink(value: MoreDestination.dreams) {
                        Label("Tidying up", systemImage: "moon.stars")
                            .foregroundStyle(.primary)
                    }
                }
                Section {
                    if session.isStaff { row(.incidents, onBar) }
                    if session.surveillance.hasCameras { row(.surveillance, onBar).id("surveillanceRow") }
                    row(.releases, onBar)
                }
                if !onBar.contains(.settings) {
                    Section {
                        NavigationLink(value: MoreDestination.settings) {
                            Label("Settings", systemImage: "gearshape")
                                .foregroundStyle(.primary)
                        }
                        .accessibilityIdentifier("settingsRow")
                    }
                }
            } }
.portalRootList()
            .navigationTitle("More")
            .portalDestinations()
            .navigationDestination(for: MoreDestination.self) { destination in
                // A screen pushed from More has no use for the tab bar.
                MoreDestinationView(destination: destination)
                    .hidesTabBarWhenCompact()
            }
            .task {
                // The demo opens the releases list and taps the first row, as a person does.
                if appModel.isDemo, DemoOptions.screen == "release-tap" {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    path.append(PortalRoute.release(id: "release01"))
                }
            }
            .onChange(of: session.automationsRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                session.automationsRequested = false
                path = NavigationPath([MoreDestination.automations])
            }
            .onChange(of: session.incidentsRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                session.incidentsRequested = false
                path = NavigationPath([MoreDestination.incidents])
            }
            .onChange(of: session.moreScreenToOpen, initial: true) { _, destination in
                guard let destination else { return }
                session.moreScreenToOpen = nil
                path = NavigationPath([destination])
            }
            .onChange(of: session.ticketToOpen, initial: true) { _, ticketId in
                // With Tickets on the tab bar its own screen takes the ticket. Without, More opens the ticket on its stack.
                guard let ticketId, !onBar.contains(.tickets) else { return }
                session.ticketToOpen = nil
                session.moreScreenToOpen = nil
                var ticketPath = NavigationPath()
                ticketPath.append(MoreDestination.tickets)
                ticketPath.append(PortalRoute.ticket(id: ticketId))
                path = ticketPath
            }
            .onChange(of: session.goalToOpen, initial: true) { _, goalId in
                guard let goalId else { return }
                session.goalToOpen = nil
                path = NavigationPath([MoreDestination.goals, MoreDestination.goal(goalId)])
            }
            .task {
                // The screenshot run scrolls to the row it photographs.
                guard appModel.isDemo, let row = DemoOptions.moreRowToShow else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                proxy.scrollTo(row, anchor: .center)
            }
            }
        }
        .pushesRoutes { route in path.append(route) }
    }

    /// The row of a screen that can also be a tab. A screen on the tab bar is not listed again.
    @ViewBuilder
    private func row(_ section: AppSection, _ onBar: [AppSection]) -> some View {
        if !onBar.contains(section), let destination = section.moreDestination {
            NavigationLink(value: destination) {
                Label(section.titleKey, systemImage: section.symbol)
                    .foregroundStyle(.primary)
            }
        }
    }
}
