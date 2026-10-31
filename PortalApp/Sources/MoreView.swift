import PortalKit
import SwiftUI

/// MoreDestination is a screen pushed from More.
enum MoreDestination: Hashable {
    case automations
}

/// MoreView is the last tab: the account, and what does not need a tab of its own.
struct MoreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var isShowingAccounts = false
    @State private var path: [MoreDestination] = DemoOptions.screen?.hasPrefix("automations") == true ? [.automations] : []
    @AppStorage("toolDetailsSetting") private var toolDetailsSetting = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
            }
            .navigationTitle("More")
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .automations: AutomationsView()
                }
            }
            .sheet(isPresented: $isShowingAccounts) {
                AccountsView()
            }
        }
    }
}
