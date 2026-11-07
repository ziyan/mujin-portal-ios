import Foundation
import Testing

@testable import PortalKit

@Suite struct PushTests {
    static func userInfo(_ portal: [String: Any], threadId: String? = "thread01") -> [AnyHashable: Any] {
        var aps: [String: Any] = ["category": "PORTAL_QUESTION"]
        if let threadId { aps["thread-id"] = threadId }
        return ["aps": aps, "portal": portal]
    }

    @Test func aQuestionPushReadsItsChoicesAndOffersThemAsButtons() throws {
        let payload = try #require(
            PushPayload(
                userInfo: Self.userInfo([
                    "userId": "user01", "organizationId": "org01", "kind": "agent_waiting", "waitingKind": "question", "interactionId": "q1",
                    "conversationId": "c1", "choices": ["Yes", "No", "", "Maybe", "Later", "Never"],
                ])))
        #expect(payload.isQuestion)
        #expect(payload.choices == ["Yes", "No", "Maybe", "Later"])
        #expect(payload.categoryIdentifier == "PORTAL_QUESTION.q1")
        #expect(payload.action(forButton: PushCategory.choiceAction(index: 2), text: nil) == .answerQuestion(id: "q1", answer: "Maybe"))
        #expect(payload.action(forButton: PushCategory.choiceAction(index: 4), text: nil) == nil)
        #expect(payload.action(forButton: PushCategory.replyAction, text: " It is fine ") == .answerQuestion(id: "q1", answer: "It is fine"))
        #expect(payload.action(forButton: PushCategory.replyAction, text: "  ") == nil)
        #expect(payload.threadId == "thread01")
    }

    @Test func choicesMayArriveAsJSONTextAndLongOnesAreClipped() throws {
        let long = String(repeating: "x", count: 60)
        let payload = try #require(
            PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_waiting", "waitingKind": "question", "interactionId": "q", "choices": "[\"One\",\"\(long)\"]"])))
        #expect(payload.choices.count == 2)
        #expect(payload.choices[1].count == PushCategory.maximumChoiceLength)
    }

    @Test func anApprovalPushApprovesOrDeniesBehindTheCategory() throws {
        let payload = try #require(
            PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_waiting", "waitingKind": "approval", "interactionId": "a1", "conversationId": "c1"])))
        #expect(payload.categoryIdentifier == PushCategory.approval)
        #expect(payload.action(forButton: PushCategory.approveAction, text: nil) == .resolveApproval(id: "a1", isApproved: true))
        #expect(payload.action(forButton: PushCategory.denyAction, text: nil) == .resolveApproval(id: "a1", isApproved: false))
        #expect(payload.route == .conversation(id: "c1"))
        let reply = PushPayload(userInfo: Self.userInfo(["userId": "u1", "kind": "ticket_comment", "ticketId": "t1"]))
        #expect(reply?.route == .ticket(id: "t1"))
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u1", "kind": "ticket_comment"]))?.route == .notifications)
    }

    @Test func aMessagePushRepliesIntoItsConversation() throws {
        let payload = try #require(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_message", "conversationId": "c9"], threadId: nil)))
        #expect(payload.categoryIdentifier == PushCategory.reply)
        #expect(payload.action(forButton: PushCategory.replyAction, text: "Thanks") == .reply(conversationId: "c9", text: "Thanks"))
        #expect(payload.resolvedThreadId == "c9")
        let chat = PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "chat_message", "conversationId": "c2", "chatId": "ch1"]))
        #expect(chat?.route == .chat(conversationId: "c2"))
    }

    @Test func otherKindsOpenTheirPlaceAndAnAnsweredPushIsPassive() throws {
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_goal_needs_you", "goalId": "g1"]))?.route == .goal(id: "g1"))
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_job_failed", "jobId": "j"]))?.route == .automations)
        #expect(PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "ticket_comment"]))?.route == .notifications)
        let answered = PushPayload(userInfo: Self.userInfo(["userId": "u", "kind": "agent_waiting", "waitingKind": "question", "interactionId": "q", "isAnswered": "true"]))
        #expect(answered?.isAnswered == true)
        #expect(PushPayload(userInfo: ["aps": [:]]) == nil)
        #expect(PushPayload(userInfo: Self.userInfo(["kind": "agent_message"])) == nil)
    }

    @Test func theEnvironmentComesFromTheBuild() {
        #expect(PushEnvironment(configured: "sandbox") == .sandbox)
        #expect(PushEnvironment(configured: " Production ") == .production)
        #expect(PushEnvironment(configured: nil) == .production)
        #expect(PushEnvironment(configured: "$(MUJINPORTAL_PUSH_ENVIRONMENT)") == .production)
    }

    @Test func registeringSendsTheTokenEnvironmentDeviceAndVersion() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["RegisterPushDevice": ["pushDevice": ["id": "d1"]]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        try await connection.registerPushDevice(deviceToken: "abcd", environment: .sandbox, deviceName: "Alex's phone", appVersion: "0.1.0 (7)")
        let body = try #require(transport.requests.last?.httpBody)
        let sent = try JSONDecoder().decode(JSONValue.self, from: body)
        let variables = try #require(sent["variables"])
        #expect(variables["deviceToken"]?.stringValue == "abcd")
        #expect(variables["environment"]?.stringValue == "sandbox")
        #expect(variables["deviceName"]?.stringValue == "Alex's phone")
        #expect(variables["appVersion"]?.stringValue == "0.1.0 (7)")
    }

    @Test func aButtonRunsTheOperationItStandsFor() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["ResolveToolApproval": true]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        try await connection.perform(.resolveApproval(id: "a1", isApproved: false))
        let sent = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests.last?.httpBody))
        #expect(sent["variables"]?["approvalId"]?.stringValue == "a1")
        #expect(sent["variables"]?["verdict"]?.stringValue == "rejected")
    }
}

