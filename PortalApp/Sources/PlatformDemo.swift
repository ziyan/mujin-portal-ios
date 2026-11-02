import Foundation
import PortalKit

/// PlatformDemo answers the platform settings documents on the demo server, from invented organizations, audit entries, usage, billing,
/// providers, agents, registrations and alerts. A change the app makes (a new name, a limit, a switch) sticks until the app is closed.
/// Every name here is made up.
enum PlatformDemo {
    /// The screens of the screenshot run that belong here.
    static func owns(_ screen: String) -> Bool { screen.hasPrefix("platform-") }

    /// The screens under More the screenshot run opens on.
    static func morePath(_ screen: String) -> [MoreDestination] {
        let customer = "organization01"
        switch screen {
        case "platform-hub": return [.platform(.hub)]
        case "platform-organizations": return [.platform(.hub), .platform(.organizations)]
        case "platform-organization": return [.platform(.hub), .platform(.organizations), .platform(.organization(id: "organization02"))]
        case "platform-organization-own": return [.platform(.hub)]
        case "platform-audit": return [.platform(.hub), .platform(.auditLog(organizationId: customer))]
        case "platform-audit-all": return [.platform(.hub), .platform(.auditLog(organizationId: nil))]
        case "platform-audit-event": return [.platform(.hub), .platform(.auditLog(organizationId: customer)), .platform(.auditEvent(sampleAuditEvent))]
        case "platform-usage": return [.platform(.hub), .platform(.usage)]
        case "platform-controller-usage": return [.platform(.hub), .platform(.controllerUsage)]
        case "platform-billing": return [.platform(.hub), .platform(.billing(organizationId: customer))]
        case "platform-billing-staff": return [.platform(.hub), .platform(.organizations), .platform(.organization(id: customer)), .platform(.billing(organizationId: customer))]
        case "platform-transactions": return [.platform(.hub), .platform(.billing(organizationId: customer)), .platform(.transactions(organizationId: customer))]
        case "platform-plans": return [.platform(.hub), .platform(.plans)]
        case "platform-providers": return [.platform(.hub), .platform(.providers)]
        case "platform-provider": return [.platform(.hub), .platform(.providers), .platform(.provider(id: "provider01"))]
        case "platform-agents": return [.platform(.hub), .platform(.agents)]
        case "platform-agent": return [.platform(.hub), .platform(.agents), .platform(.agent(id: "agent01"))]
        case "platform-grants": return [.platform(.hub), .platform(.grants), .platform(.organizationGrants(organizationId: customer))]
        case "platform-registrations": return [.platform(.hub), .platform(.registrations)]
        case "platform-alerts": return [.platform(.hub), .platform(.incidentAlerts)]
        default: return []
        }
    }

    /// The audit entry that the detail screen opens on.
    static var sampleAuditEvent: AuditEvent {
        let json = """
            {"id":"audit1","createdAt":"2026-10-30T14:05:00Z","organizationId":"organization01","actorType":"user","actorLabel":"alex@example.test","action":"update",
             "resourceType":"virtual_controller","resourceId":"01HZAAAAAAAAAAAAAAAAAAAA01","before":{"name":"Training copy","size":"small","comment":""},
             "after":{"name":"Training copy","size":"medium","comment":"Bigger for the demo day"},"sourceIp":"203.0.113.24","requestId":"request1",
             "requestRoute":"/api/v1/graphql","requestMethod":"POST","userAgent":"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1"}
            """
        return try! JSONDecoder().decode(AuditEvent.self, from: Data(json.utf8))
    }

    /// The answer to a document, or nil when it is not one of these.
    static func respond(operation: String, variables: [String: Any]) -> [String: Any]? {
        store.withData { data in answer(operation: operation, variables: variables, data: &data) }
    }

    // MARK: data

