import Foundation
import Observation
import PortalKit

/// SessionModel is what the app knows about the signed-in person once they
/// are in: who they are, which kind of person that is, and what their server
/// offers. The tabs and every screen under them read it.
@MainActor
@Observable
final class SessionModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let account: Account
    let connection: Connection
    private(set) var phase = Phase.loading
    private(set) var profile: Profile?
    private(set) var capabilities = ServerCapabilities()
    let onError: @MainActor (Error) -> Void

    init(account: Account, connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.account = account
        self.connection = connection
        self.onError = onError
    }

    var persona: Persona { profile?.persona ?? .customer }
    var userId: String { account.userId }
    var organizationId: String? { profile?.me.organizationId }
    var isStaff: Bool { persona == .staff }

    func load() async {
        do {
            async let loadedProfile = connection.profile()
            async let loadedCapabilities = connection.capabilities()
            let (newProfile, newCapabilities) = try await (loadedProfile, loadedCapabilities)
            profile = newProfile
            capabilities = newCapabilities
            phase = .loaded
        } catch {
            onError(error)
            if profile == nil { phase = .failed(error.userMessage) }
        }
    }
}

/// DemoOptions are the choices a screenshot run makes through the environment.
enum DemoOptions {
    private static let environment = ProcessInfo.processInfo.environment

    /// The raw screen name, such as `conversation:conversation02` or `section:tickets`.
    static var screen: String? { environment["PORTAL_DEMO_SCREEN"] }

    /// The tab to open on, from `section:<name>`.
    static var section: AppSection? {
        guard let screen, screen.hasPrefix("section:") else { return nil }
        return AppSection(rawValue: String(screen.dropFirst("section:".count)))
    }

    /// Whether the demo person works for the administrator organization.
    static var isStaff: Bool { environment["PORTAL_DEMO_PERSONA"] == "staff" }
}
