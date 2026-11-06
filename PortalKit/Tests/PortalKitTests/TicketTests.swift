import Foundation
import Testing

@testable import PortalKit

@Suite struct TicketTests {
    static let tickets = [
        Ticket(id: "t1", sequence: 1, title: "Gripper drops boxes", status: "open", requesterUserId: "user01", modifiedAt: "2026-03-01T10:00:00Z"),
        Ticket(id: "t2", sequence: 2, title: "Network drops", status: "pending", requesterUserId: "user02", assigneeUserId: "user01", modifiedAt: "2026-03-03T10:00:00Z"),
        Ticket(id: "t3", sequence: 3, title: "Camera offline", status: "new", requesterUserId: "user02", modifiedAt: "2026-03-02T10:00:00Z"),
        Ticket(id: "t4", sequence: 4, title: "Label printer", status: "solved", requesterUserId: "user01", modifiedAt: "2026-03-04T10:00:00Z"),
        Ticket(id: "t5", sequence: 5, title: "Old issue", status: "closed", requesterUserId: "user01", modifiedAt: "2026-02-01T10:00:00Z"),
    ]

    @Test func tabsHoldTheStatusesThatShareAStage() {
        #expect(TicketTab.open.contains("new") && TicketTab.open.contains("open") && TicketTab.open.contains("pending") && TicketTab.open.contains("hold"))
        #expect(!TicketTab.open.contains("solved") && TicketTab.solved.contains("solved") && TicketTab.closed.contains("closed"))
        #expect(!TicketTab.open.contains(nil))
    }

    @Test func theOpenTabShowsTheMostRecentlyChangedFirst() {
        let open = TicketFilter.apply(Self.tickets, tab: .open, scope: .everyone, userId: "user01")
        #expect(open.map(\.id) == ["t2", "t3", "t1"])
    }

    @Test func mineMeansAskedForOrAssigned() {
        let mine = TicketFilter.apply(Self.tickets, tab: .open, scope: .mine, userId: "user01")
        #expect(mine.map(\.id) == ["t2", "t1"])
        #expect(TicketFilter.apply(Self.tickets, tab: .open, scope: .mine, userId: "user03").isEmpty)
    }

    @Test func tabCountsFollowTheScope() {
        let counts = TicketFilter.counts(Self.tickets, scope: .mine, userId: "user01")
        #expect(counts[.open] == 2 && counts[.solved] == 1 && counts[.closed] == 1)
    }

    @Test func theQueueShowsUrgentFirstThenNewThenTheLongestWaiting() {
        let queue = [
            Ticket(id: "a", status: "open", priority: "normal", modifiedAt: "2026-03-01T10:00:00Z"),
            Ticket(id: "b", status: "new", priority: "normal", modifiedAt: "2026-03-03T10:00:00Z"),
            Ticket(id: "c", status: "pending", priority: "urgent", modifiedAt: "2026-03-04T10:00:00Z"),
            Ticket(id: "d", status: "open", priority: "normal", modifiedAt: "2026-02-01T10:00:00Z"),
            Ticket(id: "e", status: "solved", priority: "urgent", modifiedAt: "2026-02-01T10:00:00Z"),
        ]
        #expect(TicketQueue.needingAttention(queue, limit: 10).map(\.id) == ["c", "b", "d", "a"])
        #expect(TicketQueue.needingAttention(queue, limit: 2).map(\.id) == ["c", "b"])
    }

    @Test func aTicketIsNamedWithItsNumber() {
        #expect(Self.tickets[0].displayName == "#1 Gripper drops boxes")
        #expect(Ticket(id: "x", title: "No number").displayName == "No number")
    }

    @Test func assigneesMergeBothFields() {
        let ticket = Ticket(id: "x", assigneeUserId: "a", assigneeUserIds: ["a", "b"])
        #expect(Set(ticket.assigneeIds) == ["a", "b"])
    }

