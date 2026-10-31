import Foundation
import Testing

@testable import PortalKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite struct SharePayloadTests {
    let photo = UploadedFile(id: "file01", filename: "site photo (1).png", contentType: "image/png")
    let report = UploadedFile(id: "file02", filename: "report.pdf", contentType: "application/pdf")

    @Test func aMessageStartsWithOneLinkPerFileThenTheText() {
        let message = SharePayload.assistantMessage(text: "  What is this? ", files: [photo, report])
        #expect(
            message
                == """
                ![Attachment: site photo \\(1\\).png](/api/v1/attachment/file01)
                [Attachment: report.pdf](/api/v1/attachment/file02)

                What is this?
                """)
    }

    @Test func textAloneIsTrimmedAndFilesAloneAreJustLinks() {
        #expect(SharePayload.assistantMessage(text: " hi \n", files: []) == "hi")
        #expect(SharePayload.assistantMessage(text: "", files: [report]) == "[Attachment: report.pdf](/api/v1/attachment/file02)")
    }

    @Test func aTicketDescriptionUsesAttachmentTokens() {
        #expect(
            SharePayload.ticketDescription(text: "Broken gripper", files: [photo, report])
                == "Broken gripper\n\n![site photo \\(1\\).png](attachment:file01)\n\n[report.pdf](attachment:file02)")
        #expect(SharePayload.ticketDescription(text: "", files: []) == "")
    }

    @Test func theTitleIsTheFirstLineShortened() {
        #expect(SharePayload.suggestedTitle(from: "First line\nsecond") == "First line")
        let title = SharePayload.suggestedTitle(from: String(repeating: "a", count: 200), limit: 20)
        #expect(title.count == 20)
        #expect(title.hasSuffix("\u{2026}"))
        #expect(SharePayload.suggestedTitle(from: "") == "")
    }

    @Test func textAndAddressesAreCombined() {
        let text = SharePayload.combinedText(texts: [" Look at this "], urls: [URL(string: "https://example.test/a")!])
        #expect(text == "Look at this\n\nhttps://example.test/a")
    }
}

@Suite struct MultipartBodyTests {
    @Test func theBodyIsStreamedFromDiskWithTheRightFraming() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        // Larger than one chunk, so the copy loop runs more than once.
        let content = Data((0..<(MultipartBody.chunkBytes * 2 + 123)).map { UInt8($0 % 251) })
        try content.write(to: source)
        let destination = directory.appendingPathComponent("body")
        let length = try MultipartBody.write(boundary: "b1", filename: "a\"b.bin", contentType: "application/octet-stream", source: source, to: destination)
        let body = try Data(contentsOf: destination)
        #expect(Int64(body.count) == length)
        let head = "--b1\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a'b.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n"
        let tail = "\r\n--b1--\r\n"
        #expect(body.prefix(head.utf8.count) == Data(head.utf8))
        #expect(body.suffix(tail.utf8.count) == Data(tail.utf8))
        #expect(body.dropFirst(head.utf8.count).dropLast(tail.utf8.count) == content)
    }
}

