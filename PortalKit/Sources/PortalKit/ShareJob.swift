import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// ShareDestination is where something shared to the app goes.
public enum ShareDestination: Codable, Equatable, Sendable {
    /// Starts a new conversation whose first message is this text and its files.
    case assistant(text: String)
    /// Opens a ticket.
    case ticket(title: String, description: String, siteId: String?, priority: String)
}

/// PendingFile is one file waiting to be uploaded for a job.
public struct PendingFile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let filename: String
    public let contentType: String
    /// The file's name inside the job's folder.
    public let storedName: String
    public let byteCount: Int64
    public var uploaded: UploadedFile?
    public var failure: String?

    public init(id: String = UUID().uuidString, filename: String, contentType: String, storedName: String, byteCount: Int64) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.storedName = storedName
        self.byteCount = byteCount
    }
}

/// ShareStatus is how far a job has got.
public enum ShareStatus: Codable, Equatable, Sendable {
    /// Files are being uploaded (or there are none and the send is next).
    case uploading
    /// The conversation or ticket is being created.
    case sending
    /// Done; the id is the conversation's or the ticket's.
    case done(String)
    case failed(String)
}

/// ShareJob is something shared to the app, on its way to Portal. It lives in
/// the app group's folder so the share extension can start it and the app can
/// finish it when the extension has gone.
public struct ShareJob: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let accountKey: String
    public let destination: ShareDestination
    public var files: [PendingFile]
    public var status: ShareStatus
    public let createdAt: Date

    public init(id: String = UUID().uuidString, accountKey: String, destination: ShareDestination, files: [PendingFile], createdAt: Date = Date()) {
        self.id = id
        self.accountKey = accountKey
        self.destination = destination
        self.files = files
        self.status = .uploading
        self.createdAt = createdAt
    }

    /// Whether every file has been uploaded, so the conversation or ticket can be made.
    public var isReadyToSend: Bool { files.allSatisfy { $0.uploaded != nil } }

    /// The first upload failure, in words for the person.
    public var firstFailure: String? { files.compactMap(\.failure).first }
}

/// ShareJobStore keeps jobs between processes.
public protocol ShareJobStore: Sendable {
    func jobs() -> [ShareJob]
    func job(id: String) -> ShareJob?
    func save(_ job: ShareJob) throws
    /// Changes a job under the store's lock and returns the result of the change.
    func update<Result>(id: String, _ change: (inout ShareJob) -> Result) -> Result?
    func remove(id: String)
    /// The folder a job's files are kept in.
    func directory(forJob id: String) -> URL
}

