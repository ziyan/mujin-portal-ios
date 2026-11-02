import PortalKit
import SwiftUI

/// BillingText writes the words of billing: what a metered dimension is called, and a period.
private enum BillingText {
    /// "virtual_controller_hours" is "Virtual controller hours".
    static func dimension(_ name: String?) -> String {
        let words = (name ?? "").split(separator: "_").joined(separator: " ")
        return words.isEmpty ? String(localized: "Usage") : words.prefix(1).uppercased() + words.dropFirst()
    }

    static func period(_ billing: OrganizationBilling) -> String? {
        guard let start = billing.periodStartDate, let end = billing.periodEndDate else { return nil }
        return "\(start.formatted(.dateTime.month().day())) to \(end.formatted(.dateTime.month().day().year()))"
    }

    static func status(_ name: String?) -> String? {
        switch name {
        case "free": return String(localized: "Free plan")
        case "active": return String(localized: "Active")
        case "trialing": return String(localized: "Trial")
        case "past_due": return String(localized: "Payment overdue")
        case "unpaid": return String(localized: "Unpaid")
        case "canceled": return String(localized: "Canceled")
        case "incomplete": return String(localized: "Incomplete")
        default: return (name ?? "").isEmpty ? nil : name
        }
    }
}

struct BillingSnapshot: Sendable {
    let billing: OrganizationBilling?
    let subscription: OrganizationSubscription?
}

/// BillingView is an organization's billing: its plan, what it spent this period, its balance and its spending limits. What needs a
/// card or Stripe's own pages (adding funds, changing the plan, the payment method) opens on the web.
struct BillingView: View {
    let organizationId: String

    var body: some View {
        PlatformPage(
            title: "Billing", failureTitle: "Could not load billing",
            load: { [organizationId] (connection: Connection) -> BillingSnapshot in
                async let billing = connection.billingSummary(organizationId: organizationId)
                async let subscription = connection.billingSubscription(organizationId: organizationId)
                return BillingSnapshot(billing: try await billing, subscription: try? await subscription)
            }
        ) { snapshot, reload in
            BillingList(organizationId: organizationId, snapshot: snapshot, reload: reload)
        }
    }
}

private enum SpendingLimitKind: Identifiable {
    case organization
    case person
    var id: Int { self == .organization ? 0 : 1 }
}