@Suite struct ShareJobTests {
    func makeStore() -> FileShareJobStore {
        FileShareJobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func makeJob(destination: ShareDestination = .assistant(text: "Hello"), fileCount: Int = 1) -> ShareJob {
        ShareJob(
            accountKey: makeAccount().accountKey, destination: destination,
            files: (0..<fileCount).map { PendingFile(id: "f\($0)", filename: "file\($0).png", contentType: "image/png", storedName: "f\($0)", byteCount: 10) })
    }

    /// A server that records the mutations and accepts them.
    func sender(store: any ShareJobStore, calls: Guarded<[String]>, accept: Bool = true) -> ShareSender {
        let transport = ScriptedTransport { request in
            let body = request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            let query = body?["query"]?.stringValue ?? ""
            if query.contains("GetMainAgent") { return (200, ScriptedTransport.json(["data": ["GetMainAgent": ["id": "agent01"]]])) }
            if query.contains("CreateConversation") {
                calls.withValue { $0.append("CreateConversation") }
                return (200, ScriptedTransport.json(["data": ["CreateConversation": ["conversation": ["id": "conversation01"]]]]))
            }
            if query.contains("SendMessage") {
                let message = body?["variables"]?["message"]?.stringValue ?? ""
                calls.withValue { $0.append("SendMessage:" + message) }
                return (200, ScriptedTransport.json(["data": ["SendMessage": ["runId": "run01"]]]))
            }
            if query.contains("CreateTicket") {
                let ticket = body?["variables"]?["ticket"]
                calls.withValue { $0.append("CreateTicket:\(ticket?["siteId"]?.stringValue ?? "-"):\(ticket?["description"]?.stringValue ?? "")") }
                return (200, ScriptedTransport.json(["data": ["CreateTicket": ["ticket": ["id": "ticket01", "sequence": 7, "title": "t"]]]]))
            }
            return (404, Data())
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        return ShareSender(store: store, connection: { _ in connection })
    }

    @Test func theStoreKeepsJobsAndUpdatesThemUnderItsLock() throws {
        let store = makeStore()
        let job = makeJob()
        try store.save(job)
        #expect(store.jobs().map(\.id) == [job.id])
        let changed = store.update(id: job.id) { job -> Bool in
            job.status = .sending
            return true
        }
        #expect(changed == true)
        #expect(store.job(id: job.id)?.status == .sending)
        store.remove(id: job.id)
        #expect(store.job(id: job.id) == nil)
        #expect(store.update(id: "missing") { _ in 1 } == nil)
    }

    @Test func aTextOnlyShareStartsAConversationWithTheMessage() async throws {
        let store = makeStore()
        let calls = Guarded<[String]>([])
        let job = makeJob(fileCount: 0)
        try store.save(job)
        let status = await sender(store: store, calls: calls).finishIfReady(jobId: job.id)
        #expect(status == .done("conversation01"))
        #expect(calls.withValue { $0 } == ["CreateConversation", "SendMessage:Hello"])
        #expect(store.job(id: job.id)?.status == .done("conversation01"))
    }

    @Test func theSendWaitsForEveryFileAndThenLinksThem() async throws {
        let store = makeStore()
        let calls = Guarded<[String]>([])
        let job = makeJob(fileCount: 2)
        try store.save(job)
        let sender = sender(store: store, calls: calls)
        sender.recordUpload(jobId: job.id, fileId: "f0", statusCode: 200, body: ScriptedTransport.json(["id": "stored0"]))
        #expect(await sender.finishIfReady(jobId: job.id) == nil)
        sender.recordUpload(jobId: job.id, fileId: "f1", statusCode: 200, body: ScriptedTransport.json(["id": "stored1"]))
        #expect(await sender.finishIfReady(jobId: job.id) == .done("conversation01"))
        let message = calls.withValue { $0 }.last ?? ""
        #expect(message.contains("![Attachment: file0.png](/api/v1/attachment/stored0)"))
        #expect(message.contains("/api/v1/attachment/stored1"))
        #expect(message.hasSuffix("Hello"))
    }

    @Test func onlyOneCallerMakesTheConversation() async throws {
        let store = makeStore()
        let calls = Guarded<[String]>([])
        let job = makeJob(fileCount: 0)
        try store.save(job)
        let sender = sender(store: store, calls: calls)
        async let first = sender.finishIfReady(jobId: job.id)
        async let second = sender.finishIfReady(jobId: job.id)
        _ = await (first, second)
        #expect(calls.withValue { $0 }.filter { $0 == "CreateConversation" }.count == 1)
    }

    @Test func aRefusedUploadFailsTheJobInClearWords() async throws {
        let store = makeStore()
        let calls = Guarded<[String]>([])
        let job = makeJob()
        try store.save(job)
        let sender = sender(store: store, calls: calls)
        sender.recordUpload(jobId: job.id, fileId: "f0", statusCode: 401, body: Data())
        #expect(await sender.finishIfReady(jobId: job.id) == .failed(ShareSender.uploadsNotAccepted))
        #expect(calls.withValue { $0 }.isEmpty)
    }

    @Test func theSharerCanSendWithoutTheFilesThatFailed() async throws {
        let store = makeStore()
        let calls = Guarded<[String]>([])
        let job = makeJob()
        try store.save(job)
        let sender = sender(store: store, calls: calls)
        sender.recordUpload(jobId: job.id, fileId: "f0", statusCode: 401, body: Data())
        _ = await sender.finishIfReady(jobId: job.id)
        await sender.continueWithoutFailedFiles(jobId: job.id)
        #expect(store.job(id: job.id)?.status == .done("conversation01"))
        #expect(calls.withValue { $0 }.last == "SendMessage:Hello")
    }

    @Test func tooLargeAndServerErrorsAreNamed() throws {
        let store = makeStore()
        let job = makeJob(fileCount: 2)
        try store.save(job)
        let sender = sender(store: store, calls: Guarded([]))
        sender.recordUpload(jobId: job.id, fileId: "f0", statusCode: 413, body: Data())
        sender.recordUpload(jobId: job.id, fileId: "f1", statusCode: 500, body: Data())
        let failures = store.job(id: job.id)?.files.map(\.failure)
        #expect(failures == [ShareSender.tooLarge, "HTTP 500"])
    }

    @Test func aTicketUsesTheSiteAndTheTokenDescription() async throws {
        let store = makeStore()
        let calls = Guarded<[String]>([])
        let job = makeJob(destination: .ticket(title: "Gripper", description: "Broken", siteId: "site01", priority: "normal"))
        try store.save(job)
        let sender = sender(store: store, calls: calls)
        sender.recordUpload(jobId: job.id, fileId: "f0", statusCode: 200, body: ScriptedTransport.json(["id": "stored0"]))
        #expect(await sender.finishIfReady(jobId: job.id) == .done("ticket01"))
        #expect(calls.withValue { $0 } == ["CreateTicket:site01:Broken\n\n![file0.png](attachment:stored0)"])
    }

    @Test func resumingFinishesJobsWhoseFilesAreAllUp() async throws {
        let store = makeStore()
        let calls = Guarded<[String]>([])
        let ready = makeJob(fileCount: 0)
        try store.save(ready)
        await sender(store: store, calls: calls).resumeAll()
        #expect(store.job(id: ready.id)?.status == .done("conversation01"))
    }
}

@Suite struct MutationOfferTests {
    @Test func aCapabilityIsFoundIgnoringTheFirstLettersCase() async {
        let transport = ScriptedTransport { _ in
            (200, ScriptedTransport.json(["data": ["__type": ["fields": [["name": "SendMessage"], ["name": "RegisterPushDevice"]]]]]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        #expect(await connection.offersMutation("registerPushDevice"))
        #expect(await !connection.offersMutation("somethingElse"))
    }

    @Test func aFailedQueryMeansNotOffered() async {
        let transport = ScriptedTransport { _ in (500, Data()) }
        #expect(await !Connection(account: makeAccount(), transport: transport).offersMutation("registerPushDevice"))
    }
}

@Suite struct PushDeviceTokenTests {
    @Test func theTokenIsStoredAsHex() {
        let defaults = UserDefaults(suiteName: "push-token-test-\(UUID().uuidString)")!
        #expect(PushDeviceToken.hex(Data([0x00, 0xab, 0xff])) == "00abff")
        #expect(PushDeviceToken.stored(in: defaults) == nil)
        PushDeviceToken.store(Data([1, 2, 3]), in: defaults)
        #expect(PushDeviceToken.stored(in: defaults) == "010203")
    }
}