    private struct DemoData {
        var organizations: [[String: Any]]
        var auditEvents: [[String: Any]]
        var billing: [String: [String: Any]]
        var transactions: [[String: Any]]
        var providers: [[String: Any]]
        var agents: [[String: Any]]
        var providerGrants: [String: Set<String>]
        var agentGrants: [String: Set<String>]
        var registrations: [[String: Any]]
        var alerts: [[String: Any]]
        var nextNumber = 100
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var data = PlatformDemo.makeData()

        func withData<Result>(_ body: (inout DemoData) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(&data)
        }
    }

    private static let store = Store()

    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    private static func orNull(_ value: Int?) -> Any {
        if let value { return value }
        return NSNull()
    }

    private static func stamp(_ secondsAgo: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo))
    }

    private static func makeData() -> DemoData {
        func organization(_ id: String, _ name: String, isMujin: Bool = false, isActive: Bool = true, hasLogo: Bool = false) -> [String: Any] {
            ["id": id, "name": name, "isMujin": isMujin, "isActive": isActive, "hasLogo": hasLogo, "modifiedAt": "2026-01-01T00:00:00Z"]
        }
        func event(
            _ number: Int, ago: TimeInterval, actor: String, actorType: String = "user", action: String, resource: String, resourceId: String,
            before: Any = NSNull(), after: Any = NSNull(), address: String = "203.0.113.24", organizationId: String = "organization01"
        ) -> [String: Any] {
            [
                "id": "audit\(number)", "createdAt": stamp(ago), "organizationId": organizationId, "actorType": actorType, "actorLabel": actor, "action": action,
                "resourceType": resource, "resourceId": resourceId, "before": before, "after": after, "sourceIp": address, "requestId": "request\(number)",
                "requestRoute": "/api/v1/graphql", "requestMethod": "POST",
                "userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                "userId": NSNull(), "controllerId": NSNull(), "systemActor": NSNull(),
            ]
        }
        var events: [[String: Any]] = [
            event(1, ago: 12 * minute, actor: "alex@example.test", action: "update", resource: "virtual_controller", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA01", before: ["name": "Training copy", "size": "small"], after: ["name": "Training copy", "size": "medium"]),
            event(2, ago: 55 * minute, actor: "sam@example.test", action: "create", resource: "group", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA02", after: ["name": "Night shift", "description": "People on the night shift"], address: "198.51.100.7"),
            event(3, ago: 3 * hour, actor: "System", actorType: "system", action: "update", resource: "ticket", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA03", before: ["title": "Gripper drops boxes at pick station 3", "sequence": 12, "status": "open"], after: ["title": "Gripper drops boxes at pick station 3", "sequence": 12, "status": "solved"], address: ""),
            event(4, ago: 7 * hour, actor: "alex@example.test", action: "delete", resource: "api_token", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA04", before: ["comment": "Nightly export script"]),
            event(5, ago: day, actor: "robin@example.test", action: "update", resource: "user", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA05", before: ["name": "Robin Demo", "jobRole": ""], after: ["name": "Robin Demo", "jobRole": "Shift supervisor"], address: "192.0.2.55"),
            event(6, ago: 2 * day, actor: "alex@example.test", action: "create", resource: "role", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA06", after: ["name": "Auditor", "permissions": ["site:read", "audit:read"]]),
            event(7, ago: 3 * day, actor: "controller01", actorType: "controller", action: "update", resource: "controller", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA07", before: ["comment": "Line A"], after: ["comment": "Line A packing"], address: "10.0.0.8"),
            event(8, ago: 5 * day, actor: "sam@example.test", action: "update", resource: "site", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA08", before: ["name": "Hall 1"], after: ["name": "Packing hall"], address: "198.51.100.7"),
            event(9, ago: 9 * day, actor: "alex@example.test", action: "create", resource: "user", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA09", after: ["name": "Casey Illustration", "email": "casey@example.test"]),
            event(10, ago: 21 * day, actor: "alex@example.test", action: "delete", resource: "group", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA10", before: ["name": "Temporary crew"]),
        ]
        let ticketTitles = ["Scanner misreads labels", "Conveyor stops at merge", "Gripper drops boxes", "Wrong pallet height reported", "Camera feed freezes"]
        let pageTitles = ["Pick station start-up guide", "Shift handover checklist", "Charging area rules"]
        let controllerNames = ["Training copy", "Line A rehearsal", "Dock robots test"]
        let people = ["Robin Demo", "Jordan Placeholder", "Taylor Imaginary", "Morgan Fictional"]
        for number in 11...58 {
            let kind = ["ticket", "page", "virtual_controller", "user"][number % 4]
            let name: String
            switch kind {
            case "ticket": name = ticketTitles[number % ticketTitles.count]
            case "page": name = pageTitles[number % pageTitles.count]
            case "virtual_controller": name = controllerNames[number % controllerNames.count]
            default: name = people[number % people.count]
            }
            let key = kind == "ticket" || kind == "page" ? "title" : "name"
            var before: [String: Any] = [key: name, "comment": "Version \(number - 1)"]
            var after: [String: Any] = [key: name, "comment": "Version \(number)"]
            if kind == "ticket" { before["sequence"] = number; after["sequence"] = number }
            events.append(
                event(
                    number, ago: TimeInterval(number) * 14 * hour, actor: number % 3 == 0 ? "sam@example.test" : "alex@example.test", action: "update", resource: kind,
                    resourceId: "01HZAAAAAAAAAAAAAAAAAAAA\(number)", before: before, after: after, address: number % 2 == 0 ? "203.0.113.24" : "198.51.100.7"))
        }
        events.append(event(70, ago: 4 * hour, actor: "ana@example.test", action: "update", resource: "organization", resourceId: "organization02", before: ["name": "Sample Foods Ltd"], after: ["name": "Sample Foods"], address: "203.0.113.99", organizationId: "organization02"))
        events.append(event(71, ago: 30 * hour, actor: "pat@example.test", action: "create", resource: "ticket", resourceId: "01HZAAAAAAAAAAAAAAAAAAAA71", after: ["title": "Scanner misreads labels"], address: "192.0.2.12", organizationId: "organization02"))

        func billing(_ organizationId: String, currency: String, total: Int, balance: Int, limit: Int?, warning: Int?, fraction: Int, userLimit: Int?, userSpend: Int, isFree: Bool) -> [String: Any] {
            [
                "organizationId": organizationId, "planId": isFree ? "plan01" : "plan02", "currency": currency, "periodStartMillis": Int((Date().timeIntervalSince1970 - 12 * day) * 1000),
                "periodEndMillis": Int((Date().timeIntervalSince1970 + 18 * day) * 1000), "total": total, "overage": total / 3, "balance": balance, "availableBalance": balance - total / 3,
                "spendingLimit": orNull(limit), "warning": orNull(warning), "spendingFractionPercent": fraction, "isAutoReloadEnabled": false,
                "autoReloadThreshold": 0, "autoReloadAmount": 0, "blocked": false, "blockReason": "", "userSpendingLimit": orNull(userLimit), "userSpend": userSpend,
                "subscriptionStatus": isFree ? "free" : "active", "enforcementActive": true, "onDefaultPlan": isFree,
                "aiTokenLimits": [["scope": "organization", "interval": "cycle", "limit": 5_000_000, "used": 3_200_000]],
                "lineItems": [
                    ["dimension": "ai_tokens", "includedQuantity": 5_000_000, "usedQuantity": 3_200_000, "overageQuantity": 0, "cost": 0],
                    ["dimension": "virtual_controller_hours", "includedQuantity": 100, "usedQuantity": 120, "overageQuantity": 20, "cost": 4_000],
                    ["dimension": "storage_gib_day", "includedQuantity": 300, "usedQuantity": 210, "overageQuantity": 0, "cost": 0],
                ],
            ]
        }
        func transaction(_ number: Int, kind: String, amount: Int, balance: Int, description: String, ago: TimeInterval) -> [String: Any] {
            ["id": "transaction\(number)", "kind": kind, "amount": amount, "balanceAfter": balance, "currency": "usd", "description": description, "createdAt": stamp(ago), "periodStartedAt": stamp(ago), "stripeReceiptUrl": NSNull(), "lineItems": [Any]()]
        }
        func provider(_ id: String, _ name: String, type: String, model: String, enabled: Bool, key: String?) -> [String: Any] {
            [
                "id": id, "name": name, "providerType": type, "modelName": model, "baseUrl": "", "isEnabled": enabled, "capabilities": ["chat"], "contextWindow": 200_000,
                "maxOutputTokens": 8_192, "apiKeyFingerprint": key ?? NSNull(), "modifiedAt": stamp(10 * day),
            ]
        }
        func agent(_ id: String, _ name: String, _ description: String, main: Bool, enabled: Bool, provider: String, quick: String) -> [String: Any] {
            [
                "id": id, "name": name, "description": description, "systemPrompt": "You help the people of a warehouse understand what their robots are doing, and you ask before you change anything.",
                "isEnabled": enabled, "isMain": main, "defaultProviderId": provider, "quickProviderId": quick, "tools": [String](), "modifiedAt": stamp(6 * day),
            ]
        }
        func registration(_ id: String, _ organization: String, _ email: String, country: String, status: String, ago: TimeInterval) -> [String: Any] {
            ["id": id, "organizationName": organization, "email": email, "country": country, "status": status, "createdAt": stamp(ago)]
        }
        return DemoData(
            organizations: [
                organization("organization01", "Example Logistics", hasLogo: true), organization("organization02", "Sample Foods"), organization("organization00", "Support", isMujin: true),
                organization("organization03", "Placeholder Freight", isActive: false),
            ],
            auditEvents: events,
            billing: [
                "organization01": billing("organization01", currency: "usd", total: 18_250, balance: 25_000, limit: 50_000, warning: 40_000, fraction: 36, userLimit: 5_000, userSpend: 1_275, isFree: false),
                "organization02": billing("organization02", currency: "jpy", total: 52_000, balance: 100_000, limit: nil, warning: nil, fraction: 0, userLimit: nil, userSpend: 0, isFree: true),
            ],
            transactions: [
                transaction(1, kind: "charge", amount: -4_000, balance: 25_000, description: "Virtual controller hours over the allowance", ago: 2 * day),
                transaction(2, kind: "top_up", amount: 20_000, balance: 29_000, description: "Added funds", ago: 9 * day),
                transaction(3, kind: "charge", amount: -3_500, balance: 9_000, description: "Storage and virtual controller hours", ago: 33 * day),
                transaction(4, kind: "adjustment", amount: 2_500, balance: 12_500, description: "Credit for an interrupted day", ago: 40 * day),
                transaction(5, kind: "auto_reload", amount: 10_000, balance: 10_000, description: "Balance fell below the threshold", ago: 61 * day),
            ],
            providers: [
                provider("provider01", "Primary assistant", type: "anthropic", model: "model-large", enabled: true, key: "…a1b2"),
                provider("provider02", "Fast answers", type: "anthropic", model: "model-small", enabled: true, key: "…c3d4"),
                provider("provider03", "Backup", type: "openai", model: "model-mini", enabled: false, key: nil),
            ],
            agents: [
                agent("agent01", "Main assistant", "The assistant people talk to first.", main: true, enabled: true, provider: "provider01", quick: "provider02"),
                agent("agent02", "Site Helper", "Answers questions about one site.", main: false, enabled: true, provider: "provider01", quick: ""),
                agent("agent03", "Reporting Analyst", "Drafts weekly reports.", main: false, enabled: false, provider: "provider02", quick: ""),
            ],
            providerGrants: ["organization01": ["provider01", "provider02"], "organization02": ["provider01"]],
            agentGrants: ["organization01": ["agent01", "agent02"], "organization02": ["agent01"]],
            registrations: [
                registration("registration01", "Harbor Cold Storage", "pat.harbor@example.test", country: "US", status: "pending", ago: 3 * hour),
                registration("registration02", "Northfield Bakery", "lee.north@example.test", country: "CA", status: "pending", ago: day),
                registration("registration03", "Sample Parcel Co", "dana.parcel@example.test", country: "JP", status: "pending", ago: 4 * day),
                registration("registration04", "Example Logistics", "alex@example.test", country: "US", status: "approved", ago: 200 * day),
                registration("registration05", "Spam Test Ltd", "nobody@example.test", country: "US", status: "rejected", ago: 30 * day),
            ],
            alerts: [
                ["id": "alert01", "siteId": "site01", "isEnabled": true, "minimumConfidence": 0.7, "createdAt": stamp(30 * day)],
                ["id": "alert02", "siteId": "site03", "isEnabled": false, "minimumConfidence": NSNull(), "createdAt": stamp(10 * day)],
            ])
    }

    // MARK: audit filters

    /// Whether an audit entry passes the filter stages the app sent: the same operations the server runs, for the ones the app uses.
    private static func passes(_ event: [String: Any], filter: [String: Any]) -> Bool {
        let operation = filter["operation"] as? String ?? ""
        switch operation {
        case "and": return (filter["operands"] as? [[String: Any]] ?? []).allSatisfy { passes(event, filter: $0) }
        case "or": return (filter["operands"] as? [[String: Any]] ?? []).contains { passes(event, filter: $0) }
        case "in":
            let field = (filter["field"] as? [String])?.first ?? ""
            return (filter["value"] as? [String] ?? []).contains(event[field] as? String ?? "")
        case "insensitiveContains":
            let field = (filter["field"] as? [String])?.first ?? ""
            return (event[field] as? String ?? "").localizedCaseInsensitiveContains(filter["value"] as? String ?? "")
        case "greaterEqual":
            let field = (filter["field"] as? [String])?.first ?? ""
            guard let bound = ISO8601DateFormatter().date(from: filter["value"] as? String ?? ""), let moment = ISO8601DateFormatter().date(from: event[field] as? String ?? "") else { return true }
            return moment >= bound
        default: return true
        }
    }

    // MARK: answers

    private static func answer(operation: String, variables: [String: Any], data: inout DemoData) -> [String: Any]? {
        let identifier = { (key: String) in variables[key] as? String ?? "" }
        let options = variables["options"] as? [String: Any] ?? [:]
        switch operation {
        // Organizations.
        case "GetOrganizationProfile":
            guard let found = data.organizations.first(where: { ($0["id"] as? String) == identifier("organizationId") }) else { return nil }
            return ["GetOrganization": found]
        case "ListOrganizations":
            // Organizations are listed with the switched-off one, as a platform administrator sees them.
            return ["ListOrganizations": ["organizations": data.organizations, "meta": ["totalCount": data.organizations.count]]]
        case "ModifyOrganization":
            if let index = data.organizations.firstIndex(where: { ($0["id"] as? String) == identifier("organizationId") }),
                let name = (variables["organization"] as? [String: Any])?["name"] as? String
            {
                data.organizations[index]["name"] = name
            }
            return ["ModifyOrganization": ["organization": ["id": identifier("organizationId")]]]
        case "SetOrganizationActive":
            if let index = data.organizations.firstIndex(where: { ($0["id"] as? String) == identifier("organizationId") }) {
                data.organizations[index]["isActive"] = variables["isActive"] as? Bool ?? true
            }
            return ["SetOrganizationActive": ["organization": ["id": identifier("organizationId")]]]
        // The audit log.
        case "ListAuditEvents":
            let scope = DemoOptions.isStaff ? identifier("organizationId") : "organization01"
            var rows = data.auditEvents.filter { scope.isEmpty || ($0["organizationId"] as? String) == scope }
            for stage in options["aggregations"] as? [[String: Any]] ?? [] {
                if let filter = stage["filter"] as? [String: Any] { rows = rows.filter { passes($0, filter: filter) } }
            }
            rows.sort { ($0["createdAt"] as? String ?? "") > ($1["createdAt"] as? String ?? "") }
            let offset = options["after"] as? Int ?? 0
            let size = options["first"] as? Int ?? 50
            return ["ListAuditEvents": ["events": Array(rows.dropFirst(offset).prefix(size)), "meta": ["totalCount": rows.count]]]
        // Usage.
        case "ListProviderUsage":
            func row(_ number: Int, _ provider: String, _ model: String, _ organizationId: String, tokens: Int, requests: Int, ago: TimeInterval) -> [String: Any] {
                [
                    "id": "usage\(number)", "providerId": provider, "providerName": provider == "provider01" ? "Primary assistant" : "Fast answers", "providerModelName": model,
                    "organizationId": organizationId, "userId": "user01", "agentId": "agent01", "kind": "chat", "startedAt": stamp(ago), "promptTokens": tokens * 4 / 5,
                    "completionTokens": tokens / 5, "cacheCreationTokens": 0, "cacheReadTokens": 0, "totalTokens": tokens, "requestCount": requests,
                ]
            }
            return [
                "ListProviderUsage": [
                    row(1, "provider01", "model-large", "organization01", tokens: 1_840_000, requests: 412, ago: day),
                    row(2, "provider01", "model-large", "organization02", tokens: 960_000, requests: 188, ago: 2 * day),
                    row(3, "provider02", "model-small", "organization01", tokens: 410_000, requests: 905, ago: 3 * day),
                    row(4, "provider02", "model-small", "organization02", tokens: 120_000, requests: 260, ago: 4 * day),
                    row(5, "provider01", "model-large", "organization00", tokens: 75_000, requests: 31, ago: 5 * day),
                ]
            ]
        case "ListControllerUsageHistory":
            func row(_ id: String, _ comment: String, sent: Int, received: Int, up: Int) -> [String: Any] {
                ["controllerId": id, "controllerComment": comment, "startedAt": stamp(day), "sent": sent, "received": received, "up": up]
            }
            return [
                "ListControllerUsageHistory": [
                    row("controllerA", "Line A packing", sent: 4_800_000_000, received: 1_200_000_000, up: 6 * 86_400 + 5_000),
                    row("controllerB", "Dock robots", sent: 2_100_000_000, received: 640_000_000, up: 6 * 86_400 + 40_000),
                    row("controllerC", "Pallet cell", sent: 890_000_000, received: 210_000_000, up: 5 * 86_400),
                    row("controllerD", "Training bench", sent: 120_000_000, received: 30_000_000, up: 2 * 86_400),
                    row("controllerE", "Spare unit", sent: 2_000_000, received: 1_000_000, up: 3_600),
                ]
            ]
        // Billing.
        case "GetBillingSummary":
            let organizationId = identifier("organizationId").isEmpty ? "organization01" : identifier("organizationId")
            guard let found = data.billing[organizationId] else { return nil }
            return ["GetBillingSummary": found]
        case "GetBillingSubscription":
            let isFree = identifier("organizationId") == "organization02"
            if isFree { return ["GetSubscription": NSNull()] }
            return [
                "GetSubscription": [
                    "id": "subscription01", "planId": "plan02", "status": "active", "currentPeriodEndedAt": stamp(-18 * day), "isCancelAtPeriodEnd": false,
                    "plan": ["id": "plan02", "name": "team", "displayName": [["locale": "en", "text": "Team"]], "billingInterval": "month"],
                ]
            ]
        case "ListBillingTransactions":
            let offset = options["after"] as? Int ?? 0
            let size = options["first"] as? Int ?? 50
            return ["ListBillingTransactions": ["transactions": Array(data.transactions.dropFirst(offset).prefix(size)), "meta": ["totalCount": data.transactions.count]]]
        case "ListBillingPlans":
            func plan(_ id: String, _ name: String, _ title: String, sort: Int, fee: Int, active: Bool, isDefault: Bool = false, deleted: Bool = false, hours: Int, tokens: Int) -> [String: Any] {
                [
                    "id": id, "name": name, "displayName": [["locale": "en", "text": title]], "description": [["locale": "en", "text": "For \(title.lowercased()) use."]], "isActive": active,
                    "isDefault": isDefault, "sortOrder": sort, "billingInterval": "month", "includedAiTokens": tokens, "includedVirtualControllerHours": hours, "includedStorageGib": 300,
                    "maxConcurrentVirtualControllers": 4, "maxVirtualControllerHours": hours * 4, "isDocumentationIncluded": !isDefault, "deletedAt": deleted ? stamp(100 * day) : NSNull(),
                    "prices": [["currency": "usd", "baseFee": fee, "storageGibDay": 2]],
                ]
            }
            return [
                "ListPlans": [
                    "plans": [
                        plan("plan01", "free", "Free", sort: 1, fee: 0, active: true, isDefault: true, hours: 10, tokens: 500_000),
                        plan("plan02", "team", "Team", sort: 2, fee: 4_900, active: true, hours: 100, tokens: 5_000_000),
                        plan("plan03", "business", "Business", sort: 3, fee: 19_900, active: true, hours: 500, tokens: 25_000_000),
                        plan("plan04", "legacy", "Legacy", sort: 4, fee: 2_900, active: false, deleted: true, hours: 50, tokens: 2_000_000),
                    ], "meta": ["totalCount": 4],
                ]
            ]
        case "SetSpendingLimit":
            let organizationId = identifier("organizationId")
            if var found = data.billing[organizationId] {
                found["spendingLimit"] = variables["spendingLimit"] is NSNull ? NSNull() : (variables["spendingLimit"] as Any)
                if variables["clearWarning"] as? Bool == true { found["warning"] = NSNull() } else if let warning = variables["warning"] { found["warning"] = warning }
                data.billing[organizationId] = found
            }
            return ["SetSpendingLimit": ["id": organizationId]]
        case "SetUserSpendingLimit":
            let organizationId = identifier("organizationId")
            if var found = data.billing[organizationId] {
                found["userSpendingLimit"] = variables["spendingLimit"] is NSNull ? NSNull() : (variables["spendingLimit"] as Any)
                data.billing[organizationId] = found
            }
            return ["SetUserSpendingLimit": ["id": organizationId]]
        // Providers, agents and grants.
        case "ListAIProviders":
            return ["ListProviders": ["providers": data.providers, "meta": ["totalCount": data.providers.count]]]
        case "ListAIAgents":
            return ["ListAgents": ["agents": data.agents, "meta": ["totalCount": data.agents.count]]]
        case "CreateAIProvider":
            data.nextNumber += 1
            let newId = "provider\(data.nextNumber)"
            var provider = variables["provider"] as? [String: Any] ?? [:]
            provider["id"] = newId
            provider["apiKeyFingerprint"] = NSNull()
            data.providers.append(provider)
            return ["CreateProvider": ["provider": provider]]
        case "ModifyAIProvider":
            if let index = data.providers.firstIndex(where: { ($0["id"] as? String) == identifier("providerId") }) {
                for (key, value) in variables["provider"] as? [String: Any] ?? [:] { data.providers[index][key] = value }
            }
            return ["ModifyProvider": ["provider": ["id": identifier("providerId")]]]
        case "SetAIProviderKey":
            if let index = data.providers.firstIndex(where: { ($0["id"] as? String) == identifier("providerId") }) {
                data.providers[index]["apiKeyFingerprint"] = "…" + String(identifier("apiKey").suffix(4))
            }
            return ["SetProviderAPIKey": ["provider": ["id": identifier("providerId")]]]
        case "DeleteAIProvider":
            data.providers.removeAll { ($0["id"] as? String) == identifier("providerId") }
            return ["DeleteProvider": true]
        case "CreateAIAgent":
            data.nextNumber += 1
            let newId = "agent\(data.nextNumber)"
            var agent = variables["agent"] as? [String: Any] ?? [:]
            agent["id"] = newId
            data.agents.append(agent)
            return ["CreateAgent": ["agent": agent]]
        case "ModifyAIAgent":
            if let index = data.agents.firstIndex(where: { ($0["id"] as? String) == identifier("agentId") }) {
                for (key, value) in variables["agent"] as? [String: Any] ?? [:] { data.agents[index][key] = value }
            }
            return ["ModifyAgent": ["agent": ["id": identifier("agentId")]]]
        case "DeleteAIAgent":
            data.agents.removeAll { ($0["id"] as? String) == identifier("agentId") }
            return ["DeleteAgent": true]
        case "ListOrganizationProviders":
            let granted = data.providerGrants[identifier("organizationId"), default: []].sorted()
            return ["ListOrganizationProviders": granted.map { ["organizationId": identifier("organizationId"), "providerId": $0, "grantedAt": stamp(20 * day)] }]
        case "ListOrganizationAgents":
            let granted = data.agentGrants[identifier("organizationId"), default: []].sorted()
            return ["ListOrganizationAgents": granted.map { ["organizationId": identifier("organizationId"), "agentId": $0, "grantedAt": stamp(20 * day)] }]
        case "GrantOrganizationProvider":
            data.providerGrants[identifier("organizationId"), default: []].insert(identifier("providerId"))
            return ["GrantOrganizationProvider": ["grant": ["organizationId": identifier("organizationId"), "providerId": identifier("providerId")]]]
        case "RevokeOrganizationProvider":
            data.providerGrants[identifier("organizationId"), default: []].remove(identifier("providerId"))
            return ["RevokeOrganizationProvider": true]
        case "GrantOrganizationAgent":
            data.agentGrants[identifier("organizationId"), default: []].insert(identifier("agentId"))
            return ["GrantOrganizationAgent": ["grant": ["organizationId": identifier("organizationId"), "agentId": identifier("agentId")]]]
        case "RevokeOrganizationAgent":
            data.agentGrants[identifier("organizationId"), default: []].remove(identifier("agentId"))
            return ["RevokeOrganizationAgent": true]
        // Registrations.
        case "ListOrganizationRegistrations":
            let status = identifier("status")
            let rows = data.registrations.filter { status.isEmpty || ($0["status"] as? String) == status }
            return ["ListOrganizationRegistrations": ["organizationRegistrations": rows, "meta": ["totalCount": rows.count]]]
        case "RejectOrganizationRegistration":
            if let index = data.registrations.firstIndex(where: { ($0["id"] as? String) == identifier("registrationId") }) { data.registrations[index]["status"] = "rejected" }
            return ["RejectOrganizationRegistration": ["organizationRegistration": ["id": identifier("registrationId")]]]
        // Incident alerts.
        case "ListIncidentAlerts":
            return ["ListIncidentSubscriptions": ["incidentSubscriptions": data.alerts]]
        case "SubscribeToSiteIncidents":
            let siteId = identifier("siteId")
            let floor: Any = variables["minimumConfidence"] is NSNull ? NSNull() : (variables["minimumConfidence"] as Any)
            if let index = data.alerts.firstIndex(where: { ($0["siteId"] as? String) == siteId }) {
                data.alerts[index]["minimumConfidence"] = floor
                data.alerts[index]["isEnabled"] = variables["isEnabled"] as? Bool ?? true
            } else {
                data.nextNumber += 1
                data.alerts.append(["id": "alert\(data.nextNumber)", "siteId": siteId, "isEnabled": variables["isEnabled"] as? Bool ?? true, "minimumConfidence": floor, "createdAt": stamp(0)])
            }
            return ["SubscribeToSiteIncidents": ["incidentSubscription": ["siteId": siteId]]]
        case "UnsubscribeFromSiteIncidents":
            data.alerts.removeAll { ($0["siteId"] as? String) == identifier("siteId") }
            return ["UnsubscribeFromSiteIncidents": ["siteId": identifier("siteId")]]
        default:
            return nil
        }
    }
}
