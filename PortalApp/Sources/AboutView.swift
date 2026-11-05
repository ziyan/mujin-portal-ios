import PortalKit
import SwiftUI

/// AboutView says which app and which server this is.
struct AboutView: View {
    @Environment(SessionModel.self) private var session
    @Environment(AppModel.self) private var appModel

    var body: some View {
        List { PortalRows {
            Section {
                LabeledContent("Version") { Text(Self.versionText) }
                // Stays after the bar is dismissed, so the update can still be found.
                if let update = appModel.updates.update {
                    Button { appModel.updates.install() } label: {
                        LabeledContent {
                            Text(update.versionText)
                        } label: {
                            Label("Update available", systemImage: "arrow.down.circle")
                        }
                    }
                    .accessibilityIdentifier("appUpdateRow")
                }
                LabeledContent("Server") { Text(session.account.server.displayHost) }
                LabeledContent("Signed in as") { Text(session.account.email.isEmpty ? session.account.displayName : session.account.email) }
                if let organization = session.profile?.organizationName {
                    LabeledContent("Organization") { Text(organization) }
                }
                LabeledContent("Account type") {
                    Text(session.isStaff ? LocalizedStringKey("Mujin staff") : LocalizedStringKey("Customer"))
                }
            }
        } }
.portalList()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
