import PortalKit
import SwiftUI

/// GoalsView lists what the assistant is working toward for the person: the
/// goals that need them first, then the ones being worked on, then those that ended.
struct GoalsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var goals: [Goal] = []
    @State private var phase = LoadPhase.loading
    @State private var isStarting = false
    @State private var includesOthers = false

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load goals", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if goals.isEmpty {
                    ContentUnavailableView {
                        Label("No goals yet", systemImage: "scope")
                    } description: {
                        Text("Ask the assistant to keep working toward something and check in on it. Start one here or in a conversation.")
                    } actions: {
                        Button("New goal") { isStarting = true }
                    }
                } else {
                    list
                }
            }
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isStarting = true } label: { Label("New goal", systemImage: "plus") }
                    if session.isStaff || session.profile?.me.permissions?.contains("agent:manage") == true {
                        Toggle("Include other people's", isOn: $includesOthers)
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isStarting) {
            NewGoalView { goal in
                goals.insert(goal, at: 0)
                // More shows the new goal's page.
                session.goalToOpen = goal.id
            }
        }
        .task(id: includesOthers) { await load() }
    }

    private var list: some View {
        List {
            PortalRows {
                ForEach(sections, id: \.key) { section in
                    Section(section.title) {
                        ForEach(section.goals) { goal in
                            NavigationLink(value: MoreDestination.goal(goal.id)) { GoalRow(goal: goal) }
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private struct GoalSection {
        let key: String
        let title: LocalizedStringKey
        let goals: [Goal]
    }

    private var sections: [GoalSection] {
        let sorted = self.goals.sortedForList
        func inState(_ state: GoalState) -> [Goal] { sorted.filter { $0.state == state } }
        return [
            GoalSection(key: "waiting", title: "Needs you", goals: inState(.waiting)),
            GoalSection(key: "working", title: "Working", goals: inState(.working)),
            GoalSection(key: "met", title: "Done", goals: inState(.met)),
            GoalSection(key: "stopped", title: "Stopped", goals: inState(.stopped)),
        ].filter { !$0.goals.isEmpty }
    }

    private func load() async {
        do {
            goals = try await appModel.connection(for: session.account).goals(includeOthers: includesOthers)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if goals.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

/// LoadPhase is where a screen's first load stands.
enum LoadPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

private struct GoalRow: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title ?? "").font(.body.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 8)
                GoalStateBadge(state: goal.state)
            }
            if goal.state == .waiting, let question = goal.waitingQuestion, !question.isEmpty {
                Text(question).font(.subheadline).foregroundStyle(.primary).lineLimit(3)
            } else if let status = goal.statusLine, !status.isEmpty {
                Text(status).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            if goal.state == .working, let next = goal.nextCheck {
                Text("Next check \(next, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct GoalStateBadge: View {
    let state: GoalState

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var label: LocalizedStringKey {
        switch state {
        case .waiting: "Needs you"
        case .working: "Working"
        case .met: "Done"
        case .stopped: "Stopped"
        }
    }

    private var tint: Color {
        switch state {
        case .waiting: Color.statusWarning
        case .working: Color.accentColor
        case .met: Color.statusSuccess
        case .stopped: Color.portalSecondary
        }
    }
}

/// GoalDetailView is one goal: where it stands, what the assistant did toward
/// it, a way to tell it something and to end or reopen it.
struct GoalDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let goalId: String

    @State private var goal: Goal?
    @State private var activities: [GoalActivity] = []
    @State private var turns: [AgentActivity] = []
    @State private var note = ""
    @State private var errorText: String?
    @State private var isConfirmingStop = false
    @State private var isBusy = false

    var body: some View {
        // The composer sits below the list, so the last item is never under it.
        VStack(spacing: 0) {
            listView
            if goal?.isOpen == true {
                ComposerCard(
                    placeholder: goal?.state == .waiting ? LocalizedStringKey("Your answer") : LocalizedStringKey("Tell the assistant"), text: $note,
                    canSend: !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy, isSending: isBusy,
                    fieldIdentifier: "goalField", sendIdentifier: "goalSendButton", onSend: { Task { await tell() } })
            }
        }
        .background(Color.portalPage)
        .navigationTitle(goal?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Stop this goal?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
            Button("Stop this goal", role: .destructive) { Task { await change { try await $0.stopGoal(id: goalId) } } }
        } message: {
            Text("The assistant stops working toward it. You can reopen it later.")
        }
        .task { await load() }
    }

    private var listView: some View {
        List {
            PortalRows {
                if let goal {
                    Section {
                        HStack {
                            Text(goal.title ?? "").font(.headline)
                            Spacer()
                            GoalStateBadge(state: goal.state)
                        }
                        if let description = goal.description, !description.isEmpty { Text(description).font(.body) }
                        if let status = goal.statusLine, !status.isEmpty { LabeledContent("Status") { Text(status) } }
                        if let next = goal.nextCheck, goal.state == .working {
                            LabeledContent("Next check") { Text(next, format: .relative(presentation: .named)) }
                        }
                        if let last = goal.lastCheck { LabeledContent("Last check") { Text(last, format: .relative(presentation: .named)) } }
                    }
                    if goal.state == .waiting, let question = goal.waitingQuestion, !question.isEmpty {
                        Section("The assistant asks") {
                            Text(question)
                        }
                    }
                    if let conversationId = goal.conversationId, !conversationId.isEmpty {
                        Section {
                            Button {
                                session.open(.conversation(id: conversationId))
                            } label: {
                                Label("Open the goal's conversation", systemImage: "bubble.left")
                            }
                        }
                    }
                    if !activities.isEmpty {
                        Section("What the assistant did") {
                            ForEach(activities) { activity in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.activityText ?? "")
                                    if let date = activity.date {
                                        Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !turns.isEmpty {
                        Section("Turns") {
                            ForEach(turns) { turn in
                                HStack {
                                    Text(turn.title ?? String(localized: "Goal check-in"))
                                    Spacer()
                                    Text(turn.activityStatus ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        if goal.isOpen {
                            Button("Mark as done") { Task { await change { try await $0.markGoalMet(id: goalId, statusLine: goal.statusLine ?? "") } } }
                            Button("Stop this goal", role: .destructive) { isConfirmingStop = true }
                        } else {
                            Button("Reopen") { Task { await change { try await $0.reopenGoal(id: goalId) } } }
                        }
                    }
                    if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
                } else {
                    ProgressView()
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        do {
            let loaded = try await connection.goal(id: goalId)
            goal = loaded
            activities = (try? await connection.goalActivities(id: goalId)) ?? activities
            turns = (try? await connection.goalTurns(id: goalId)) ?? turns
        } catch {
            appModel.handle(error, account: session.account)
            if goal == nil { errorText = error.userMessage }
        }
    }

    private func tell() async {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await change { try await $0.tellGoal(id: goalId, text: text) }
        note = ""
    }

    private func change(_ action: (Connection) async throws -> Goal) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await action(appModel.connection(for: session.account))
            goal = updated
            errorText = nil
            await load()
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }
}

/// NewGoalView asks for a goal's title, what done looks like and how often to check.
struct NewGoalView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onStarted: (Goal) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var intervalMinutes = 60
    @State private var errorText: String?
    @State private var isBusy = false

    private static let intervals: [(minutes: Int, label: LocalizedStringKey)] = [
        (15, "Every 15 minutes"), (60, "Every hour"), (240, "Every 4 hours"), (1_440, "Every day"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                PortalRows {
                    Section {
                        TextField("What should the assistant work toward?", text: $title)
                        TextField("What does done look like?", text: $description, axis: .vertical)
                            .lineLimit(2...6)
                    }
                    Section("Check in") {
                        Picker("How often", selection: $intervalMinutes) {
                            ForEach(Self.intervals, id: \.minutes) { Text($0.label).tag($0.minutes) }
                        }
                    }
                    if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
                }
            }
            .portalList()
            .navigationTitle("New goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { Task { await start() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                }
            }
        }
    }

    private func start() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let goal = try await appModel.connection(for: session.account).startGoal(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                checkIntervalMinutes: intervalMinutes)
            onStarted(goal)
            dismiss()
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }
}
