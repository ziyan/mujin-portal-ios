import PortalKit
import SwiftUI

/// DreamsView is the assistant tidying its memory in the background: links it
/// proposes between pages for the person to accept or decline, and, for an
/// organization's administrators, the setting and the runs.
struct DreamsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var setting: AgentDreamSetting?
    @State private var runs: [MemoryDream] = []
    @State private var phase = LoadPhase.loading
    @State private var budgetShare = 20.0
    @State private var tokenCap = 0
    @State private var errorText: String?
    @State private var noticeText: String?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Tidying up")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var canManage: Bool { setting?.canManageOrganization == true }

    private var list: some View {
        List {
            PortalRows {
                if let setting {
                    Section("Status") {
                        LabeledContent("Tidies up in the background") { Text(setting.isDreamEnabled == true ? LocalizedStringKey("On") : LocalizedStringKey("Off")) }
                        if let last = setting.lastDreamEnd { LabeledContent("Last run") { Text(last, format: .relative(presentation: .named)) } }
                        // The numbers are for the people who pay for it.
                        if canManage, let allowance = setting.todayBudgetTokenCount, allowance > 0 {
                            LabeledContent("Today") { Text("\(setting.todaySpentTokenCount ?? 0) of \(allowance) tokens") }
                        }
                    }
                    if canManage { settingsSection(setting) }
                }
                if !runs.isEmpty {
                    Section("Recent runs") {
                        ForEach(runs) { run in
                            DisclosureGroup {
                                ForEach(run.phaseReports ?? []) { report in
                                    HStack {
                                        Text((report.dreamPhase ?? "").capitalized)
                                        Spacer()
                                        Text("\(report.doneItemCount ?? 0) · \(report.phaseOutcome ?? "")").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                if let gaps = run.gapQuestions, !gaps.isEmpty {
                                    ForEach(gaps, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                                }
                                if let error = run.errorMessage, !error.isEmpty { Text(error).font(.footnote).foregroundStyle(Color.statusError) }
                            } label: {
                                HStack {
                                    if let start = run.start { Text(start, format: .relative(presentation: .named)) }
                                    Spacer()
                                    Text((run.dreamStatus ?? "").replacingOccurrences(of: "_", with: " ")).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let noticeText { Section { Text(noticeText).foregroundStyle(.secondary) } }
                if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    @ViewBuilder
    private func settingsSection(_ setting: AgentDreamSetting) -> some View {
        Section("Organization setting") {
            Toggle("Tidy up in the background", isOn: Binding(get: { setting.isDreamEnabled == true }, set: { value in Task { await save(isEnabled: value) } }))
            VStack(alignment: .leading) {
                Text("Share of the daily allowance: \(Int(budgetShare))%")
                Slider(value: $budgetShare, in: 1...100, step: 1) { isEditing in
                    if !isEditing { Task { await save(isEnabled: setting.isDreamEnabled == true) } }
                }
            }
            Stepper("Token cap per run: \(tokenCap)", value: $tokenCap, in: 0...5_000_000, step: 10_000) { isEditing in
                if !isEditing { Task { await save(isEnabled: setting.isDreamEnabled == true) } }
            }
            Button("Tidy up now") { Task { await dreamNow() } }
                .disabled(setting.isDreamEnabled != true || setting.isDreaming == true)
        }
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        do {
            let loaded = try await connection.dreamSetting()
            setting = loaded
            budgetShare = Double(loaded.dreamBudgetSharePercent ?? 20)
            tokenCap = loaded.dreamTokenCap ?? 0
            phase = .loaded
            // Only an organization's administrators may read the runs.
            runs = loaded.canManageOrganization == true ? ((try? await connection.memoryDreams()) ?? []) : []
        } catch {
            appModel.handle(error, account: session.account)
            if setting == nil { phase = .failed(error.userMessage) }
        }
    }

    private func save(isEnabled: Bool) async {
        do {
            setting = try await appModel.connection(for: session.account).setDreamSetting(isEnabled: isEnabled, budgetSharePercent: Int(budgetShare), tokenCap: tokenCap)
            errorText = nil
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }

    private func dreamNow() async {
        do {
            try await appModel.connection(for: session.account).startMemoryDream()
            noticeText = String(localized: "Started. It runs in the background.")
            errorText = nil
            await load()
        } catch {
            errorText = error.userMessage
        }
    }
    }
}
