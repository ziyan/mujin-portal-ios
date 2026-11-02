import PortalKit
import SwiftUI

/// UsageWindowPicker chooses how far back usage is read.
private struct UsageWindowPicker: View {
    @Binding var window: UsageWindow

    var body: some View {
        Picker("Period", selection: $window) {
            Text("24 hours").tag(UsageWindow.lastDay)
            Text("7 days").tag(UsageWindow.lastWeek)
            Text("30 days").tag(UsageWindow.lastMonth)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("usagePeriod")
    }
}

/// UsageTotal is one big number with its name under it.
private struct UsageTotal: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// ProviderUsageView is the AI usage of the whole platform over a period: how many tokens and requests, by model and by organization.
struct ProviderUsageView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var window = UsageWindow.lastWeek
    @State private var phase = LoadPhase.loading
    @State private var summary: ProviderUsageSummary?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load usage", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if let summary { list(summary) }
            }
        }
        .navigationTitle("AI usage")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: window) { await load() }
    }

    private func list(_ summary: ProviderUsageSummary) -> some View {
        List {
            PortalRows {
                Section { UsageWindowPicker(window: $window) }
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        UsageTotal(value: UsageFormat.tokens(summary.tokenCount), label: "Tokens")
                        UsageTotal(value: UsageFormat.tokens(summary.requestCount), label: "Requests")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        UsageTotal(value: UsageFormat.tokens(summary.promptTokenCount), label: "Prompt tokens")
                        UsageTotal(value: UsageFormat.tokens(summary.completionTokenCount), label: "Completion tokens")
                    }
                }
                if summary.tokenCount == 0 && summary.requestCount == 0 {
                    Section { Text("No usage in this period.").foregroundStyle(Color.secondary) }
                }
                if !summary.byModel.isEmpty {
                    Section("By model") { ForEach(summary.byModel) { line in lineRow(line) } }
                }
                if summary.byOrganization.count > 1 {
                    Section("By organization") { ForEach(summary.byOrganization) { line in lineRow(line) } }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func lineRow(_ line: UsageLine) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.label)
                    .foregroundStyle(Color.primary)
                Text("^[\(line.requestCount) request](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            Text(UsageFormat.tokens(line.tokenCount))
                .foregroundStyle(Color.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            let rows = try await appModel.connection(for: session.account).providerUsage(window: window)
            summary = ProviderUsageSummary(rows: rows, organizationNames: session.organizationNames)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}

/// ControllerUsageView is the traffic and uptime of every controller over a period, the busiest first.
struct ControllerUsageView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    private static let shownLimit = 100

    @State private var window = UsageWindow.lastWeek
    @State private var phase = LoadPhase.loading
    @State private var lines: [ControllerUsageLine] = []

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load usage", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Controller usage")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: window) { await load() }
    }

    private var list: some View {
        List {
            PortalRows {
                Section { UsageWindowPicker(window: $window) }
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        UsageTotal(value: UsageFormat.bytes(lines.reduce(0) { $0 + $1.sentBytes }), label: "Sent")
                        UsageTotal(value: UsageFormat.bytes(lines.reduce(0) { $0 + $1.receivedBytes }), label: "Received")
                    }
                }
                if lines.isEmpty {
                    Section { Text("No traffic in this period.").foregroundStyle(Color.secondary) }
                } else {
                    Section {
                        ForEach(lines.prefix(Self.shownLimit)) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.label)
                                    .foregroundStyle(Color.primary)
                                Text("\(UsageFormat.bytes(line.totalBytes)), connected \(UsageFormat.duration(seconds: line.connectedSeconds))")
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("Busiest controllers")
                    } footer: {
                        if lines.count > Self.shownLimit { Text("The \(Self.shownLimit) busiest of \(lines.count) controllers.") }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let rows = try await appModel.connection(for: session.account).controllerUsage(window: window)
            lines = ControllerUsageSummary.lines(rows)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }
}
