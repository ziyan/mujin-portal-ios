import Foundation
import Testing

@testable import PortalKit

@Suite struct PlatformAccessTests {
    static func access(_ permissions: [String], mujin: Bool = false, own: String? = "org1") -> PlatformAccess {
        PlatformAccess(permissions: permissions, isMujinUser: mujin, viewerOrganizationId: own)
    }

    @Test func anOrdinaryMemberHasNoEntry() {
        let member = Self.access(["ticket:read", "site:read"])
        #expect(!member.hasEntry)
        #expect(!member.canReadAudit(of: "org1"))
        #expect(!member.canEditOrganization("org1"))
    }

    @Test func aCustomerAdministratorManagesTheirOwnOrganizationButNotBilling() {
        let admin = Self.access(["organization:operate-all"])
        #expect(admin.hasEntry)
        #expect(admin.canEditOrganization("org1"))
        #expect(admin.canReadAudit(of: "org1"))
        #expect(!admin.canEditOrganization("org2"))
        #expect(!admin.canReadAudit(of: "org2"))
        // The web offers billing to administrators of the Mujin organization only.
        #expect(!admin.canViewBilling(of: "org1"))
        #expect(!admin.canSetOrganizationActive)
        #expect(!admin.hasPlatformPages)
        #expect(admin.canSeeIncidentAlerts)
    }

    @Test func aPlatformAdministratorReachesEveryOrganizationAndEveryPage() {
        let platform = Self.access(["platform:administer"], mujin: true)
        #expect(platform.canEditOrganization("org2"))
        #expect(platform.canReadAudit(of: "org2"))
        #expect(platform.canReadPlatformAudit)
        #expect(platform.canViewBilling(of: "org2"))
        #expect(platform.canManageBilling(of: "org2"))
        #expect(platform.canSetOrganizationActive)
        #expect(platform.canReadUsage && platform.canSeePlans && platform.canManageProviders && platform.canManageAgents && platform.canDecideRegistrations)
        #expect(platform.canManageGrants)
    }

    @Test func aSingleReadingPermissionOpensOnlyTheAuditLogOfTheViewersOrganization() {
        let auditor = Self.access(["audit:read"])
        #expect(auditor.canReadAudit(of: "org1"))
        #expect(!auditor.canReadAudit(of: "org2"))
        #expect(!auditor.canReadPlatformAudit)
        #expect(auditor.hasEntry)
        #expect(!auditor.canEditOrganization("org1"))
    }

    @Test func aPlatformVerbOpensTheOneAreaItCovers() {
        let operatorOfProviders = Self.access(["provider:manage"], mujin: true)
        #expect(operatorOfProviders.canManageProviders)
        #expect(operatorOfProviders.canManageGrants)
        #expect(!operatorOfProviders.canManageAgents)
        #expect(!operatorOfProviders.canReadUsage)
        #expect(operatorOfProviders.hasEntry)
        let registrar = Self.access(["organization:create"], mujin: true)
        #expect(registrar.canDecideRegistrations)
        #expect(!registrar.canSeePlans)
        let usageReader = Self.access(["usage:read"], mujin: true)
        #expect(usageReader.canReadUsage)
        #expect(!usageReader.canReadPlatformAudit)
    }

    @Test func aMujinUserWithoutAnyOfThemHasNoEntry() {
        #expect(!Self.access(["ticket:read"], mujin: true).hasEntry)
    }

    @Test func billingNeedsTheBillingPermissionToChangeAnything() {
        let staffAdmin = Self.access(["organization:operate-all"], mujin: true)
        #expect(staffAdmin.canViewBilling(of: "org1"))
        #expect(staffAdmin.canManageBilling(of: "org1"))
        #expect(!staffAdmin.canViewBilling(of: "org2"))
    }
}

@Suite struct MoneyTests {
    static let american = Locale(identifier: "en_US")

