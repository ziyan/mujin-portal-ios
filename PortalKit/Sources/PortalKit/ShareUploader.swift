#if canImport(Darwin)
    import Foundation

    /// ShareUploader sends a job's files to Portal through a background URL
    /// session that belongs to the app group. The system keeps the uploads
    /// going after the share extension is gone and wakes the app to finish
    /// them, so the same code runs in either process: each answer is recorded
    /// in the job, and the last one makes the conversation or the ticket.
    public final class ShareUploader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        public static let sessionIdentifier = "com.ziyan.mujinportal.share-upload"

        private let store: any ShareJobStore
        private let sender: ShareSender
        private let lock = NSLock()
        private var answers: [Int: Data] = [:]
        private var finishEventsHandler: (() -> Void)?
        private var onChange: (@Sendable (String) -> Void)?
        private lazy var session: URLSession = {
            let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
            configuration.sharedContainerIdentifier = AppGroup.identifier
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
            return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }()

        public init(store: any ShareJobStore, sender: ShareSender) {
            self.store = store
            self.sender = sender
            super.init()
        }

        /// Calls back with a job's id each time something about it changed.
        public func observe(_ handler: @escaping @Sendable (String) -> Void) {
            lock.lock()
            onChange = handler
            lock.unlock()
        }

        /// Reconnects to uploads the system kept going, so their answers arrive.
        public func reconnect() {
            _ = session
        }

        public func setFinishEventsHandler(_ handler: @escaping () -> Void) {
            lock.lock()
            finishEventsHandler = handler
            lock.unlock()
        }

        /// Starts a job: uploads its files, or goes straight to the send when it has none.
        public func start(_ job: ShareJob, connection: Connection) async throws {
            try store.save(job)
            guard !job.files.isEmpty else {
                await finish(jobId: job.id)
                return
            }
            let token = try await connection.accessToken()
            let server = await connection.server
            let folder = store.directory(forJob: job.id)
            for file in job.files {
                let boundary = "portal-\(UUID().uuidString)"
                let body = folder.appendingPathComponent(file.storedName + ".body")
                try MultipartBody.write(
                    boundary: boundary, filename: file.filename, contentType: file.contentType, source: folder.appendingPathComponent(file.storedName),
                    to: body)
                var request = URLRequest(url: server.endpoint("/api/v1/attachment"))
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let task = session.uploadTask(with: request, fromFile: body)
                task.taskDescription = "\(job.id)/\(file.id)"
                task.resume()
            }
        }

        private func notify(_ jobId: String) {
            lock.lock()
            let handler = onChange
            lock.unlock()
            handler?(jobId)
        }

        private func finish(jobId: String) async {
            await sender.finishIfReady(jobId: jobId)
            notify(jobId)
        }

        // MARK: URLSessionDataDelegate

        public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            answers[dataTask.taskIdentifier, default: Data()].append(data)
            lock.unlock()
        }

        public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let body = answers.removeValue(forKey: task.taskIdentifier) ?? Data()
            lock.unlock()
            let parts = (task.taskDescription ?? "").split(separator: "/").map(String.init)
            guard parts.count == 2 else { return }
            sender.recordUpload(
                jobId: parts[0], fileId: parts[1], statusCode: (task.response as? HTTPURLResponse)?.statusCode ?? 0, body: body, error: error)
            notify(parts[0])
            let jobId = parts[0]
            Task { await self.finish(jobId: jobId) }
        }

        public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            lock.lock()
            let handler = finishEventsHandler
            finishEventsHandler = nil
            lock.unlock()
            DispatchQueue.main.async { handler?() }
        }
    }

    #if canImport(Security)
        /// SharedConnections makes a Connection for an account from the shared keychain.
        public final class SharedConnections: @unchecked Sendable {
            private let lock = NSLock()
            private var connections: [String: Connection] = [:]
            private let accountStore: any AccountStore
            private let transport: any HTTPTransport

            public init(accountStore: any AccountStore = KeychainAccountStore(), transport: any HTTPTransport = URLSessionTransport()) {
                self.accountStore = accountStore
                self.transport = transport
            }

            public func connection(for accountKey: String) -> Connection? {
                lock.lock()
                defer { lock.unlock() }
                if let existing = connections[accountKey] { return existing }
                guard let account = try? accountStore.load(accountKey: accountKey) else { return nil }
                let connection = Connection(account: account, transport: transport, store: accountStore)
                connections[accountKey] = connection
                return connection
            }
        }
    #endif
#endif