@Suite struct PresenceTests {
    @Test func theReportCarriesVisibilityIdleTimeAndTheInstallID() async throws {
        let transport = ScriptedTransport { _ in
            (200, ScriptedTransport.json(["data": ["ReportAgentPresence": ["pendingSpeakFirst": ["speakFirstId": "sf1", "conversationId": "c7", "speakFirstReason": "idea"]]]]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        let pending = try await connection.reportPresence(isVisible: true, idleSeconds: 12, reporterId: "install01")
        #expect(pending == PendingSpeakFirst(speakFirstId: "sf1", conversationId: "c7", speakFirstReason: "idea"))
        let sent = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests.last?.httpBody))
        let variables = try #require(sent["variables"])
        #expect(variables["isVisible"]?.boolValue == true)
        #expect(variables["source"]?.stringValue == "app")
        #expect(variables["reporterId"]?.stringValue == "install01")
        #expect(variables["idleSeconds"]?.numberValue == 12)
    }

    @Test func aReportWithNothingPendingGivesNil() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["ReportAgentPresence": ["pendingSpeakFirst": NSNull()]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        #expect(try await connection.reportPresence(isVisible: false, idleSeconds: 0, reporterId: "i") == nil)
    }

    @Test func idleSecondsAreBoundedAndNeverNegative() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(PresenceRules.idleSeconds(since: now.addingTimeInterval(-42), now: now) == 42)
        #expect(PresenceRules.idleSeconds(since: now.addingTimeInterval(10), now: now) == 0)
        #expect(PresenceRules.idleSeconds(since: now.addingTimeInterval(-90_000), now: now) == PresenceRules.maximumIdleSeconds)
    }

    @Test func eachSpeakFirstConversationIsOpenedOnce() {
        let suiteName = "presence-tests-\(UUID().uuidString)"
        let memory = SpeakFirstMemory(defaults: { UserDefaults(suiteName: suiteName)! })
        let pending = PendingSpeakFirst(speakFirstId: "sf1", conversationId: "c1")
        #expect(memory.isNew(pending))
        memory.markHandled(pending)
        #expect(!memory.isNew(pending))
        #expect(memory.isNew(PendingSpeakFirst(speakFirstId: "sf2", conversationId: "c2")))
    }

    @Test func stoppingOnboardingSwitchesOffTheWholeFeature() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SetAgentSpeakFirst": ["isEnabledForUser": false], "SetAgentSpeakFirstReason": ["isEnabledForUser": true]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        try await connection.stopSpeakingFirst(reason: "onboarding")
        let first = try String(decoding: #require(transport.requests.last?.httpBody), as: UTF8.self)
        #expect(first.contains("SetAgentSpeakFirst(isEnabled"))
        try await connection.stopSpeakingFirst(reason: "idea")
        let second = try String(decoding: #require(transport.requests.last?.httpBody), as: UTF8.self)
        #expect(second.contains("SetAgentSpeakFirstReason"))
    }
}

@Suite struct NotificationFeedTests {
    static func fastTiming() -> FeedTiming {
        var timing = FeedTiming()
        timing.sleep = { _ in try await Task.sleep(nanoseconds: 1_000_000) }
        timing.pingInterval = 3_600
        timing.silenceLimit = 3_600
        return timing
    }

