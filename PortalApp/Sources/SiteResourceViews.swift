import PortalKit
import SwiftUI

/// OrchestratorRow is one orchestrator: the line's own status first, as the web's main status column,
/// and the run status (whether it is executing a command right now) second, each labeled so the two are
/// never read as one. A fault is the warning symbol and the message.
struct OrchestratorRow: View {
    let orchestrator: SiteOrchestrators.Orchestrator
    /// The controller page names the orchestrator by its id; the site list by its type.
    var showsID = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 8)
                    ownStatusView
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    ownStatusView
                }
            }
            if let runStatus = orchestrator.runStatus, !runStatus.isEmpty {
                Text("Run status: \(runStatus)").font(.footnote).foregroundStyle(.secondary)
            }
            if orchestrator.hasError == true, let message = orchestrator.statusMessage, !message.isEmpty {
                Text(message).font(.footnote).foregroundStyle(Color.statusError)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        HStack(spacing: 6) {
            Text(showsID ? (orchestrator.orchestratorId ?? orchestrator.id) : orchestrator.displayName)
                .foregroundStyle(.primary)
            if orchestrator.hasError == true {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusError).accessibilityLabel(Text("Has an error"))
            }
        }
    }

    @ViewBuilder
    private var ownStatusView: some View {
        if let status = orchestrator.ownStatus {
            Text("Line status: \(status)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(orchestrator.isRunning ? Color.statusSuccess : (orchestrator.isInTransition ? Color.statusWarning : Color.secondary))
        } else {
            Text("No line status").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// RobotRow is one mobile robot: its name, which controller it is on, its state, battery and fault.
struct RobotRow: View {
    let robot: SiteRobots.Robot
    var showsController = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    nameView
                    Spacer(minLength: 8)
                    stateView
                }
                VStack(alignment: .leading, spacing: 2) {
                    nameView
                    stateView
                }
            }
            if showsController, !robot.controllerId.isEmpty {
                Text(robot.controllerId).font(.footnote).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { detailParts }
                VStack(alignment: .leading, spacing: 2) { detailParts }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if robot.hasError, let errorText = robot.errorText, !errorText.isEmpty {
                Text(errorText).font(.footnote).foregroundStyle(Color.statusError)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detailParts: some View {
        if let power = robot.powerLevel {
            Label {
                Text(power, format: .percent.precision(.fractionLength(0))).fixedSize()
            } icon: {
                Image(systemName: robot.isCharging ? "battery.100.bolt" : "battery.50")
            }
            .accessibilityLabel(Text("Battery \(power.formatted(.percent.precision(.fractionLength(0))))"))
        }
        if robot.isCharging { Text("Charging") }
        if robot.isLoaded == true { Text("Loaded") }
    }

    private var nameView: some View {
        HStack(spacing: 6) {
            Image(systemName: robot.isOnline ? "checkmark.circle" : "circle.slash").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(robot.name).foregroundStyle(.primary)
            if robot.hasError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusError).accessibilityLabel(Text("Has an error"))
            }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        if let status = robot.statusText, !status.isEmpty {
            Text(LocalizedStringKey(status)).font(.footnote).foregroundStyle(.secondary)
        } else {
            Text(robot.isOnline ? LocalizedStringKey("Online") : LocalizedStringKey("Offline")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// AlarmDetailView is one active alarm in full: what the list shows, then what the controller reports
/// about where it came from, and its metadata as JSON to read and copy. The extra fields are fetched
/// when the screen opens; until then (or if that fails) the screen shows what the list already had.
struct AlarmDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let alarm: SiteAlarm
    let controller: ControllerSummary?

    @State private var detail: AlarmDetail?
    @State private var isLoading = true
    @State private var didFail = false
    @State private var didCopy = false

    var body: some View {
        ScrollViewReader { proxy in
        List { PortalRows {
            Section {
                LabeledContent("Severity") { Text(severityText).foregroundStyle(alarm.severityRank <= 1 ? Color.statusError : Color.statusWarning) }
                if let status = nonEmpty(detail?.alarmStatus ?? alarm.status) { LabeledContent("Status") { Text(status) } }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Message").font(.footnote).foregroundStyle(.secondary)
                    Text(nonEmpty(detail?.alarmMessage ?? alarm.message) ?? "").textSelection(.enabled)
                }
                if let controller {
                    NavigationLink(value: PortalRoute.controller(controller)) {
                        LabeledContent("Controller") { Text(alarm.controllerId).portalNameLine() }
                    }
                } else {
                    LabeledContent("Controller") { Text(alarm.controllerId).portalNameLine() }
                }
            }
            Section("Times") {
                if let started = ControllerTime.text(detail?.occurredAt ?? alarm.occurredAt) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Started").font(.footnote).foregroundStyle(.secondary)
                        Text(started).monospacedDigit()
                    }
                } else {
                    Text("Not reported").foregroundStyle(.secondary)
                }
            }
            Section("Metadata") {
                if isLoading {
                    ProgressView()
                } else if didFail {
                    Label("Could not load the details", systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusError)
                } else if let detail, !detail.metadataEntries.isEmpty {
                    // Code is not wrapped: a long key or value would break mid-word, so a long line scrolls sideways. The code's size is capped so most keys fit.
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(detail.metadataJSON)
                            .font(.footnote.monospaced())
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .id("metadata")
                    Button {
                        UIPasteboard.general.string = detail.metadataJSON
                        didCopy = true
                    } label: {
                        Label(didCopy ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy"), systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                } else {
                    Text("No metadata reported").foregroundStyle(.secondary)
                }
            }
            if let logEntryId = nonEmpty(alarm.logEntryId) {
                Section("Origin") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log entry").font(.footnote).foregroundStyle(.secondary)
                        Text(logEntryId).font(.body.monospaced()).textSelection(.enabled).portalNameLine()
                    }
                    if let label = nonEmpty(alarm.originLabel) { LabeledContent("Raised by") { Text(label).portalNameLine() } }
                    if let kind = nonEmpty(detail?.originKind) { LabeledContent("Origin kind") { Text(kind).portalNameLine() } }
                    if let origin = nonEmpty(detail?.originControllerId) { LabeledContent("Origin controller") { Text(origin).portalNameLine() } }
                    ForEach(detail?.originEntries ?? []) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.key).font(.footnote).foregroundStyle(.secondary).portalNameLine()
                            Text(entry.value.isEmpty ? "\u{2014}" : entry.value).font(.body.monospaced()).textSelection(.enabled).portalNameLine()
                        }
                    }
                }
            }
        } }
        .portalList()
        .navigationTitle("Alarm")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: alarm.id) {
            await load()
            // The screenshot of the metadata scrolls to it: the screen is taller than the display.
            if appModel.isDemo, DemoOptions.screen == "site-alarm-metadata" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation { proxy.scrollTo("metadata", anchor: UnitPoint(x: 0.5, y: 0.1)) }
            }
        }
        }
    }

    private var severityText: String {
        let level = nonEmpty(detail?.alarmLevel ?? alarm.level) ?? ""
        return level.capitalized
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func load() async {
        isLoading = true
        didFail = false
        defer { isLoading = false }
        guard let logEntryId = nonEmpty(alarm.logEntryId) else { return }
        do {
            detail = try await appModel.connection(for: session.account).alarmDetail(controllerId: alarm.controllerId, logEntryId: logEntryId)
        } catch {
            didFail = true
        }
    }
}
