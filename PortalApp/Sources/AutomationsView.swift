import Observation
import PortalKit
import SwiftUI

/// AutomationsModel loads what the assistant does on its own: its schedule,
/// the runs it did, and the work it started in the background.
@MainActor
@Observable
final class AutomationsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var days: [ScheduleDay] = []
    private(set) var unreadableJobCount = 0
    private(set) var activities: [AgentActivity] = []
    private(set) var work: [BackgroundWork] = []
    /// Widens every list to the people the person may read for.
    var includesOthers = false

    init(connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.onError = onError
    }

    func loadAll() async {
        do {
            async let schedule = connection.schedule(includeOthers: includesOthers)
            async let activity = connection.activity(includeOthers: includesOthers)
            async let background = connection.backgroundWork(includeOthers: includesOthers, includeFinished: true)
            let (loadedSchedule, loadedActivity, loadedWork) = try await (schedule, activity, background)
            days = AgentSchedule.groupedByDay(loadedSchedule.occurrences)
            unreadableJobCount = loadedSchedule.unreadableJobCount
            activities = loadedActivity
            work = loadedWork
            phase = .loaded
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    /// Reads the runs again, for the poll while any is queued or running.
    func refreshProgress() async {
        if let loaded = try? await connection.activity(includeOthers: includesOthers) { activities = loaded }
        if let loaded = try? await connection.backgroundWork(includeOthers: includesOthers, includeFinished: true) { work = loaded }
    }

    func stop(_ item: BackgroundWork) async {
        do {
            try await connection.stopBackgroundWork(id: item.id)
            await refreshProgress()
        } catch {
            onError(error)
        }
    }

    var needsPolling: Bool { activities.needsPolling || work.contains(where: \.isInProgress) }
}

/// AutomationsView is the Automations screen under More.
struct AutomationsView: View {
    enum Part: String, CaseIterable, Identifiable {
        case schedule
        case activity
        case work
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var model: AutomationsModel?
    @State private var part = Part.schedule

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $part) {
                Text("Schedule").tag(Part.schedule)
                Text("Activity").tag(Part.activity)
                Text("Background work").tag(Part.work)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if let model {
                content(model)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .navigationTitle("Automations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let model {
                ToolbarItem(placement: .topBarTrailing) {
                    @Bindable var bindable = model
                    Menu {
                        Toggle("Include other people's", isOn: $bindable.includesOthers)
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            if model == nil {
                model = AutomationsModel(
                    connection: appModel.connection(for: session.account),
                    onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            }
            await model?.loadAll()
            if appModel.isDemo, let screen = DemoOptions.screen {
                if screen.hasSuffix("activity") { part = .activity } else if screen.hasSuffix("work") { part = .work }
            }
        }
        .task(id: model?.includesOthers) {
            if model != nil { await model?.loadAll() }
        }
        .task(id: model?.needsPolling) {
            // Runs that are queued or running are read again every five seconds.
            guard let model, model.needsPolling, !appModel.isDemo else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                await model.refreshProgress()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: AutomationsModel) -> some View {
        switch model.phase {
        case .loading:
            Spacer()
            ProgressView()
            Spacer()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load automations", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.loadAll() } }
            }
        case .loaded:
            switch part {
            case .schedule: ScheduleList(model: model, open: openConversation)
            case .activity: ActivityList(model: model, open: openConversation, ask: { activity in Task { await session.beginAsk(about: Viewing(kind: "agent_run", id: activity.id, label: activity.title), subject: activity.title ?? "") } })
            case .work: WorkList(model: model, open: openConversation)
            }
        }
    }

    private func openConversation(_ conversationId: String) {
        session.conversationToOpen = conversationId
        session.selectedSection = .assistant
    }
}

private struct ScheduleList: View {
    let model: AutomationsModel
    let open: (String) -> Void

    var body: some View {
        if model.days.isEmpty {
            ContentUnavailableView {
                Label("Nothing scheduled", systemImage: "calendar")
            } description: {
                Text("Jobs your assistant runs on a schedule show up here for the next week.")
            }
        } else {
            List { PortalRows {
                ForEach(model.days) { day in
                    Section {
                        ForEach(day.occurrences) { occurrence in
                            ScheduleRow(occurrence: occurrence, open: open)
                        }
                    } header: {
                        Text(day.day, format: .dateTime.weekday(.wide).month().day())
                    }
                }
                if model.unreadableJobCount > 0 {
                    Section {
                        Label("\(model.unreadableJobCount) jobs could not be read.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            } }
.portalList()
            .refreshable { await model.loadAll() }
        }
    }
}

private struct ScheduleRow: View {
    let occurrence: ScheduleOccurrence
    let open: (String) -> Void

    var body: some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let date = occurrence.date {
                Text(date, format: .dateTime.hour().minute())
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.title ?? "")
                    .foregroundStyle(.primary)
                if let kind = Self.kindText(occurrence) {
                    Text(kind).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        if let conversationId = occurrence.conversationId, !conversationId.isEmpty {
            Button { open(conversationId) } label: { content }
        } else {
            content
        }
    }

    private static func kindText(_ occurrence: ScheduleOccurrence) -> LocalizedStringKey? {
        if occurrence.occurrenceKind == "goal_check_in" { return "Goal check-in" }
        switch occurrence.jobType {
        case "recurring": return "Repeats"
        case "oneshot": return "Once"
        case "monitor": return "Monitor"
        default: return nil
        }
    }
}

/// RunStatus words a run's or work's state with a symbol, so color is never the only signal.
private struct StatusLabel: View {
    let state: String

    var body: some View {
        switch state {
        case "queued": Label("Queued", systemImage: "clock").foregroundStyle(.secondary)
        case "running": Label("Running", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case "succeeded", "done": Label("Done", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case "failed": Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.statusError)
        case "cancelled", "stopped": Label("Stopped", systemImage: "stop.circle").foregroundStyle(.secondary)
        default: Label(state, systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}

private struct ActivityList: View {
    let model: AutomationsModel
    let open: (String) -> Void
    let ask: (AgentActivity) -> Void

    var body: some View {
        if model.activities.isEmpty {
            ContentUnavailableView {
                Label("No runs yet", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Runs your assistant did on its own show up here.")
            }
        } else {
            List(model.activities) { activity in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(activity.title ?? "").font(.headline).lineLimit(2)
                        Spacer(minLength: 8)
                        if let date = activity.startedDate {
                            Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    StatusLabel(state: activity.activityStatus ?? "").font(.footnote)
                    if let message = activity.errorMessage, activity.hasFailed, !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let cost = activity.costText {
                        Text(cost).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Cost not recorded").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let conversationId = activity.conversationId, !conversationId.isEmpty { open(conversationId) }
                }
                .contextMenu {
                    if let conversationId = activity.conversationId, !conversationId.isEmpty {
                        Button { open(conversationId) } label: { Label("Open the conversation", systemImage: "bubble.left") }
                    }
                    Button {
                        ask(activity)
                    } label: {
                        Label("Ask about this", systemImage: "sparkles")
                    }
                }
.listRowBackground(Color.portalCard)
}
.portalList()
            .refreshable { await model.loadAll() }
        }
    }
}

private struct WorkList: View {
    let model: AutomationsModel
    let open: (String) -> Void

    var body: some View {
        if model.work.isEmpty {
            ContentUnavailableView {
                Label("No background work", systemImage: "square.stack.3d.up")
            } description: {
                Text("Work your assistant starts and lets run on its own shows up here.")
            }
        } else {
            List(model.work) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title ?? item.purpose ?? "").font(.headline).lineLimit(2)
                    StatusLabel(state: item.workState ?? "").font(.footnote)
                    if let purpose = item.purpose, !purpose.isEmpty, purpose != item.title {
                        Text(purpose).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                    if let report = item.reportText {
                        DisclosureGroup("Report") {
                            Text(report).font(.footnote).textSelection(.enabled)
                        }
                        .font(.footnote)
                    }
                    if item.isInProgress {
                        Button("Stop", role: .destructive) { Task { await model.stop(item) } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 2)
                .contextMenu {
                    if let conversationId = item.parentConversationId, !conversationId.isEmpty {
                        Button { open(conversationId) } label: { Label("Open the conversation", systemImage: "bubble.left") }
                    }
                }
.listRowBackground(Color.portalCard)
}
.portalList()
            .refreshable { await model.loadAll() }
        }
    }
}