    static func frame(_ payload: String) -> FeedFrame {
        .text(#"{"id":"1","type":"next","payload":{"data":{"OnNotification":\#(payload)}}}"#)
    }

    @Test func aCreatedEventNamesTheRowAndAnOddOneIsIgnored() async {
        let socket = ScriptedSocket(frames: [
            ackFrame(),
            Self.frame(#"{"type":"created","notificationId":"n1","kind":"agent_message"}"#),
            Self.frame(#"{"type":"read","notificationId":"n2","kind":"alarm"}"#),
        ])
        let connection = Connection(account: makeAccount(), transport: ScriptedTransport { _ in (200, Data()) })
        var seen: [NotificationFeedUpdate] = []
        for await update in NotificationFeed.updates(connection: connection, socketFactory: { _, _ in socket }, timing: Self.fastTiming()) {
            seen.append(update)
            if seen.count == 2 { break }
        }
        #expect(seen == [.connected, .created(notificationId: "n1", kind: "agent_message")])
        #expect(socket.sent.contains { $0.contains("OnNotification") })
    }

    @Test func closeCode4401ReconnectsWithARenewedTokenAndAnnouncesItself() async {
        let sockets = Guarded<[ScriptedSocket]>([
            ScriptedSocket(frames: [ackFrame(), .closed(code: 4401)]),
            ScriptedSocket(frames: [ackFrame(), Self.frame(#"{"type":"created","notificationId":"n3","kind":"alarm"}"#)]),
        ])
        let transport = ScriptedTransport { request in
            if request.url?.path == "/.well-known/openid-configuration" {
                return (200, ScriptedTransport.json(OIDCClientTests.discovery))
            }
            return (200, ScriptedTransport.json(["access_token": "access-2", "refresh_token": "refresh-2", "expires_in": 300]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        var seen: [NotificationFeedUpdate] = []
        let factory: FeedSocketFactory = { _, _ in sockets.withValue { $0.removeFirst() } }
        for await update in NotificationFeed.updates(connection: connection, socketFactory: factory, timing: Self.fastTiming()) {
            seen.append(update)
            if case .created = update { break }
        }
        #expect(seen == [.connected, .reconnecting, .connected, .created(notificationId: "n3", kind: "alarm")])
    }
}


@Suite struct PageContextTests {
    @Test func everyMessageCarriesThePageEvenWithoutAResource() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SendMessage": ["runId": "r"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        _ = try await connection.sendMessage(conversationId: "c1", text: "Hi", pageTitle: "Weekly status")
        let viewing = sentVariables(try #require(transport.requests.last))["viewing"] as? [String: Any]
        #expect(viewing?["page"] as? String == "/agent/c1")
        #expect(viewing?["pageTitle"] as? String == "Weekly status")
        #expect(viewing?["kind"] == nil)
    }

    @Test func aResourceBringsItsOwnWebPath() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SendMessage": ["runId": "r"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        _ = try await connection.sendMessage(conversationId: "c1", text: "Why?", viewing: Viewing(kind: "ticket", id: "ticket01", label: "#1 Gripper drops boxes"))
        let viewing = sentVariables(try #require(transport.requests.last))["viewing"] as? [String: Any]
        #expect(viewing?["kind"] as? String == "ticket")
        #expect(viewing?["page"] as? String == "/ticket/ticket01")
        #expect(viewing?["pageTitle"] as? String == "#1 Gripper drops boxes")
    }

    @Test func pathsAndTitlesAreCleanedAndBounded() {
        #expect(PageContext.path("/site/site01?tab=1#x") == "/site/site01")
        #expect(PageContext.path("//evil.test/a") == nil)
        #expect(PageContext.path("site/site01") == nil)
        #expect(PageContext.path("/" + String(repeating: "a", count: 300))?.count == 200)
        #expect(PageContext.title("Line one\nline two") == "Line one line two")
        #expect(PageContext.title(String(repeating: "t", count: 300))?.count == 120)
        #expect(PageContext.title("  ") == nil)
        #expect(Viewing(kind: "virtual_controller", id: "virtual01").page == "/virtualcontroller/virtual01")
        #expect(Viewing(kind: "cell", id: "cell01").page == nil)
    }
}
