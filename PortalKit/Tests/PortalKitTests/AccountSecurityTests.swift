import Foundation
import Testing

@testable import PortalKit

@Suite struct AccountSecurityTests {
    static func records(_ json: String) throws -> [SignInRecord] {
        try JSONDecoder().decode([SignInRecord].self, from: Data(json.utf8))
    }

    @Test func aSessionDecodesWithItsPlace() throws {
        let rows = try Self.records(
            #"[{"id":"s1","comment":"","createdAt":"2026-03-01T10:00:00Z","usedAt":"2026-03-02T09:30:00Z","ip":"203.0.113.9","userAgent":"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1","location":{"city":"Springfield","country":"US"}}]"#
        )
        #expect(rows[0].location?.text == "Springfield, US")
        #expect(rows[0].deviceName == "Safari on iPhone")
        #expect(rows[0].lastSeenDate == PortalDate.parse("2026-03-02T09:30:00Z"))
    }

    @Test func aPlaceNamesWhicheverPartIsKnown() {
        #expect(SignInPlace(city: nil, country: "US").text == "US")
        #expect(SignInPlace(city: "", country: "").text == nil)
    }

    @Test func userAgentsAreNamedByBrowserAndSystem() {
        #expect(DeviceDescription.name(userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36 Edg/120.0") == "Edge on Windows")
        #expect(DeviceDescription.name(userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36") == "Chrome on Windows")
        #expect(DeviceDescription.name(userAgent: "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0") == "Firefox on Linux")
        #expect(DeviceDescription.name(userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.2 Safari/605.1.15") == "Safari on Mac")
        #expect(DeviceDescription.name(userAgent: "Mozilla/5.0 (iPad; CPU OS 17_2 like Mac OS X) AppleWebKit/605.1.15 CriOS/120.0 Mobile/15E148 Safari/604.1") == "Chrome on iPad")
        #expect(DeviceDescription.name(userAgent: "curl/8.4.0") == "curl")
        #expect(DeviceDescription.name(userAgent: "  ") == nil)
        #expect(DeviceDescription.name(userAgent: nil) == nil)
    }

    @Test func activeRecordsLeaveOutRevokedAndExpiredOnesAndComeMostRecentFirst() throws {
        let rows = try Self.records(
            """
            [{"id":"old","usedAt":"2026-01-01T00:00:00Z"},
             {"id":"new","usedAt":"2026-03-01T00:00:00Z"},
             {"id":"gone","usedAt":"2026-04-01T00:00:00Z","revokedAt":"2026-04-02T00:00:00Z"},
             {"id":"lapsed","usedAt":"2026-04-01T00:00:00Z","expiresAt":"2026-04-03T00:00:00Z"},
             {"id":"unused","createdAt":"2026-02-01T00:00:00Z"}]
            """)
        let now = PortalDate.parse("2026-05-01T00:00:00Z")!
        #expect(SignInRecords.active(rows, now: now).map(\.id) == ["new", "unused", "old"])
    }

