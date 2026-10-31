import PortalKit
import SwiftUI

/// IdeasView is what the assistant suggests it could do for the person. Each
/// idea can be talked through in a new conversation, turned into a goal, or put away.
struct IdeasView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var ideas: [Idea] = []
    @State private var earlier: [Idea] = []
    @State private var phase = LoadPhase.loading
    @State private var showsEarlier = false
    @State private var errorText: String?
    @State private var busyIdeaId: String?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load ideas", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showsEarlier) { Label("Earlier ideas", systemImage: "clock.arrow.circlepath") }
                    .toggleStyle(.button)
            }
        }
        .task { await load() }
        .task(id: showsEarlier) { if showsEarlier { await loadEarlier() } }
    }

    private var list: some View {
        List {
            PortalRows {
                if ideas.isEmpty {
                    Section {
                        Text("No ideas right now. The assistant suggests things when it notices something worth doing.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(ideas) { idea in
                    Section { IdeaCard(idea: idea, isBusy: busyIdeaId == idea.id, onTalk: { Task { await talk(idea) } }, onGoal: { Task { await makeGoal(idea) } }, onDismiss: { Task { await dismiss(idea) } }, open: open) }
                }
                if showsEarlier {
                    Section("Earlier") {
                        if earlier.isEmpty { Text("Nothing earlier.").foregroundStyle(.secondary) }
                        ForEach(earlier) { idea in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(idea.headline ?? "").font(.subheadline.weight(.semibold))
                                Text(idea.ideaStatus ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func load() async {
        do {
            ideas = try await appModel.connection(for: session.account).ideas()
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if ideas.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    private func loadEarlier() async {
        earlier = (try? await appModel.connection(for: session.account).ideas(statuses: ["started", "done", "dismissed", "expired"])) ?? []
    }

    /// Starts the idea: its request goes in a new conversation's composer and nothing is sent.
    private func talk(_ idea: Idea) async {
        busyIdeaId = idea.id
        defer { busyIdeaId = nil }
        do {
            let draft = try await appModel.connection(for: session.account).startIdea(id: idea.id)
            ideas.removeAll { $0.id == idea.id }
            await session.beginDraft(draft.isEmpty ? (idea.openingRequest ?? "") : draft)
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }

    private func makeGoal(_ idea: Idea) async {
        busyIdeaId = idea.id
        defer { busyIdeaId = nil }
        do {
            let goal = try await appModel.connection(for: session.account).startGoalFromIdea(id: idea.id)
            ideas.removeAll { $0.id == idea.id }
            session.goalToOpen = goal.id
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }

    private func dismiss(_ idea: Idea) async {
        busyIdeaId = idea.id
        defer { busyIdeaId = nil }
        do {
            try await appModel.connection(for: session.account).dismissIdea(id: idea.id)
            ideas.removeAll { $0.id == idea.id }
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }

    /// Opens the thing an idea points at: a site, a controller, a virtual controller or a conversation.
    private func open(_ evidence: Idea.Evidence) {
        guard evidence.isLinkable, let id = evidence.evidenceId else { return }
        switch evidence.evidenceKind {
        case "conversation": session.open(.conversation(id: id))
        case "site": link("/site/\(id)")
        case "controller": link("/controller/\(id)")
        case "virtual_controller": link("/virtualcontroller/\(id)")
        default: break
        }
    }

    private func link(_ path: String) {
        guard let url = URL(string: session.account.server.description + path) else { return }
        Task { await appModel.openInApp(url, account: session.account) }
    }
}

private struct IdeaCard: View {
    let idea: Idea
    let isBusy: Bool
    let onTalk: () -> Void
    let onGoal: () -> Void
    let onDismiss: () -> Void
    let open: (Idea.Evidence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(idea.headline ?? "").font(.headline)
            if let body = idea.body, !body.isEmpty { Text(body).font(.subheadline).foregroundStyle(.secondary) }
            if let evidence = idea.evidence, !evidence.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(evidence) { item in
                            if item.isLinkable {
                                Button { open(item) } label: { chip(item) }.buttonStyle(.plain)
                            } else {
                                chip(item)
                            }
                        }
                    }
                }
            }
            // Full-width capsules on their own lines, so no label ever wraps; the one prominent button is first.
            VStack(spacing: 8) {
                Button(action: onTalk) { Text("Talk it through").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button(action: onGoal) { Text("Make it a goal").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button(action: onDismiss) { Text("Not interested").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(isBusy)
        }
        .padding(.vertical, 4)
    }

    private func chip(_ item: Idea.Evidence) -> some View {
        Text(item.evidenceLabel ?? item.evidenceId ?? "")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.portalPage, in: Capsule())
            .foregroundStyle(item.isLinkable ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
    }
}
