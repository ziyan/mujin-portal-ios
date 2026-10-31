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
}

/// MoreView is the last tab: the account, and what does not need a tab of its own.
struct MoreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var isShowingAccounts = false
    @State private var isConfirmingSignOut = false
    @State private var path: [MoreDestination] = DemoOptions.morePath
    @AppStorage("toolDetailsSetting") private var toolDetailsSetting = ""

    var body: some View {
        NavigationStack(path: $path) {
            List { PortalRows {
                Section {
                    Button {
                        isShowingAccounts = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName).foregroundStyle(.primary)
                            Text(account.server.displayHost).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("accountsButton")
                }
                Section {
                    Button {
                        session.isShowingNotifications = true
                    } label: {
                        HStack {
                            Label("Notifications", systemImage: "bell")
                                .foregroundStyle(.primary)
                            Spacer()
                            if session.unreadCount > 0 {
                                Text("\(session.unreadCount)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                    Toggle(
                        isOn: Binding(
                            get: { AssistantDisplay.showsToolDetails(setting: toolDetailsSetting, persona: session.persona) },
                            set: { toolDetailsSetting = $0 ? "1" : "0" })
                    ) { Label("Show tool details", systemImage: "wrench.and.screwdriver").foregroundStyle(.primary) }
                }
                Section {
                    NavigationLink(value: MoreDestination.about) {
                        Label("About", systemImage: "info.circle")
                            .foregroundStyle(.primary)
                    }
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
            } }
.portalRootList()
            .navigationTitle("More")
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
                }
                }
                .toolbarVisibility(.hidden, for: .tabBar)
            }
            .sheet(isPresented: $isShowingAccounts) {
                AccountsView()
            }
            .onChange(of: session.automationsRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                session.automationsRequested = false
                path = [.automations]
            }
            .onChange(of: session.goalToOpen, initial: true) { _, goalId in
                guard let goalId else { return }
                session.goalToOpen = nil
                path = [.goals, .goal(goalId)]
            }
        }
    }
}