    @Test func aMinorAmountIsWrittenInTheMajorUnit() {
        #expect(Money.format(minor: 1250, currency: "usd", locale: Self.american) == "$12.50")
        #expect(Money.format(minor: 0, currency: "USD", locale: Self.american) == "$0.00")
        #expect(Money.format(minor: 500, currency: "jpy", locale: Self.american).contains("500"))
        #expect(!Money.format(minor: 500, currency: "jpy", locale: Self.american).contains("."))
    }

    @Test func aTypedAmountBecomesMinorUnitsAndBack() {
        #expect(Money.minorUnits(from: "12.5", currency: "usd") == 1250)
        #expect(Money.minorUnits(from: " 1,200 ", currency: "usd") == 120_000)
        #expect(Money.minorUnits(from: "500", currency: "jpy") == 500)
        #expect(Money.minorUnits(from: "", currency: "usd") == nil)
        #expect(Money.minorUnits(from: "-3", currency: "usd") == nil)
        #expect(Money.minorUnits(from: "abc", currency: "usd") == nil)
        #expect(Money.editableText(minor: 1250, currency: "usd") == "12.5")
        #expect(Money.editableText(minor: 1000, currency: "usd") == "10")
        #expect(Money.editableText(minor: 500, currency: "jpy") == "500")
    }

    @Test func translationsArePickedByLanguageThenEnglish() {
        let names = [LocalizedText(locale: "de-DE", text: "Standard"), LocalizedText(locale: "en", text: "Standard plan"), LocalizedText(locale: "ja-JP", text: "")]
        #expect(LocalizedText.pick(names, languageCode: "de") == "Standard")
        #expect(LocalizedText.pick(names, languageCode: "fr") == "Standard plan")
        #expect(LocalizedText.pick(names, languageCode: "ja") == "Standard plan")
        #expect(LocalizedText.pick([], languageCode: "en") == nil)
        #expect(LocalizedText.pick(nil, languageCode: "en") == nil)
    }
}

@Suite struct PlatformUsageTests {
    static func rows() throws -> [ProviderUsageRow] {
        try JSONDecoder().decode(
            [ProviderUsageRow].self,
            from: Data(
                """
                [{"id":"u1","providerId":"p1","providerName":"Alpha","providerModelName":"model-a","organizationId":"org1","promptTokens":900,"completionTokens":100,"totalTokens":1000,"requestCount":3},
                 {"id":"u2","providerId":"p1","providerName":"Alpha","providerModelName":"model-a","organizationId":"org2","totalTokens":4000,"requestCount":2},
                 {"id":"u3","providerId":"p2","providerName":"Beta","providerModelName":"model-b","organizationId":"org1","promptTokens":50,"completionTokens":25,"requestCount":1}]
                """.utf8))
    }

    @Test func usageIsTotaledByModelAndByOrganization() throws {
        let summary = ProviderUsageSummary(rows: try Self.rows(), organizationNames: ["org1": "Example Foods"])
        #expect(summary.tokenCount == 5075)
        #expect(summary.requestCount == 6)
        #expect(summary.byModel.map(\.label) == ["Alpha, model-a", "Beta, model-b"])
        #expect(summary.byModel[0].tokenCount == 5000)
        #expect(summary.byOrganization.map(\.label) == ["Unknown organization", "Example Foods"])
        #expect(summary.byOrganization[1].tokenCount == 1075)
    }