    @Test func theCurrentSessionIsSplitOffOnlyWhenTheServerNamesOneThatIsListed() throws {
        let rows = try Self.records(#"[{"id":"a","usedAt":"2026-03-01T00:00:00Z"},{"id":"b","usedAt":"2026-03-02T00:00:00Z"}]"#)
        let now = PortalDate.parse("2026-05-01T00:00:00Z")!
        let named = SignInRecords.splitCurrent(SessionList(currentSessionId: "a", sessions: rows), now: now)
        #expect(named.current?.id == "a")
        #expect(named.others.map(\.id) == ["b"])
        // An app token has no session of its own: the id is empty, and no row may be called this device.
        let empty = SignInRecords.splitCurrent(SessionList(currentSessionId: "", sessions: rows), now: now)
        #expect(empty.current == nil)
        #expect(empty.others.map(\.id) == ["b", "a"])
        let unknown = SignInRecords.splitCurrent(SessionList(currentSessionId: "zzz", sessions: rows), now: now)
        #expect(unknown.current == nil)
        #expect(unknown.others.count == 2)
    }

    @Test func thisAppIsRecognizedByItsClientId() throws {
        let json = #"[{"id":"c1","clientId":"mujin-portal-ios","clientName":"Mujin Portal for iPhone","grantedScopes":["api:read","api:write"]},{"id":"c2","clientId":"third-party","clientName":""}]"#
        let apps = try JSONDecoder().decode([AuthorizedApp].self, from: Data(json.utf8))
        #expect(apps[0].isThisApp)
        #expect(!apps[1].isThisApp)
        #expect(apps[1].shownName == "third-party")
    }

    @Test func aPasskeyIsSyncedWhenItsBackupStateSaysSo() throws {
        let json = #"[{"id":"p1","name":"Phone","backupEligible":true,"backupState":true},{"id":"p2","name":"","backupEligible":true,"backupState":false}]"#
        let passkeys = try JSONDecoder().decode([Passkey].self, from: Data(json.utf8))
        #expect(passkeys[0].isSynced)
        #expect(!passkeys[1].isSynced)
        #expect(passkeys[1].shownName == "Passkey")
    }

    @Test func anSSHKeyHasTheFingerprintSSHKeygenPrints() {
        let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICycyCqsiXxn6a4o5TKG8ju7v2hXUI70olpYIej0XSWW demo-laptop"
        #expect(SSHFingerprint.sha256(publicKey: publicKey) == "SHA256:mggFDHbGudxjSOuIusTQwvr0XAXbRQxwAT2WfHgAYj8")
        #expect(SSHFingerprint.sha256(publicKey: "not a key") == nil)
        #expect(SSHFingerprint.sha256(publicKey: nil) == nil)
    }

    @Test func aWireGuardKeyIsShortenedToItsEnds() {
        #expect(WireGuardKey.abbreviated("abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG=") == "abcdef…CDEFG=")
        #expect(WireGuardKey.abbreviated("short") == "short")
        #expect(WireGuardKey.abbreviated("") == nil)
    }

    @Test func responsibilitiesAreLimitedToFive() {
        var activities: [String] = []
        for code in ProfessionalProfile.activityCodes.prefix(6) { activities = ProfessionalProfile.toggling(activities, code) }
        #expect(activities.count == 5)
        #expect(!ProfessionalProfile.canAddActivity(to: activities))
        #expect(ProfessionalProfile.toggling(activities, "operations").count == 4)
        #expect(ProfessionalProfile.canAddActivity(to: ProfessionalProfile.toggling(activities, "operations")))
    }

    @Test func revokingASessionSendsItsIdAndReadsTheBooleanAnswer() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in operation == "RevokeSession" ? ["RevokeSession": true] : [:] }
        try await connection.revokeSession(id: "s1")
        #expect(sentVariables(transport.requests[0])["sessionId"] as? String == "s1")
    }

    @Test func theSessionListAsksForNoRevokedOnesAndKeepsTheCurrentId() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["ListSessions": ["currentSessionId": "", "sessions": [["id": "s1", "usedAt": "2026-03-01T00:00:00Z"]], "meta": ["totalCount": 1]]]
        }
        let list = try await connection.sessions()
        #expect(list.currentSessionId.isEmpty)
        #expect(list.sessions.map(\.id) == ["s1"])
        #expect(sentVariables(transport.requests[0])["includeRevoked"] as? Bool == false)
    }

    @Test func revokedKeysAndPeersAreNotListed() async throws {
        let (keyConnection, _) = scriptedConnection { _, _ in
            ["ListSSHKeys": ["sshKeys": [["id": "k1", "comment": "a"], ["id": "k2", "comment": "b", "revokedAt": "2026-03-01T00:00:00Z"]]]]
        }
        #expect(try await keyConnection.sshKeys().map(\.id) == ["k1"])
        let (peerConnection, _) = scriptedConnection { _, _ in
            ["ListWireGuardPeers": ["wireGuardPeers": [["id": "w1"], ["id": "w2", "revokedAt": "2026-03-01T00:00:00Z"]]]]
        }
        #expect(try await peerConnection.wireGuardPeers().map(\.id) == ["w1"])
    }

    @Test func revokingAllTokensSendsEveryId() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["RevokeTokens": ["tokenIds": ["t1", "t2"]]] }
        try await connection.revokeTokens(ids: ["t1", "t2"])
        #expect(sentVariables(transport.requests[0])["tokenIds"] as? [String] == ["t1", "t2"])
    }

    @Test func theProfileSavesSendBothFieldsTheServerRequires() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ModifyMyProfessionalProfile": ["user": ["id": "user01"]]] }
        try await connection.saveProfessionalProfile(jobRole: "Line lead", jobActivities: ["safety"])
        let variables = sentVariables(transport.requests[0])
        #expect(variables["jobRole"] as? String == "Line lead")
        #expect(variables["jobActivities"] as? [String] == ["safety"])
    }
}
