import Foundation
import PortalKit

/// LiveShareBackend sends shared content to the real Portal: files through
/// the app group's background session, then the conversation or the ticket.
@MainActor
final class LiveShareBackend: ShareBackend {
    let store: any ShareJobStore
    private let connections: SharedConnections
    private let uploader: ShareUploader
    private let sender: ShareSender
    private let ring: AccountRing

    init(accountStore: any AccountStore = KeychainAccountStore()) {
        let store = AppGroup.shareJobStore()
        let connections = SharedConnections(accountStore: accountStore)
        let sender = ShareSender(store: store, connection: { connections.connection(for: $0) })
        self.store = store
        self.connections = connections
        self.sender = sender
        self.uploader = ShareUploader(store: store, sender: sender)
        self.ring = (try? accountStore.loadRing()) ?? AccountRing()
        uploader.reconnect()
    }

    var accounts: [Account] {
        // The active account first, so it is the one chosen by default.
        guard let active = ring.active else { return ring.accounts }
        return [active] + ring.accounts.filter { $0.accountKey != active.accountKey }
    }

    func sites(accountKey: String) async throws -> [SiteSummary] {
        guard let connection = connections.connection(for: accountKey) else { throw PortalError.signedOut }
        return try await connection.sites()
    }

    func start(_ job: ShareJob) async throws {
        guard let connection = connections.connection(for: job.accountKey) else { throw PortalError.signedOut }
        try await uploader.start(job, connection: connection)
    }

    func job(id: String) -> ShareJob? { store.job(id: id) }

    func continueWithoutFailedFiles(jobId: String) async {
        await sender.continueWithoutFailedFiles(jobId: jobId)
    }

    /// Finishes jobs whose files are all up, for the app to call when it starts.
    func resumeAll() async {
        await sender.resumeAll()
    }

    func setFinishEventsHandler(_ handler: @escaping () -> Void) {
        uploader.setFinishEventsHandler(handler)
    }

    func discard(jobId: String) {
        store.remove(id: jobId)
    }
}