    @Test func bodiesSplitIntoWordsAndFiles() {
        let body = "The gripper dropped a box.\n\n![photo\\[1\\].jpg](attachment:att01)\n\n[log.txt](attachment:att02)\n\nThanks."
        #expect(
            TicketBody.parts(body) == [
                .text("The gripper dropped a box."),
                .attachment(id: "att01", name: "photo[1].jpg", kind: .image),
                .attachment(id: "att02", name: "log.txt", kind: .file),
                .text("Thanks."),
            ])
    }

    @Test func theWebsOtherFormsAreFilesToo() {
        let ulid = "01HZX3K9Q8W2M5N7P4R6T8V0AB"
        let body = "Photo:\n\n![frame_008.jpg](attachment:\(ulid))\n\n[clip.mp4](attachment:\(ulid))\n\n<video src=\"attachment:\(ulid)\" controls preload=\"metadata\" width=\"100%\" title=\"walk.mov\"></video>\n\n<iframe src=\"attachment:\(ulid)#page=2\" width=\"100%\" height=\"600\" title=\"report &quot;v2&quot;.pdf\"></iframe>\n\n![shot](/api/v1/attachment/\(ulid))"
        #expect(
            TicketBody.parts(body) == [
                .text("Photo:"),
                .attachment(id: ulid, name: "frame_008.jpg", kind: .image),
                .attachment(id: ulid, name: "clip.mp4", kind: .video),
                .attachment(id: ulid, name: "walk.mov", kind: .video),
                .attachment(id: ulid, name: "report \"v2\".pdf", kind: .pdf),
                .attachment(id: ulid, name: "shot", kind: .image),
            ])
        #expect(AttachmentKind.of(name: "Attachment: notes.txt", isImageSyntax: false) == .file)
        #expect(AttachmentKind.of(name: "scan.PNG", isImageSyntax: false) == .image)
        #expect(TicketBody.hasAttachments(body))
        #expect(!TicketBody.hasAttachments("no files here"))
    }

    @Test func anAssistantReplyWithRelativeImagesAndAVideoSplitsIntoFiles() {
        let first = "01HZSAMPLE00000000000000AA"
        let second = "01HZSAMPLE00000000000000BB"
        let video = "01HZSAMPLE00000000000000CC"
        let reply = "**Station 3 (c123)**: ![camera-a1b2c3.jpg](/api/v1/attachment/\(first))\n\n**Station 4 (c124)**: ![camera-d4e5f6.jpg](/api/v1/attachment/\(second)) and a clip [walk.mp4](/api/v1/attachment/\(video)) and [old.webm](/api/v1/attachment/\(video))\n\n<video src=\"/api/v1/attachment/\(video)\"></video>\n\n![remote](https://portal.example.test/api/v1/attachment/\(first))"
        #expect(
            TicketBody.parts(reply) == [
                .text("**Station 3 (c123)**:"),
                .attachment(id: first, name: "camera-a1b2c3.jpg", kind: .image),
                .text("**Station 4 (c124)**:"),
                .attachment(id: second, name: "camera-d4e5f6.jpg", kind: .image),
                .text("and a clip"),
                .attachment(id: video, name: "walk.mp4", kind: .video),
                .text("and"),
                .attachment(id: video, name: "old.webm", kind: .file),
                .attachment(id: video, name: "", kind: .video),
                .attachment(id: first, name: "remote", kind: .image),
            ])
        #expect(AttachmentKind.of(name: "clip.MOV", isImageSyntax: true) == .video)
        #expect(AttachmentKind.of(name: "clip.webm", isImageSyntax: true) == .file)
    }

    @Test func plainTextIsOnePart() {
        #expect(TicketBody.parts("Just words [and a link](https://example.test)") == [.text("Just words [and a link](https://example.test)")])
        #expect(TicketBody.parts("").isEmpty)
    }

    @Test func listingAsksForTheOrganizationAndSorts() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            [
                "ListTickets": [
                    "tickets": [
                        ["id": "t1", "status": "open", "modifiedAt": "2026-03-01T10:00:00Z"], ["id": "t2", "status": "open", "modifiedAt": "2026-03-02T10:00:00Z"],
                    ], "meta": ["totalCount": 2],
                ]
            ]
        }
        let tickets = try await connection.tickets(organizationId: "organization01")
        #expect(tickets.map(\.id) == ["t2", "t1"])
        #expect(sentVariables(transport.requests[0])["organizationId"] as? String == "organization01")
    }

    @Test func theThreadHidesDeletedCommentsAndReadsOldestFirst() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "ListTicketComments": [
                    ["id": "c2", "body": "Second", "createdAt": "2026-03-01T11:00:00Z"],
                    ["id": "c1", "body": "First", "createdAt": "2026-03-01T10:00:00Z", "isOriginalRequest": true],
                    ["id": "c3", "body": "Gone", "createdAt": "2026-03-01T12:00:00Z", "deletedAt": "2026-03-01T12:30:00Z"],
                ]
            ]
        }
        let comments = try await connection.ticketComments(ticketId: "t1")
        #expect(comments.map(\.id) == ["c1", "c2"])
    }

    @Test func aCommentCarriesItsBodyAndWhetherItIsInternal() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["CreateTicketComment": ["ticketComment": ["id": "c1", "body": "Hi"]]] }
        let comment = try await connection.addTicketComment(ticketId: "t1", body: "Hi", isInternal: true)
        #expect(comment?.id == "c1")
        let variables = sentVariables(transport.requests[0])
        #expect(variables["isInternal"] as? Bool == true)
        #expect(variables["body"] as? String == "Hi")
    }

    @Test func aMissingTicketIsAnError() async {
        let (connection, _) = scriptedConnection { _, _ in ["GetTicket": NSNull()] }
        await #expect(throws: PortalError.self) { try await connection.ticket(id: "nope") }
    }

    @Test func peopleAreShownByNameThenEmail() {
        #expect(PersonSummary(id: "u", name: "Alex Example", email: "alex@example.test").shownName == "Alex Example")
        #expect(PersonSummary(id: "u", name: "", email: "alex@example.test").shownName == "alex@example.test")
        #expect(PersonSummary(id: "u").shownName == nil)
    }

    @Test func organizationsAreSortedByNameAndInactiveOnesLeftOut() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "ListOrganizations": [
                    "organizations": [
                        ["id": "o2", "name": "beta Logistics", "isActive": true], ["id": "o1", "name": "Alpha Foods", "isActive": true],
                        ["id": "o3", "name": "Closed Co", "isActive": false],
                    ]
                ]
            ]
        }
        #expect(try await connection.organizations().map(\.id) == ["o1", "o2"])
    }

    @Test func uploadsAreRefusedBeforeTheyLeaveWhenTooLarge() async {
        let (connection, transport) = scriptedConnection { _, _ in [:] }
        let big = Data(count: Int(SharePayload.maximumFileBytes) + 1)
        await #expect(throws: PortalError.self) { try await connection.uploadAttachment(data: big, filename: "video.mov", contentType: "video/quicktime") }
        #expect(transport.requests.isEmpty)
        #expect(SharePayload.tooLargeMessage(name: "video.mov", byteCount: 40 << 20).hasPrefix("video.mov is "))
    }

    @Test func theAppRefusesWhatTheWebAppWouldRefuse() {
        #expect(AttachmentLimits.refusal(name: "photo.jpg", byteCount: 2 << 20, alreadyAttached: 0) == nil)
        let tooBig = AttachmentLimits.refusal(name: "scan.pdf", byteCount: 12 << 20, alreadyAttached: 0)
        #expect(tooBig?.contains("scan.pdf") == true && tooBig?.contains("10 MB") == true)
        #expect(AttachmentLimits.refusal(name: "a.txt", byteCount: 1, alreadyAttached: 10)?.contains("10 files") == true)
    }

    @Test func anUploadReturnsTheStoredFile() async throws {
        let transport = ScriptedTransport { request in
            #expect(request.url?.path == "/api/v1/attachment")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            return (201, ScriptedTransport.json(["id": "att01"]))
        }
        let file = try await Connection(account: makeAccount(), transport: transport).uploadAttachment(data: Data("hello".utf8), filename: "note.txt", contentType: "text/plain")
        #expect(file == UploadedFile(id: "att01", filename: "note.txt", contentType: "text/plain"))
        let body = String(decoding: transport.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("filename=\"note.txt\"") && body.contains("hello"))
    }

    @Test func aRefusedUploadSaysWhy() async {
        let transport = ScriptedTransport { _ in (413, Data()) }
        await #expect(throws: PortalError.refused(ShareSender.tooLarge)) {
            try await Connection(account: makeAccount(), transport: transport).uploadAttachment(data: Data("x".utf8), filename: "a.txt", contentType: "text/plain")
        }
    }

    @Test func anImageTagIsAPicture() {
        let parts = TicketBody.parts("Before\n\n<img src=\"attachment:01ABCDEF\" alt=\"new screen\" width=\"400\">\n\nAfter")
        #expect(parts == [.text("Before"), .attachment(id: "01ABCDEF", name: "new screen", kind: .image), .text("After")])
    }
}
