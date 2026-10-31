import PortalKit
import SwiftUI

/// AboutView says which app and which server this is.
struct AboutView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        List { PortalRows {
            Section {
                LabeledContent("Version") { Text(Self.versionText) }
                LabeledContent("Server") { Text(session.account.server.displayHost) }
                LabeledContent("Signed in as") { Text(session.account.email.isEmpty ? session.account.displayName : session.account.email) }
                if let organization = session.profile?.organizationName {
                    LabeledContent("Organization") { Text(organization) }
                }
                LabeledContent("Account type") {
                    Text(session.isStaff ? LocalizedStringKey("Mujin staff") : LocalizedStringKey("Customer"))
                }
            }
            Section("This server offers") {
                capability("Push notifications", session.capabilities.offersPushRegistration)
                capability("Chats with colleagues", session.capabilities.offersChats)
                capability("Active monitoring board", session.capabilities.offersMonitoringBoard)
                capability("Signing in the built-in browser", session.capabilities.offersWebSessionHandoff)
            }
        } }
.portalList()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func capability(_ name: LocalizedStringKey, _ isOffered: Bool) -> some View {
        LabeledContent(name) {
            Label(isOffered ? LocalizedStringKey("Yes") : LocalizedStringKey("Not yet"), systemImage: isOffered ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isOffered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .labelStyle(.titleAndIcon)
        }
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
