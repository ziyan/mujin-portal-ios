import PortalKit
import SwiftUI

/// MoreDestination is a screen pushed from More.
enum MoreDestination: Hashable {
    case automations
    case notificationSettings
    case about
}

/// MoreView is the last tab: the account, and what does not need a tab of its own.
struct MoreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var isShowingAccounts = false
    @State private var isConfirmingSignOut = false
    @State private var path: [MoreDestination] = DemoOptions.screen?.hasPrefix("automations") == true ? [.automations] : (DemoOptions.screen == "about" ? [.about] : [])
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
                    NavigationLink(value: MoreDestination.automations) {
                        Label("Automations", systemImage: "clock.arrow.2.circlepath")
                            .foregroundStyle(.primary)
                    }
                    Toggle(
                        "Show tool details",
                        isOn: Binding(
                            get: { AssistantDisplay.showsToolDetails(setting: toolDetailsSetting, persona: session.persona) },
                            set: { toolDetailsSetting = $0 ? "1" : "0" }))
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
.portalList()
            .navigationTitle("More")
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .automations: AutomationsView()
                case .notificationSettings: NotificationPreferencesView()
                case .about: AboutView()
                }
            }
            .sheet(isPresented: $isShowingAccounts) {
                AccountsView()
            }
            .onChange(of: session.automationsRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                session.automationsRequested = false
                path = [.automations]
            }
        }
    }
}
