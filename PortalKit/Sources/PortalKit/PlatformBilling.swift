import Foundation

/// Money is how amounts in minor units (cents, or whole yen) are read and written.
public enum Money {
    /// Currencies with no minor unit. The web asks the system; this list is what the system knows of the common ones.
    static let zeroDecimalCurrencies: Set<String> = ["jpy", "krw", "vnd", "clp", "isk", "ugx", "xaf", "xof", "xpf", "pyg", "rwf"]
    static let threeDecimalCurrencies: Set<String> = ["bhd", "jod", "kwd", "omr", "tnd"]

    /// How many minor units make one major unit.
    public static func divisor(currency: String) -> Int {
        let code = currency.lowercased()
        if zeroDecimalCurrencies.contains(code) { return 1 }
        if threeDecimalCurrencies.contains(code) { return 1000 }
        return 100
    }

    /// "$12.50" for 1250 US cents, in the person's language. The code is the ISO currency code, in any case.
    public static func format(minor: Int, currency: String, locale: Locale = .current) -> String {
        let code = (currency.isEmpty ? "usd" : currency).uppercased()
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code
        let scale = divisor(currency: currency)
        let digits = scale == 1 ? 0 : (scale == 1000 ? 3 : 2)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: Double(minor) / Double(scale))) ?? "\(minor) \(code)"
    }

    /// The minor units a typed amount stands for: "12.5" is 1250 US cents. Nil for text that is not an amount or is negative.
    public static func minorUnits(from text: String, currency: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0, value.isFinite else { return nil }
        return Int((value * Double(divisor(currency: currency))).rounded())
    }

    /// The amount as a person types it: 1250 US cents is "12.5", 500 yen is "500".
    public static func editableText(minor: Int, currency: String) -> String {
        let divisor = divisor(currency: currency)
        guard divisor > 1 else { return String(minor) }
        let value = Double(minor) / Double(divisor)
        return value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// LocalizedText picks the wording for the person's language from the translations a plan carries.
public struct LocalizedText: Codable, Equatable, Hashable, Sendable {
    public let locale: String?
    public let text: String?

    /// The translation in the language, or in English, or the first one that has words; nil when none does.
    public static func pick(_ translations: [LocalizedText]?, languageCode: String) -> String? {
        let usable = (translations ?? []).filter { !($0.text ?? "").isEmpty }
        func language(_ translation: LocalizedText) -> String { String((translation.locale ?? "").lowercased().prefix(2)) }
        return usable.first { language($0) == languageCode.lowercased() }?.text ?? usable.first { language($0) == "en" }?.text ?? usable.first?.text
    }
}

public struct AITokenLimitStatus: Codable, Equatable, Hashable, Sendable {
    public let scope: String?
    public let interval: String?
    public let limit: Int?
    public let used: Int?
}

public struct BillingLineItem: Codable, Equatable, Hashable, Sendable {
    public let dimension: String?
    public let includedQuantity: Int?
    public let usedQuantity: Int?
    public let overageQuantity: Int?
    public let cost: Int?
}

/// OrganizationBilling is an organization's billing for the current period.
public struct OrganizationBilling: Codable, Equatable, Hashable, Sendable {
    public let organizationId: String?
    public let planId: String?
    public let currency: String?
    public let periodStartMillis: Int?
    public let periodEndMillis: Int?
    public let total: Int?
    public let overage: Int?
    public let balance: Int?
    public let availableBalance: Int?
    public let spendingLimit: Int?
    public let warning: Int?
    public let spendingFractionPercent: Int?
    public let isAutoReloadEnabled: Bool?
    public let autoReloadThreshold: Int?
    public let autoReloadAmount: Int?
    public let blocked: Bool?
    public let blockReason: String?
    public let userSpendingLimit: Int?
    public let userSpend: Int?
    public let subscriptionStatus: String?
    public let enforcementActive: Bool?
    public let onDefaultPlan: Bool?
    public let aiTokenLimits: [AITokenLimitStatus]?
    public let lineItems: [BillingLineItem]?

    public var currencyCode: String { (currency ?? "").isEmpty ? "usd" : currency! }
    public var periodStartDate: Date? { periodStartMillis.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
    public var periodEndDate: Date? { periodEndMillis.map { Date(timeIntervalSince1970: Double($0) / 1000) } }

    public func money(_ minor: Int?, locale: Locale = .current) -> String { Money.format(minor: minor ?? 0, currency: currencyCode, locale: locale) }

    /// Why the organization is blocked, in words, or nil when it is not.
    public var blockMessage: String? {
        guard blocked == true else { return nil }
        switch blockReason {
        case "spending_limit": return "The spending limit has been reached."
        case "balance": return "The prepaid balance has run out."
        case "subscription_inactive": return "The subscription is not paid up."
        default: return "Usage is blocked."
        }
    }
}

/// SubscriptionPlanSummary is the plan a subscription is on.
public struct SubscriptionPlanSummary: Codable, Equatable, Hashable, Sendable {
    public let id: String?
    public let name: String?
    public let displayName: [LocalizedText]?
    public let billingInterval: String?
}

/// OrganizationSubscription is the paid plan an organization is on. An organization on the free plan has none.
public struct OrganizationSubscription: Codable, Equatable, Hashable, Sendable {
    public let id: String?
    public let planId: String?
    public let status: String?
    public let currentPeriodEndedAt: String?
    public let isCancelAtPeriodEnd: Bool?
    public let plan: SubscriptionPlanSummary?
}

public struct BillingTransactionLine: Codable, Equatable, Hashable, Sendable {
    public let dimension: String?
    public let quantity: Int?
    public let cost: Int?
}

/// BillingTransaction is one movement on an organization's prepaid balance.
public struct BillingTransaction: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: String?
    /// `charge`, `top_up`, `auto_reload` or `adjustment`.
    public let kind: String?
    public let amount: Int?
    public let balanceAfter: Int?
    public let currency: String?
    public let description: String?
    public let periodStartedAt: String?
    public let stripeReceiptUrl: String?
    public let lineItems: [BillingTransactionLine]?

    public var kindName: String {
        switch kind {
        case "charge": return "Charge"
        case "top_up": return "Top-up"
        case "auto_reload": return "Automatic top-up"
        case "adjustment": return "Adjustment"
        default: return "Transaction"
        }
    }
}

/// PlanPrice is what a plan costs in one currency.
public struct PlanPrice: Codable, Equatable, Hashable, Sendable {
    public let currency: String?
    public let baseFee: Int?
    public let storageGibDay: Int?
}

/// Plan is a plan of the catalog.
public struct Plan: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let displayName: [LocalizedText]?
    public let description: [LocalizedText]?
    public let isActive: Bool?
    public let isDefault: Bool?
    public let sortOrder: Int?
    public let billingInterval: String?
    public let includedAiTokens: Int?
    public let includedVirtualControllerHours: Int?
    public let includedStorageGib: Int?
    public let maxConcurrentVirtualControllers: Int?
    public let maxVirtualControllerHours: Int?
    public let isDocumentationIncluded: Bool?
    public let deletedAt: String?
    public let prices: [PlanPrice]?

    public func title(languageCode: String = "en") -> String {
        LocalizedText.pick(displayName, languageCode: languageCode) ?? ((name ?? "").isEmpty ? id : name!)
    }

    public func summary(languageCode: String = "en") -> String? { LocalizedText.pick(description, languageCode: languageCode) }
    public var isDeleted: Bool { !(deletedAt ?? "").isEmpty }

    /// The base fee in a currency, or in the first one the plan lists.
    public func baseFee(currency: String?) -> (amount: Int, currency: String)? {
        let list = prices ?? []
        let match = list.first { ($0.currency ?? "").lowercased() == (currency ?? "").lowercased() } ?? list.first
        guard let match, let amount = match.baseFee, let code = match.currency else { return nil }
        return (amount, code)
    }
}

