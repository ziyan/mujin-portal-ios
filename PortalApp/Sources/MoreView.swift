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
    case release(String)
    case releaseImage(String)
}

/// MoreView is the last tab: the account, and what does not need a tab of its own.
struct MoreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var isShowingAccounts = false
    @State private var isConfirmingSignOut = false
    // Screens under More push their own kinds of value (a release opens controllers), so the path holds any of them.
    @State private var path = NavigationPath(DemoOptions.morePath)

    var body: some View {
        NavigationStack(path: $path) {
            List { PortalRows {
                Section {
                    Button {
                        isShowingAccounts = true
                    } label: {
                        HStack(spacing: 12) {
                            UserAvatar(userId: account.userId, name: account.displayName, hasAvatar: session.profile?.me.hasAvatar, modifiedAt: session.profile?.me.modifiedAt, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName).foregroundStyle(Color.primary)
                                Text(account.server.displayHost).font(.footnote).foregroundStyle(Color.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    // A row that opens something reads as a navigation row: plain text, not the accent a Button takes in a list.
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("accountsButton")
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
                    NavigationLink(value: MoreDestination.notificationSettings) {
                        Label("Notification settings", systemImage: "gearshape")
                            .foregroundStyle(.primary)
                    }
                }
                Section("Assistant") {
                    NavigationLink(value: MoreDestination.goals) {
                        Label("Goals", systemImage: "scope")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: MoreDestination.ideas) {
                        Label("Ideas", systemImage: "lightbulb")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: MoreDestination.knowledge) {
                        Label("What it knows", systemImage: "brain.head.profile")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: MoreDestination.automations) {
                        Label("Automations", systemImage: "clock.arrow.2.circlepath")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: MoreDestination.dreams) {
                        Label("Tidying up", systemImage: "moon.stars")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: MoreDestination.assistantSettings) {
                        Label("Assistant settings", systemImage: "slider.horizontal.3")
                            .foregroundStyle(.primary)
                    }
                }
                Section {
                    if session.isStaff {
                        NavigationLink(value: MoreDestination.incidents) {
                            Label("Incidents", systemImage: "exclamationmark.shield")
                                .foregroundStyle(.primary)
                        }
                    }
                    NavigationLink(value: MoreDestination.releases) {
                        Label("Releases", systemImage: "shippingbox")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: MoreDestination.about) {
                        Label("About", systemImage: "info.circle")
                            .foregroundStyle(.primary)
                    }
                    if let exit = appModel.exitDemo {
                        Button("Exit demo", action: exit)
                    } else {
                        Button(role: .destructive) {
                            isConfirmingSignOut = true
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(Color.statusError)
                        }
                        .confirmationDialog("Sign out of this account?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                            Button("Sign out of \(account.displayName)", role: .destructive) { Task { await appModel.remove(account) } }
                        } message: {
                            Text("\(account.displayName) on \(account.server.displayHost) will be removed from this phone.")
                        }
                    }
                }
            } }
.portalRootList()
            .navigationTitle("More")
            .portalDestinations()
            .navigationDestination(for: MoreDestination.self) { destination in
                // A screen pushed from More has no use for the tab bar.
                Group {
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
                case .release(let id): ReleaseDetailView(releaseId: id)
                case .releaseImage(let id): ReleaseImageView(imageId: id)
                }
                }
                .toolbarVisibility(.hidden, for: .tabBar)
            }
            .sheet(isPresented: $isShowingAccounts) {
                AccountsView()
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
            .onChange(of: session.goalToOpen, initial: true) { _, goalId in
                guard let goalId else { return }
                session.goalToOpen = nil
                path = NavigationPath([MoreDestination.goals, MoreDestination.goal(goalId)])
            }
        }
    }
}