    @Test func aWindowAsksForHoursWithinADayAndDaysBeyond() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UsageWindow.lastDay.intervalType == "hour")
        #expect(UsageWindow.lastWeek.intervalType == "day")
        #expect(UsageWindow.lastWeek.untilMilliseconds(now: now) - UsageWindow.lastWeek.sinceMilliseconds(now: now) == 7 * 86_400_000)
    }

    @Test func quantitiesAreWrittenCompactly() {
        #expect(UsageFormat.tokens(950) == "950")
        #expect(UsageFormat.tokens(12_300) == "12.3K")
        #expect(UsageFormat.tokens(4_500_000) == "4.5M")
        #expect(UsageFormat.bytes(0) == "0 B")
        #expect(UsageFormat.bytes(512) == "512 B")
        #expect(UsageFormat.bytes(1536) == "1.5 KB")
        #expect(UsageFormat.bytes(3 * 1024 * 1024 * 1024) == "3.0 GB")
        #expect(UsageFormat.duration(seconds: 0) == "0s")
        #expect(UsageFormat.duration(seconds: 45) == "45s")
        #expect(UsageFormat.duration(seconds: 725) == "12m 5s")
        #expect(UsageFormat.duration(seconds: 12_000) == "3h 20m")
        #expect(UsageFormat.duration(seconds: 3 * 86_400 + 4 * 3_600) == "3d 4h")
    }

    @Test func controllersAreTotaledAcrossBucketsHeaviestFirst() throws {
        let rows = try JSONDecoder().decode(
            [ControllerUsageRow].self,
            from: Data(
                """
                [{"controllerId":"k1","controllerComment":"Line A","sent":100,"received":50,"up":3600},
                 {"controllerId":"k1","controllerComment":"Line A","sent":100,"received":50,"up":3600},
                 {"controllerId":"k2","controllerComment":"","sent":900,"received":10,"up":60}]
                """.utf8))
        let lines = ControllerUsageSummary.lines(rows)
        #expect(lines.map(\.label) == ["k2", "Line A"])
        #expect(lines[1].totalBytes == 300)
        #expect(lines[1].connectedSeconds == 7200)
    }
}

