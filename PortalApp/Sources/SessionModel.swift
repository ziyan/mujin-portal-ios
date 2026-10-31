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
    /// Questions and approvals that wait for the person, in any conversation.
    private(set) var waiting: [WaitingItem] = []
    /// The tab in front. Screens change it to take the person elsewhere.
    var selectedSection = AppSection.assistant
    /// A conversation the Assistant tab should open as soon as it can.
    var conversationToOpen: String?
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

    var waitingCounts: [String: Int] { waiting.countsByConversation }

    /// Reads what waits for the person. The web app asks every 30 seconds too.
    func refreshWaiting() async {
        do {
            waiting = try await connection.waiting()
        } catch {
            onError(error)
        }
    }

    /// Answers a question that waits, from the list, without opening the conversation.
    func answer(_ item: WaitingItem, with text: String) async -> String? {
        do {
            try await connection.answerQuestion(id: item.interactionId, answer: text)
            waiting.removeAll { $0.id == item.id }
            return nil
        } catch {
            onError(error)
            return error.userMessage
        }
    }

    func decide(_ item: WaitingItem, isApproved: Bool) async -> String? {
        do {
            try await connection.resolveToolApproval(id: item.interactionId, isApproved: isApproved)
            waiting.removeAll { $0.id == item.id }
            return nil
        } catch {
            onError(error)
            return error.userMessage
        }
    }

    /// Starts a conversation about the screen the person is looking at: the
    /// question goes out with the resource it is about, and the Assistant tab
    /// opens on the new conversation. Returns the reason it failed, if it did.
    func ask(about viewing: Viewing, question: String) async -> String? {
        do {
            let agent = try await connection.mainAgent()
            let conversation = try await connection.createConversation(agentId: agent.id)
            try await connection.sendMessage(conversationId: conversation.id, text: question, viewing: viewing)
            conversationToOpen = conversation.id
            selectedSection = .assistant
            return nil
        } catch {
            onError(error)
            return error.userMessage
        }
    }

    func load() async {
        do {
            async let loadedProfile = connection.profile()
            async let loadedCapabilities = connection.capabilities()
            let (newProfile, newCapabilities) = try await (loadedProfile, loadedCapabilities)
            profile = newProfile
            capabilities = newCapabilities
            phase = .loaded
            await refreshWaiting()
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
        guard let screen else { return nil }
        if screen.hasPrefix("section:") { return AppSection(rawValue: String(screen.dropFirst("section:".count))) }
        // Screens that live under More.
        if ["automations", "notifications", "about", "settings"].contains(where: { screen.hasPrefix($0) }) { return .more }
        return nil
    }

    /// Whether the demo person works for the administrator organization.
    static var isStaff: Bool { environment["PORTAL_DEMO_PERSONA"] == "staff" }
}