public enum Plans {
    /// Plans the catalog still offers first, in the catalog's order, then the retired ones.
    public static func ordered(_ plans: [Plan]) -> [Plan] {
        plans.sorted { left, right in
            if left.isDeleted != right.isDeleted { return !left.isDeleted }
            if (left.isActive == true) != (right.isActive == true) { return left.isActive == true }
            if (left.sortOrder ?? 0) != (right.sortOrder ?? 0) { return (left.sortOrder ?? 0) < (right.sortOrder ?? 0) }
            return left.title().localizedCaseInsensitiveCompare(right.title()) == .orderedAscending
        }
    }
}

extension Documents {
    public static let getBillingSummary = """
        query GetBillingSummary($organizationId: String) {
          GetBillingSummary(organizationId: $organizationId) {
            organizationId planId currency periodStartMillis periodEndMillis total overage balance availableBalance spendingLimit warning
            spendingFractionPercent isAutoReloadEnabled autoReloadThreshold autoReloadAmount blocked blockReason userSpendingLimit userSpend
            subscriptionStatus enforcementActive onDefaultPlan
            aiTokenLimits { scope interval limit used }
            lineItems { dimension includedQuantity usedQuantity overageQuantity cost }
          }
        }
        """

    public static let getBillingSubscription = """
        query GetBillingSubscription($organizationId: String) {
          GetSubscription(organizationId: $organizationId) {
            id planId status currentPeriodEndedAt isCancelAtPeriodEnd plan { id name displayName { locale text } billingInterval }
          }
        }
        """