@Suite struct PlatformBillingTests {
    @Test func aSummaryDecodesAndExplainsWhyUsageIsBlocked() throws {
        let summary = try JSONDecoder().decode(
            OrganizationBilling.self,
            from: Data(#"{"currency":"usd","balance":2500,"spendingLimit":10000,"spendingFractionPercent":40,"blocked":true,"blockReason":"spending_limit","onDefaultPlan":false}"#.utf8))
        #expect(summary.currencyCode == "usd")
        #expect(summary.blockMessage == "The spending limit has been reached.")
        #expect(summary.money(2500, locale: Locale(identifier: "en_US")) == "$25.00")
        let free = try JSONDecoder().decode(OrganizationBilling.self, from: Data(#"{"onDefaultPlan":true}"#.utf8))
        #expect(free.blockMessage == nil)
        #expect(free.currencyCode == "usd")
    }

    @Test func plansListTheOfferedOnesFirstInTheCatalogsOrder() throws {
        let plans = try JSONDecoder().decode(
            [Plan].self,
            from: Data(
                """
                [{"id":"p3","name":"retired","isActive":false,"deletedAt":"2026-01-01T00:00:00Z"},
                 {"id":"p2","name":"team","isActive":true,"sortOrder":2,"displayName":[{"locale":"en","text":"Team"}],"prices":[{"currency":"usd","baseFee":4900}]},
                 {"id":"p1","name":"free","isActive":true,"sortOrder":1},
                 {"id":"p4","name":"hidden","isActive":false}]
                """.utf8))
        let ordered = Plans.ordered(plans)
        #expect(ordered.map(\.id) == ["p1", "p2", "p4", "p3"])
        #expect(ordered[1].title() == "Team")
        #expect(ordered[0].title() == "free")
        #expect(ordered[1].baseFee(currency: "eur")?.amount == 4900)
        #expect(ordered[0].baseFee(currency: "usd") == nil)
    }

    @Test func removingALimitSendsNullAndKeepingAWarningSendsIt() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SetSpendingLimit": ["id": "org1"]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        try await connection.setSpendingLimit(organizationId: "org1", limit: nil, warning: 5000, clearWarning: false)
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any]
        let variables = body?["variables"] as? [String: Any]
        #expect(variables?["spendingLimit"] is NSNull)
        #expect(variables?["warning"] as? Int == 5000)
        #expect(variables?["clearWarning"] as? Bool == false)
    }

    @Test func aTransactionIsNamedByItsKind() throws {
        let rows = try JSONDecoder().decode(
            [BillingTransaction].self, from: Data(#"[{"id":"t1","kind":"top_up","amount":5000},{"id":"t2","kind":"other"}]"#.utf8))
        #expect(rows.map(\.kindName) == ["Top-up", "Transaction"])
    }
}

@Suite struct PlatformAIAndAdminTests {
    @Test func providersAndAgentsAreOrdered() throws {
        let providers = try JSONDecoder().decode(
            [AIProvider].self,
            from: Data(#"[{"id":"p2","name":"zeta","providerType":"openai","apiKeyFingerprint":"…1234"},{"id":"p1","name":"Alpha","providerType":"anthropic"}]"#.utf8))
        let ordered = AICatalog.orderedProviders(providers)
        #expect(ordered.map(\.id) == ["p1", "p2"])
        #expect(ordered[1].hasAPIKey)
        #expect(!ordered[0].hasAPIKey)
        #expect(ordered[1].typeName == "OpenAI")
        #expect(AICatalog.providerName("p1", in: ordered) == "Alpha")
        #expect(AICatalog.providerName("gone", in: ordered) == "Removed provider")
        #expect(AICatalog.providerName("", in: ordered) == nil)
        let agents = try JSONDecoder().decode(
            [AIAgent].self, from: Data(#"[{"id":"a1","name":"Helper"},{"id":"a2","name":"Zed","isMain":true},{"id":"a3","name":"Alpha"}]"#.utf8))
        #expect(AICatalog.orderedAgents(agents).map(\.id) == ["a2", "a3", "a1"])
    }

    @Test func grantsAreReadFromBothLists() async throws {
        let transport = ScriptedTransport { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            if body.contains("ListOrganizationProviders") {
                return (200, ScriptedTransport.json(["data": ["ListOrganizationProviders": [["providerId": "p1"], ["providerId": "p2"]]]]))
            }
            return (200, ScriptedTransport.json(["data": ["ListOrganizationAgents": [["agentId": "a1"]]]]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        let grants = try await connection.aiGrants(organizationId: "org1")
        #expect(grants == AIGrants(providerIds: ["p1", "p2"], agentIds: ["a1"]))
    }

    @Test func changingAProviderSendsOnlyTheGivenFields() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["ModifyProvider": ["provider": ["id": "p1"]]]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        try await connection.modifyAIProvider(id: "p1", isEnabled: false)
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any]
        let provider = (body?["variables"] as? [String: Any])?["provider"] as? [String: Any]
        #expect(provider?.keys.sorted() == ["isEnabled"])
    }

    @Test func registrationsAreNamedAndWaitUntilDecided() throws {
        let rows = try JSONDecoder().decode(
            [OrganizationRegistration].self,
            from: Data(#"[{"id":"r1","organizationName":"Sample Freight","email":"pat@example.test","status":"pending"},{"id":"r2","email":"lee@example.test","status":"rejected"}]"#.utf8))
        #expect(rows[0].shownName == "Sample Freight")
        #expect(rows[0].isPending)
        #expect(rows[0].statusName == "Waiting")
        #expect(rows[1].shownName == "lee@example.test")
        #expect(!rows[1].isPending)
    }

    @Test func aConfidenceFloorIsAPercentageOrNothing() {
        #expect(IncidentAlerts.floor(fromPercentText: "70") == 0.7)
        #expect(IncidentAlerts.floor(fromPercentText: " ") == nil)
        #expect(IncidentAlerts.isValid(percentText: ""))
        #expect(IncidentAlerts.isValid(percentText: "0"))
        #expect(IncidentAlerts.isValid(percentText: "100"))
        #expect(!IncidentAlerts.isValid(percentText: "101"))
        #expect(!IncidentAlerts.isValid(percentText: "-1"))
        #expect(!IncidentAlerts.isValid(percentText: "high"))
        #expect(IncidentAlerts.percentText(0.7) == "70")
        #expect(IncidentAlerts.percentText(nil) == "")
        let alert = IncidentAlert(id: "i1", siteId: "s1", isEnabled: true, minimumConfidence: 0.85, createdAt: nil)
        #expect(alert.floorText == "85%")
        #expect(IncidentAlert(id: "i2", siteId: "s1", isEnabled: true, minimumConfidence: nil, createdAt: nil).floorText == "Every incident")
    }
}