private struct BillingList: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String
    let snapshot: BillingSnapshot
    let reload: PageReload

    @State private var editing: SpendingLimitKind?

    var body: some View {
        let access = session.platformAccess
        let canManage = access.canManageBilling(of: organizationId)
        List {
            PortalRows {
                if let billing = snapshot.billing {
                    summarySections(billing, canManage: canManage)
                } else {
                    Section { Text("This organization has no billing yet.").foregroundStyle(Color.secondary) }
                }
                Section {
                    PlatformLink(destination: .transactions(organizationId: organizationId), title: "Balance history", symbol: "list.bullet.rectangle")
                }
                if canManage {
                    Section {
                        PlatformWebRow(title: "Add funds, change plan or payment", path: "/organization/\(organizationId)/billing")
                    } footer: {
                        Text("Paying and changing the plan happen on Stripe's pages, which open in Portal on the web, signed in as you.")
                    }
                }
            }
        }
        .portalList()
        .refreshable { await reload() }
        .sheet(item: $editing) { kind in
            if let billing = snapshot.billing {
                SpendingLimitSheet(
                    currency: billing.currencyCode, initialLimit: kind == .organization ? billing.spendingLimit : billing.userSpendingLimit,
                    initialWarning: kind == .organization ? billing.warning : nil, asksForWarning: kind == .organization,
                    title: kind == .organization ? "Spending limit" : "Limit per person"
                ) { limit, warning in
                    let connection = appModel.connection(for: session.account)
                    if kind == .organization {
                        try await connection.setSpendingLimit(organizationId: organizationId, limit: limit, warning: warning, clearWarning: warning == nil)
                    } else {
                        try await connection.setUserSpendingLimit(organizationId: organizationId, limit: limit)
                    }
                    await reload()
                }
            }
        }
    }

    @ViewBuilder
    private func summarySections(_ billing: OrganizationBilling, canManage: Bool) -> some View {
        Section {
            LabeledContent("Plan") { Text(planName(billing)).foregroundStyle(Color.secondary) }
            if let status = BillingText.status(billing.subscriptionStatus) {
                LabeledContent("Status") { Text(status).foregroundStyle(Color.secondary) }
            }
            if let message = billing.blockMessage {
                Label(localizedWords(message), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.statusWarning)
            }
        }
        Section {
            if let period = BillingText.period(billing) {
                LabeledContent("Period") { Text(period).foregroundStyle(Color.secondary) }
            }
            LabeledContent("Spent this period") { Text(billing.money(billing.total)).foregroundStyle(Color.secondary).monospacedDigit() }
            LabeledContent("Balance") { Text(billing.money(billing.balance)).foregroundStyle(Color.secondary).monospacedDigit() }
            LabeledContent("Available") { Text(billing.money(billing.availableBalance)).foregroundStyle(Color.secondary).monospacedDigit() }
        } header: {
            Text("This period")
        }
        Section {
            LabeledContent("Limit") { Text(limitText(billing.spendingLimit, billing)).foregroundStyle(Color.secondary).monospacedDigit() }
            if billing.spendingLimit != nil {
                LabeledContent("Used") { Text("\(billing.spendingFractionPercent ?? 0)%").foregroundStyle(Color.secondary).monospacedDigit() }
            }
            if let warning = billing.warning {
                LabeledContent("Warns at") { Text(billing.money(warning)).foregroundStyle(Color.secondary).monospacedDigit() }
            }
            if canManage {
                changeButton("Change spending limit", .organization)
            }
        } header: {
            Text("Spending limit")
        } footer: {
            Text("Usage past the limit is blocked until the next period or the limit is raised.")
        }
        Section {
            LabeledContent("Limit") { Text(limitText(billing.userSpendingLimit, billing)).foregroundStyle(Color.secondary).monospacedDigit() }
            LabeledContent("Your spend") { Text(billing.money(billing.userSpend)).foregroundStyle(Color.secondary).monospacedDigit() }
            if canManage {
                changeButton("Change limit per person", .person)
            }
        } header: {
            Text("Limit per person")
        }
        if let items = billing.lineItems?.filter({ ($0.usedQuantity ?? 0) > 0 || ($0.cost ?? 0) > 0 }), !items.isEmpty {
            Section("Usage this period") {
                ForEach(items, id: \.dimension) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BillingText.dimension(item.dimension))
                                .foregroundStyle(Color.primary)
                            Text("\(UsageFormat.tokens(item.usedQuantity ?? 0)) used of \(UsageFormat.tokens(item.includedQuantity ?? 0)) included")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength: 8)
                        if (item.cost ?? 0) > 0 {
                            Text(billing.money(item.cost))
                                .foregroundStyle(Color.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func changeButton(_ title: LocalizedStringKey, _ kind: SpendingLimitKind) -> some View {
        Button {
            editing = kind
        } label: {
            Label(title, systemImage: "pencil")
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func planName(_ billing: OrganizationBilling) -> String {
        if billing.onDefaultPlan == true { return String(localized: "Free") }
        let name = snapshot.subscription?.plan.flatMap { LocalizedText.pick($0.displayName, languageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? $0.name }
        return name ?? String(localized: "Unknown plan")
    }

    private func limitText(_ limit: Int?, _ billing: OrganizationBilling) -> String {
        limit.map { billing.money($0) } ?? String(localized: "None")
    }
}

/// SpendingLimitSheet asks for an amount, and for the amount that warns before it, in the organization's currency. Empty means none.
private struct SpendingLimitSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let currency: String
    let initialLimit: Int?
    let initialWarning: Int?
    let asksForWarning: Bool
    let title: LocalizedStringKey
    let onSubmit: (Int?, Int?) async throws -> Void

    @State private var limitText = ""
    @State private var warningText = ""
    @State private var actions = ActionState()

    private var limit: Int? { Money.minorUnits(from: limitText, currency: currency) }
    private var warning: Int? { Money.minorUnits(from: warningText, currency: currency) }
    private var isLimitValid: Bool { limitText.trimmingCharacters(in: .whitespaces).isEmpty || limit != nil }
    private var isWarningValid: Bool { warningText.trimmingCharacters(in: .whitespaces).isEmpty || warning != nil }
    private var isChanged: Bool { limit != initialLimit || (asksForWarning && warning != initialWarning) }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section {
                        TextField("No limit", text: $limitText)
                            .keyboardType(.decimalPad)
                    } header: {
                        Text("Amount in \(currency.uppercased())")
                    } footer: {
                        Text("Leave empty for no limit.")
                    }
                    if asksForWarning {
                        Section {
                            TextField("No warning", text: $warningText)
                                .keyboardType(.decimalPad)
                        } header: {
                            Text("Warn at")
                        } footer: {
                            Text("An administrator is told when spending reaches this amount.")
                        }
                    }
                }
            }
            .portalList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await submit() } }
                        .disabled(!isLimitValid || !isWarningValid || !isChanged || actions.isWorking)
                }
            }
            .onAppear {
                limitText = initialLimit.map { Money.editableText(minor: $0, currency: currency) } ?? ""
                warningText = initialWarning.map { Money.editableText(minor: $0, currency: currency) } ?? ""
            }
            .failureAlert(actions)
        }
    }

    private func submit() async {
        let newLimit = limit
        let newWarning = asksForWarning ? warning : nil
        let submit = onSubmit
        if await actions.run(appModel: appModel, session: session, { try await submit(newLimit, newWarning) }) { dismiss() }
    }
}

