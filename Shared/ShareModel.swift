import Foundation
import Observation
import PortalKit

/// SharedFile is a file handed to the share sheet, already copied into the
/// job's folder in the app group.
struct SharedFile: Identifiable, Equatable {
    let id: String
    let filename: String
    let contentType: String
    let storedName: String
    let byteCount: Int64
    /// A small preview, made with ImageIO without decoding the whole image.
    var thumbnailData: Data?

    var pendingFile: PendingFile {
        PendingFile(id: id, filename: filename, contentType: contentType, storedName: storedName, byteCount: byteCount)
    }

    var isImage: Bool { contentType.lowercased().hasPrefix("image/") }
}

/// ShareBackend is what the share sheet needs from the app: its accounts and
/// a way to send a job. The extension and the app use the real one, the demo a fake.
@MainActor
protocol ShareBackend {
    var accounts: [Account] { get }
    func sites(accountKey: String) async throws -> [SiteSummary]
    func start(_ job: ShareJob) async throws
    func job(id: String) -> ShareJob?
    func continueWithoutFailedFiles(jobId: String) async
    func discard(jobId: String)
}

/// ShareModel is the share sheet's state: where the content goes and what is
/// said about it.
@MainActor
@Observable
final class ShareModel {
    enum Destination: String, CaseIterable, Identifiable {
        case assistant
        case ticket
        // Sending to a chat joins this list once Portal has chat operations.
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case editing
        case sending
        case done
        case failed(message: String, canContinueWithoutFiles: Bool)
    }

    static let priorities = ["low", "normal", "high", "urgent"]

    let backend: any ShareBackend
    let jobId: String
    let files: [SharedFile]
    /// Files left out, with the reason, such as one over the size limit.
    let skippedMessages: [String]

    var selectedAccountKey: String
    var destination = Destination.assistant
    var text: String
    var title: String
    var siteId = ""
    var priority = "normal"
    private(set) var sites: [SiteSummary] = []
    private(set) var isLoadingSites = false
    private(set) var sitesError: String?
    private(set) var phase = Phase.editing

    init(backend: any ShareBackend, jobId: String, text: String, files: [SharedFile], skippedMessages: [String] = []) {
        self.backend = backend
        self.jobId = jobId
        self.text = text
        self.title = SharePayload.suggestedTitle(from: text)
        self.files = files
        self.skippedMessages = skippedMessages
        self.selectedAccountKey = backend.accounts.first?.accountKey ?? ""
    }

    var accounts: [Account] { backend.accounts }
    var selectedAccount: Account? { accounts.first { $0.accountKey == selectedAccountKey } }

    func loadSites() async {
        guard destination == .ticket, !selectedAccountKey.isEmpty else { return }
        isLoadingSites = true
        sitesError = nil
        defer { isLoadingSites = false }
        do {
            sites = try await backend.sites(accountKey: selectedAccountKey)
            if !sites.contains(where: { $0.id == siteId }) { siteId = sites.count == 1 ? sites[0].id : "" }
        } catch {
            sites = []
            sitesError = error.userMessage
        }
    }

    var canSend: Bool {
        guard phase == .editing, selectedAccount != nil else { return false }
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty
        switch destination {
        case .assistant: return hasContent
        case .ticket: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (sites.isEmpty || !siteId.isEmpty)
        }
    }

    /// Starts the job and follows it until it is done or has failed.
    func send() async {
        guard canSend else { return }
        let target: ShareDestination =
            destination == .assistant
            ? .assistant(text: text)
            : .ticket(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: text, siteId: siteId.isEmpty ? nil : siteId, priority: priority)
        let job = ShareJob(id: jobId, accountKey: selectedAccountKey, destination: target, files: files.map(\.pendingFile))
        phase = .sending
        do {
            try await backend.start(job)
        } catch {
            phase = .failed(message: error.userMessage, canContinueWithoutFiles: false)
            return
        }
        await follow()
    }

    func continueWithoutFiles() async {
        phase = .sending
        await backend.continueWithoutFailedFiles(jobId: jobId)
        await follow()
    }

    /// Goes back to editing after a failure.
    func edit() {
        phase = .editing
    }

    private func follow() async {
        while !Task.isCancelled {
            if let job = backend.job(id: jobId) {
                switch job.status {
                case .done:
                    phase = .done
                    return
                case .failed(let message):
                    phase = .failed(message: message, canContinueWithoutFiles: !job.files.isEmpty && job.firstFailure != nil)
                    return
                case .uploading, .sending:
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }
}