    public static let listBillingTransactions = """
        query ListBillingTransactions($organizationId: String, $options: ListOptionsInput) {
          ListBillingTransactions(organizationId: $organizationId, options: $options) {
            transactions {
              id createdAt kind amount balanceAfter currency description periodStartedAt stripeReceiptUrl lineItems { dimension quantity cost }
            }
            meta { totalCount }
          }
        }
        """

    public static let listBillingPlans = """
        query ListBillingPlans($activeOnly: Boolean, $includeDeleted: Boolean) {
          ListPlans(activeOnly: $activeOnly, includeDeleted: $includeDeleted) {
            plans {
              id name displayName { locale text } description { locale text } isActive isDefault sortOrder billingInterval includedAiTokens
              includedVirtualControllerHours includedStorageGib maxConcurrentVirtualControllers maxVirtualControllerHours isDocumentationIncluded
              deletedAt prices { currency baseFee storageGibDay }
            }
            meta { totalCount }
          }
        }
        """

    public static let setSpendingLimit = """
        mutation SetSpendingLimit($organizationId: String, $spendingLimit: Int64, $warning: Int64, $clearWarning: Boolean) {
          SetSpendingLimit(organizationId: $organizationId, spendingLimit: $spendingLimit, warning: $warning, clearWarning: $clearWarning) {
            id spendingLimit spendingWarning
          }
        }
        """

    public static let setUserSpendingLimit = """
        mutation SetUserSpendingLimit($organizationId: String, $spendingLimit: Int64) {
          SetUserSpendingLimit(organizationId: $organizationId, spendingLimit: $spendingLimit) { id userSpendingLimit }
        }
        """

    static var billingDocuments: [String] {
        [getBillingSummary, getBillingSubscription, listBillingTransactions, listBillingPlans, setSpendingLimit, setUserSpendingLimit]
    }
}

extension Connection {
    public static let billingTransactionPageSize = 50

    public func billingSummary(organizationId: String) async throws -> OrganizationBilling? {
        struct Answer: Decodable, Sendable { let GetBillingSummary: OrganizationBilling? }
        return try await execute(Documents.getBillingSummary, variables: ["organizationId": .string(organizationId)], as: Answer.self).GetBillingSummary
    }

    public func billingSubscription(organizationId: String) async throws -> OrganizationSubscription? {
        struct Answer: Decodable, Sendable { let GetSubscription: OrganizationSubscription? }
        return try await execute(Documents.getBillingSubscription, variables: ["organizationId": .string(organizationId)], as: Answer.self).GetSubscription
    }

    public func billingTransactions(organizationId: String, offset: Int = 0) async throws -> (transactions: [BillingTransaction], totalCount: Int) {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let transactions: [BillingTransaction?]?
                let meta: Meta?
            }
            let ListBillingTransactions: List?
        }
        let variables: [String: JSONValue] = [
            "organizationId": .string(organizationId),
            "options": .object(["first": .number(Double(Self.billingTransactionPageSize)), "after": .number(Double(offset))]),
        ]
        let list = try await execute(Documents.listBillingTransactions, variables: variables, as: Answer.self).ListBillingTransactions
        let rows = (list?.transactions ?? []).compactMap { $0 }
        return (rows, list?.meta?.totalCount ?? rows.count)
    }

    /// The plans of the catalog. Retired plans come too when asked.
    public func plans(includeDeleted: Bool = false) async throws -> [Plan] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let plans: [Plan?]? }
            let ListPlans: List?
        }
        var variables: [String: JSONValue] = [:]
        if includeDeleted { variables["includeDeleted"] = .bool(true) }
        return Plans.ordered(try await execute(Documents.listBillingPlans, variables: variables, as: Answer.self).ListPlans?.plans?.compactMap { $0 } ?? [])
    }

    /// Sets the organization's spending limit, in minor units; nil removes the limit. `warning` is the amount that raises a warning, and
    /// `clearWarning` removes it.
    public func setSpendingLimit(organizationId: String, limit: Int?, warning: Int?, clearWarning: Bool) async throws {
        var variables: [String: JSONValue] = [
            "organizationId": .string(organizationId), "spendingLimit": limit.map { .number(Double($0)) } ?? .null, "clearWarning": .bool(clearWarning),
        ]
        if let warning, !clearWarning { variables["warning"] = .number(Double(warning)) }
        _ = try await execute(Documents.setSpendingLimit, variables: variables, as: JSONValue.self)
    }

    /// Sets what one person may spend in a period, in minor units; nil removes the limit.
    public func setUserSpendingLimit(organizationId: String, limit: Int?) async throws {
        _ = try await execute(
            Documents.setUserSpendingLimit,
            variables: ["organizationId": .string(organizationId), "spendingLimit": limit.map { .number(Double($0)) } ?? .null], as: JSONValue.self)
    }
}