/// FileShareJobStore keeps each job as `<root>/<id>/job.json` beside its files.
public final class FileShareJobStore: ShareJobStore, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func directory(forJob id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func read(id: String) -> ShareJob? {
        guard let data = try? Data(contentsOf: directory(forJob: id).appendingPathComponent("job.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShareJob.self, from: data)
    }

    private func write(_ job: ShareJob) throws {
        let folder = directory(forJob: job.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(job).write(to: folder.appendingPathComponent("job.json"), options: .atomic)
    }

    public func jobs() -> [ShareJob] {
        lock.lock()
        defer { lock.unlock() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap { read(id: $0) }.sorted { $0.createdAt < $1.createdAt }
    }

    public func job(id: String) -> ShareJob? {
        lock.lock()
        defer { lock.unlock() }
        return read(id: id)
    }

    public func save(_ job: ShareJob) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(job)
    }

    public func update<Result>(id: String, _ change: (inout ShareJob) -> Result) -> Result? {
        lock.lock()
        defer { lock.unlock() }
        guard var job = read(id: id) else { return nil }
        let result = change(&job)
        try? write(job)
        return result
    }

    public func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory(forJob: id))
    }
}

/// ShareSender finishes jobs: it records what the uploads answered and, once
/// every file is up, makes the conversation or the ticket. It runs in the
/// extension while the extension lives and in the app after it.
public struct ShareSender: Sendable {
    public let store: any ShareJobStore
    public let connection: @Sendable (String) async -> Connection?

    public init(store: any ShareJobStore, connection: @escaping @Sendable (String) async -> Connection?) {
        self.store = store
        self.connection = connection
    }

    /// What the server answered to one file's upload.
    public func recordUpload(jobId: String, fileId: String, statusCode: Int, body: Data, error: Error? = nil) {
        _ = store.update(id: jobId) { job in
            guard let index = job.files.firstIndex(where: { $0.id == fileId }) else { return }
            if let error {
                job.files[index].failure = error.userFacingText
                return
            }
            switch statusCode {
            case 200, 201:
                struct Stored: Decodable { let id: String? }
                if let id = (try? JSONDecoder().decode(Stored.self, from: body))?.id, !id.isEmpty {
                    job.files[index].uploaded = UploadedFile(id: id, filename: job.files[index].filename, contentType: job.files[index].contentType)
                    job.files[index].failure = nil
                } else {
                    job.files[index].failure = Self.unreadable
                }
            case 401, 403:
                job.files[index].failure = Self.uploadsNotAccepted
            case 413:
                job.files[index].failure = Self.tooLarge
            default:
                job.files[index].failure = "HTTP \(statusCode)"
            }
        }
    }

    public static let uploadsNotAccepted = "This server does not accept file uploads from the app yet."
    public static let tooLarge = "A file is larger than the server takes."
    static let unreadable = "The server sent an answer the app cannot read."

    /// Makes the conversation or ticket when every file is up, or marks the
    /// job failed when an upload was refused. Safe to call from both
    /// processes and more than once: only one caller claims the send.
    @discardableResult
    public func finishIfReady(jobId: String) async -> ShareStatus? {
        enum Claim { case send(ShareJob), failed(String), wait }
        let claim = store.update(id: jobId) { job -> Claim in
            guard job.status == .uploading else { return .wait }
            if let failure = job.firstFailure {
                job.status = .failed(failure)
                return .failed(failure)
            }
            guard job.isReadyToSend else { return .wait }
            job.status = .sending
            return .send(job)
        }
        switch claim {
        case .send(let job):
            let status = await perform(job)
            _ = store.update(id: jobId) { $0.status = status }
            return status
        case .failed(let message):
            return .failed(message)
        case .wait, nil:
            return nil
        }
    }

    /// Drops the files that could not be uploaded and lets the rest go on.
    public func continueWithoutFailedFiles(jobId: String) async {
        _ = store.update(id: jobId) { job in
            job.files.removeAll { $0.failure != nil }
            job.status = .uploading
        }
        await finishIfReady(jobId: jobId)
    }

    /// Finishes every job that has all its files up, for the app to call when it starts.
    public func resumeAll() async {
        for job in store.jobs() where job.status == .uploading { await finishIfReady(jobId: job.id) }
    }

    func perform(_ job: ShareJob) async -> ShareStatus {
        guard let connection = await connection(job.accountKey) else { return .failed(PortalError.signedOut.errorDescription ?? "") }
        let files = job.files.compactMap(\.uploaded)
        do {
            switch job.destination {
            case .assistant(let text):
                let agent = try await connection.mainAgent()
                let conversation = try await connection.createConversation(agentId: agent.id)
                try await connection.sendMessage(conversationId: conversation.id, text: SharePayload.assistantMessage(text: text, files: files))
                return .done(conversation.id)
            case .ticket(let title, let description, let siteId, let priority):
                let ticketId = try await connection.createTicket(
                    title: title, description: SharePayload.ticketDescription(text: description, files: files), siteId: siteId, priority: priority)
                return .done(ticketId)
            }
        } catch {
            return .failed(error.userFacingText)
        }
    }
}

extension Error {
    /// The text of an error for a person: the app's own errors and the server's words.
    var userFacingText: String {
        if let error = self as? PortalError { return error.errorDescription ?? "" }
        return localizedDescription
    }
}
