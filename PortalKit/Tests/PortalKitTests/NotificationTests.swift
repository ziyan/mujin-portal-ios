import Foundation
import Testing

@testable import PortalKit

@Suite struct NotificationTests {
    @Test func aTicketNotificationIsAboutItsNumberAndTitleAndOpensTheTicket() {
        let notification = PortalNotification(
            id: "n1", kind: "ticket_comment", ticketId: "ticket01", ticket: .init(id: "ticket01", sequence: 12, title: "Gripper drops boxes"))
        #expect(notification.subject == "#12 Gripper drops boxes")
        #expect(notification.target == .ticket(id: "ticket01"))
        #expect(notification.isUnread)
    }

    @Test func aFailedJobNamesItAndItsFailure() {
        let notification = PortalNotification(id: "n2", kind: "agent_job_failed", readAt: "2026-03-01T10:00:00Z", agentJobName: "Morning check", agentJobFailureMessage: "Timed out.")
        #expect(notification.subject == "Morning check")
        #expect(notification.detail == "Timed out.")
        #expect(notification.target == .automations)
        #expect(!notification.isUnread)
    }

    @Test func incidentsAndAlarmsGoToTheirScreens() {
        #expect(PortalNotification(id: "a", kind: "incident", incident: .init(id: "i", title: "Pallet left in aisle")).subject == "Pallet left in aisle")
        #expect(PortalNotification(id: "a", kind: "incident").target == .incident)
        let alarm = PortalNotification(id: "b", kind: "alarm", siteName: "site01", alarmMessage: "Gripper fault")
        #expect(alarm.target == .site && alarm.detail == "site01" && alarm.subject == "Gripper fault")
        #expect(PortalNotification(id: "c", kind: "budget_alert").target == .none)
    }

    @Test func preferencesFallBackToTheDefaults() {
        var preferences = NotificationPreferences(rows: [.init(kind: "incident", channel: "push", isEnabled: false, minimumAlarmLevel: nil)])
        #expect(!preferences.isEnabled(kind: "incident", channel: "push"))
        #expect(preferences.isEnabled(kind: "incident", channel: "email"))
        #expect(preferences.isEnabled(kind: "alarm", channel: "in_app"))
        #expect(!preferences.isEnabled(kind: "agent_job_failed", channel: "email"))
        preferences.set(kind: "agent_job_failed", channel: "email", isEnabled: true)
        #expect(preferences.isEnabled(kind: "agent_job_failed", channel: "email"))
    }

    @Test func theInboxComesNewestFirst() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "ListNotifications": [
                    "notifications": [
                        ["id": "n1", "kind": "alarm", "createdAt": "2026-03-01T10:00:00Z"], ["id": "n2", "kind": "alarm", "createdAt": "2026-03-02T10:00:00Z"],
                    ]
                ]
            ]
        }
        #expect(try await connection.notifications().map(\.id) == ["n2", "n1"])
    }

    @Test func unreadCountAndMarkingRead() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            operation == "CountUnreadNotifications" ? ["CountUnreadNotifications": 3] : ["MarkNotificationRead": ["notification": ["id": "n1"]]]
        }
        #expect(try await connection.unreadNotificationCount() == 3)
        try await connection.markNotificationRead(id: "n1")
        #expect(sentVariables(transport.requests[1])["notificationId"] as? String == "n1")
    }

    @Test func aPreferenceChangeSendsKindChannelAndState() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["SetNotificationPreference": ["kind": "incident", "channel": "push", "isEnabled": false]] }
        try await connection.setNotificationPreference(kind: "incident", channel: "push", isEnabled: false)
        let variables = sentVariables(transport.requests[0])
        #expect(variables["kind"] as? String == "incident" && variables["channel"] as? String == "push" && variables["isEnabled"] as? Bool == false)
    }
}
