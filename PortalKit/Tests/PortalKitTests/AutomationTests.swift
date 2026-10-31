import Foundation
import Testing

@testable import PortalKit

@Suite struct AutomationTests {
    static let usEnglish = Locale(identifier: "en_US")

    @Test func costIsDividedByTheCurrencysMinorUnits() {
        // 12,300 millionths of a cent is 0.0123 dollars.
        #expect(CostFormat.amount(microMinorUnits: 1_230_000, currency: "USD") == 0.0123)
        // Yen have no minor unit: a million millionths is one yen.
        #expect(CostFormat.amount(microMinorUnits: 1_000_000, currency: "JPY") == 1)
        #expect(CostFormat.amount(microMinorUnits: 1_000_000, currency: "KWD") == 0.001)
    }

    @Test func belowOneUnitShowsFourDecimals() {
        #expect(CostFormat.string(microMinorUnits: 1_230_000, currency: "USD", locale: Self.usEnglish) == "$0.0123")
        #expect(CostFormat.string(microMinorUnits: 150_000_000, currency: "USD", locale: Self.usEnglish) == "$1.50")
        #expect(CostFormat.string(microMinorUnits: 500_000, currency: "JPY", locale: Self.usEnglish)?.hasSuffix("0.5000") == true)
    }

    @Test func zeroMeansUnpriced() {
        #expect(CostFormat.string(microMinorUnits: 0, currency: "USD") == nil)
        #expect(CostFormat.string(microMinorUnits: 100, currency: "") == nil)
    }

    @Test func occurrencesGroupByTheDevicesCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let occurrences = [
            ScheduleOccurrence(occursAt: "2026-03-02T01:00:00Z", subjectId: "job2", title: "Evening report"),
            ScheduleOccurrence(occursAt: "2026-03-01T22:00:00Z", subjectId: "job1", title: "Morning check"),
            ScheduleOccurrence(occursAt: "2026-03-01T10:00:00Z", subjectId: "job3", title: "Hourly look"),
            ScheduleOccurrence(occursAt: "not a date", subjectId: "job4", title: "Broken"),
        ]
        let days = AgentSchedule.groupedByDay(occurrences, calendar: calendar)
        // 10:00Z is 19:00 on the 1st in Tokyo; 22:00Z and 01:00Z are both on the 2nd.
        #expect(days.count == 2)
        #expect(days[0].occurrences.map(\.subjectId) == ["job3"])
        #expect(days[1].occurrences.map(\.subjectId) == ["job1", "job2"])
    }

    @Test func pollingContinuesWhileARunIsQueuedOrRunning() throws {
        let json = #"[{"id":"a1","activityStatus":"succeeded"},{"id":"a2","activityStatus":"running"}]"#
        let activities = try JSONDecoder().decode([AgentActivity].self, from: Data(json.utf8))
        #expect(activities.needsPolling)
        #expect(!Array(activities.prefix(1)).needsPolling)
    }

    @Test func anActivityRowDecodesWithItsCostAndTranscript() throws {
        let json = #"{"id":"a1","activityKind":"scheduled_job","activityStatus":"failed","title":"Morning check","costMicroMinorUnits":2500000,"costCurrency":"USD","conversationId":"conversation01","answerMessageId":"m9","errorMessage":"The model timed out."}"#
        let activity = try JSONDecoder().decode(AgentActivity.self, from: Data(json.utf8))
        #expect(activity.hasFailed && activity.hasTranscript && !activity.isInProgress)
        #expect(activity.costText != nil)
    }

    @Test func aWorkReportIsTheResultOrTheFailure() throws {
        func work(_ json: String) throws -> BackgroundWork { try JSONDecoder().decode(BackgroundWork.self, from: Data(json.utf8)) }
        #expect(try work(#"{"id":"w1","workState":"done","resultText":"Site one is faster."}"#).reportText == "Site one is faster.")
        #expect(try work(#"{"id":"w2","workState":"failed","errorMessage":"Out of budget.","resultText":"ignored"}"#).reportText == "Out of budget.")
        #expect(try work(#"{"id":"w3","workState":"running"}"#).reportText == nil)
        #expect(try work(#"{"id":"w3","workState":"queued"}"#).isInProgress)
    }

    @Test func theScheduleIsAskedForAtMost31DaysAndSortedSoonestFirst() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            [
                "ListAgentSchedule": [
                    "occurrences": [
                        ["occurrenceKind": "job", "occursAt": "2026-03-02T01:00:00Z", "subjectId": "job2", "title": "Later"],
                        ["occurrenceKind": "goal_check_in", "occursAt": "2026-03-01T01:00:00Z", "subjectId": "goal1", "title": "Earlier"],
                    ], "unreadableJobCount": 1,
                ]
            ]
        }
        let schedule = try await connection.schedule(dayCount: 90)
        #expect(schedule.occurrences.map(\.subjectId) == ["goal1", "job2"])
        #expect(schedule.unreadableJobCount == 1)
        #expect(sentVariables(transport.requests[0])["dayCount"] as? Int == 31)
    }

    @Test func stoppingWorkSendsItsId() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["StopBackgroundWork": ["backgroundWork": ["id": "w1", "workState": "stopped"]]] }
        try await connection.stopBackgroundWork(id: "w1")
        #expect(sentVariables(transport.requests[0])["id"] as? String == "w1")
    }

    @Test func activityAsksForTheWidenedScopeWhenTold() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ListAgentActivity": ["activities": [["id": "a1", "activityStatus": "queued"]], "meta": ["totalCount": 1]]] }
        let activities = try await connection.activity(includeOthers: true, organizationId: "organization01")
        #expect(activities.count == 1)
        let variables = sentVariables(transport.requests[0])
        #expect(variables["shouldIncludeOthers"] as? Bool == true)
        #expect(variables["organizationId"] as? String == "organization01")
    }
}