/// BillingTransactionsView is the history of an organization's balance: charges, top-ups and adjustments, a page at a time.
struct BillingTransactionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String

    @State private var phase = LoadPhase.loading
    @State private var transactions: [BillingTransaction] = []
    @State private var totalCount = 0
    @State private var isLoadingMore = false
    @State private var actions = ActionState()

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load the history", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await reload() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Balance history")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .failureAlert(actions)
    }

    private var list: some View {
        List {
            PortalRows {
                if transactions.isEmpty {
                    Section { Text("Nothing has moved on the balance yet.").foregroundStyle(Color.secondary) }
                } else {
                    Section {
                        ForEach(transactions) { transaction in row(transaction) }
                    } footer: {
                        Text("\(transactions.count) of \(totalCount) shown")
                    }
                }
                if transactions.count < totalCount {
                    Section {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack {
                                Text("Load more")
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if isLoadingMore { ProgressView() }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingMore)
                    }
                }
            }
        }
        .portalList()
        .refreshable { await reload() }
    }

    private func row(_ transaction: BillingTransaction) -> some View {
        let currency = transaction.currency ?? "usd"
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizedWords(transaction.kindName))
                    .foregroundStyle(Color.primary)
                if let description = transaction.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                if let date = PortalDate.parse(transaction.createdAt) {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(minor: transaction.amount ?? 0, currency: currency))
                    .foregroundStyle(Color.primary)
                    .monospacedDigit()
                if let balance = transaction.balanceAfter {
                    Text("Balance \(Money.format(minor: balance, currency: currency))")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func reload() async {
        do {
            let page = try await appModel.connection(for: session.account).billingTransactions(organizationId: organizationId)
            transactions = page.transactions
            totalCount = page.totalCount
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) } else { actions.errorMessage = error.userMessage }
        }
    }

    private func loadMore() async {
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await appModel.connection(for: session.account).billingTransactions(organizationId: organizationId, offset: transactions.count)
            let known = Set(transactions.map(\.id))
            transactions += page.transactions.filter { !known.contains($0.id) }
            totalCount = page.totalCount
        } catch {
            appModel.handle(error, account: session.account)
            actions.errorMessage = error.userMessage
        }
    }
}

/// PlansView is the catalog of plans, the ones on offer first.
struct PlansView: View {
    var body: some View {
        PlatformPage(
            title: "Plans", failureTitle: "Could not load plans",
            load: { try await $0.plans(includeDeleted: true) }
        ) { plans, reload in
            List {
                PortalRows {
                    Section {
                        ForEach(plans) { plan in
                            NavigationLink(value: MoreDestination.platform(.plan(plan))) { PlanRow(plan: plan) }
                        }
                    }
                    if plans.isEmpty {
                        Section { Text("There are no plans.").foregroundStyle(Color.secondary) }
                    }
                    Section {
                        PlatformWebRow(title: "Edit plans on the web", path: "/settings/plans")
                    } footer: {
                        Text("Prices are set per currency and synced to Stripe, which happens in Portal on the web.")
                    }
                }
            }
            .portalList()
            .refreshable { await reload() }
        }
    }
}

private struct PlanRow: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.title())
                .foregroundStyle(Color.primary)
            if let fee = plan.baseFee(currency: nil) {
                Text("\(Money.format(minor: fee.amount, currency: fee.currency)) per \(plan.billingInterval ?? "month")")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if plan.isDeleted {
                Text("Retired")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            } else if plan.isActive != true {
                Text("Not on offer")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            } else if plan.isDefault == true {
                Text("Given to new organizations")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// PlanView is one plan: what it costs and what it includes.
struct PlanView: View {
    let plan: Plan

    var body: some View {
        List {
            PortalRows {
                Section {
                    if let summary = plan.summary(), !summary.isEmpty {
                        Text(summary).foregroundStyle(Color.primary)
                    }
                    ForEach(plan.prices ?? [], id: \.currency) { price in
                        if let fee = price.baseFee, let currency = price.currency {
                            LabeledContent("Base fee in \(currency.uppercased())") {
                                Text("\(Money.format(minor: fee, currency: currency)) per \(plan.billingInterval ?? "month")").foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                Section("Included") {
                    fact("AI tokens", plan.includedAiTokens.map { UsageFormat.tokens($0) })
                    fact("Virtual controller hours", plan.includedVirtualControllerHours.map(String.init))
                    fact("Storage (GiB)", plan.includedStorageGib.map(String.init))
                    fact("Documentation", plan.isDocumentationIncluded == true ? String(localized: "Included") : String(localized: "Not included"))
                }
                Section("Limits") {
                    fact("Virtual controllers at once", plan.maxConcurrentVirtualControllers.map(String.init))
                    fact("Virtual controller hours", plan.maxVirtualControllerHours.map(String.init))
                }
            }
        }
        .portalList()
        .navigationTitle(plan.title())
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func fact(_ label: LocalizedStringKey, _ value: String?) -> some View {
        LabeledContent(label) {
            Text(value ?? String(localized: "No limit")).foregroundStyle(Color.secondary).monospacedDigit()
        }
    }
}
