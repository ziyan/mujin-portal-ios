import PortalKit
import SwiftUI

/// DemoShare shows the share sheet with invented content, for screenshots.
@MainActor
enum DemoShare {
    @MainActor
    final class Backend: ShareBackend {
        let accounts: [Account]
        init() {
            let model = DemoServer.makeModel()
            accounts = model.accounts
        }
        func sites(accountKey: String) async throws -> [SiteSummary] {
            [SiteSummary(id: "site01", name: "site01"), SiteSummary(id: "site02", name: "site02"), SiteSummary(id: "site03", name: "site03")]
        }
        func start(_ job: ShareJob) async throws {}
        func job(id: String) -> ShareJob? { nil }
        func continueWithoutFailedFiles(jobId: String) async {}
        func discard(jobId: String) {}
    }

    static func view(ticket: Bool) -> some View {
        let files = [
            SharedFile(id: "file01", filename: "gripper.jpg", contentType: "image/jpeg", storedName: "file01", byteCount: 2_400_000),
            SharedFile(id: "file02", filename: "pick-log.pdf", contentType: "application/pdf", storedName: "file02", byteCount: 310_000),
        ]
        let model = ShareModel(
            backend: Backend(), jobId: "demo-job", text: "The gripper on controller01 stops after the second pick.\n\nhttps://example.test/status", files: files)
        if ticket {
            model.destination = .ticket
            model.siteId = "site01"
        }
        return ShareView(model: model, onFinish: {}, onCancel: {})
    }
}
