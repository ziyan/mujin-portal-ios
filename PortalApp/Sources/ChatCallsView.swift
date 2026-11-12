import PortalKit
import SwiftUI

/// ChatCallsView lists the past calls of a chat, newest first, a page at a time. A call opens to who said what, in time order, and its
/// recordings.
struct ChatCallsView: View {
    let model: ChatModel
    @State private var calls: [ChatCall] = []
    @State private var totalCount = 0
    @State private var phase = LoadPhase.loading
    @State private var openedCallId: String?

    private static let pageSize = 20

    var body: some View {
        List {
            PortalRows {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed(let message):
                    Text(message).foregroundStyle(Color.statusError)
                case .loaded:
                    if calls.isEmpty {
                        Text("No calls yet").foregroundStyle(.secondary)
                    }
                    ForEach(calls) { call in
                        NavigationLink {
                            ChatCallDetailView(model: model, call: call)
                        } label: {
                            ChatCallRow(call: call, currentUserId: model.currentUserId)
                        }
                        .accessibilityIdentifier("pastCallRow")
                        .task {
                            if call.id == calls.last?.id, calls.count < totalCount { await loadMore() }
                        }
                    }
                }
            }
        }
        .portalList()
        .navigationTitle("Calls")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedCallId) { callId in
            if let call = calls.first(where: { $0.id == callId }) { ChatCallDetailView(model: model, call: call) }
        }
        .task {
            await loadMore()
            if DemoOptions.screen == "chat-call-history-detail" { openedCallId = calls.first?.id }
        }
    }

    private func loadMore() async {
        guard let chatId = model.chatId else { return }
        do {
            let page = try await model.connection.pastChatCalls(chatId: chatId, first: Self.pageSize, after: calls.count)
            let held = Set(calls.map(\.id))
            calls += page.calls.filter { !held.contains($0.id) }
            totalCount = page.totalCount
            phase = .loaded
        } catch {
            if calls.isEmpty { phase = .failed(String(localized: "Could not load the calls.")) }
        }
    }
}

/// ChatCallRow is one past call: who called, how it ended, and when.
private struct ChatCallRow: View {
    @ScaledMetric(relativeTo: .body) private var iconColumnWidth = 26
    let call: ChatCall
    let currentUserId: String

    private var callerText: String {
        call.startedByUserId == currentUserId ? String(localized: "You called") : String(localized: "\(call.startedByUserName ?? String(localized: "Someone")) called")
    }

    private var outcomeText: String {
        switch ChatCallRules.outcome(of: call) {
        case .going: String(localized: "In progress")
        case .missed: String(localized: "Missed")
        case .declined: String(localized: "Declined")
        case .failed: String(localized: "Call failed")
        case .ended(let duration): duration.map { ChatCallRules.elapsedText($0) } ?? String(localized: "Ended")
        }
    }

    private var isMissed: Bool {
        let outcome = ChatCallRules.outcome(of: call)
        return outcome == .missed || outcome == .declined || outcome == .failed
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isMissed ? "phone.down.fill" : "phone.fill")
                .foregroundStyle(isMissed ? Color.statusError : Color.statusSuccess)
                .frame(width: iconColumnWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(callerText).font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text(outcomeText).foregroundStyle(isMissed ? Color.statusError : Color.secondary)
                    if let date = PortalDate.parse(call.startedAt) {
                        Text(date, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
            }
        }
        .frame(minHeight: 44)
    }
}

/// ChatCallDetailView is one past call: the words of the call, who said what in time order, and each person's recording.
struct ChatCallDetailView: View {
    @Environment(AppModel.self) private var appModel
    let model: ChatModel
    let call: ChatCall
    @State private var detail: ChatCall?
    @State private var phase = LoadPhase.loading

    var body: some View {
        let shown = detail ?? call
        let segments = shown.spokenSegments()
        let recordings = shown.recordingAttachments ?? []
        List {
            PortalRows {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed(let message):
                    Text(message).foregroundStyle(Color.statusError)
                case .loaded:
                    if !recordings.isEmpty {
                        Section("Recordings") {
                            ForEach(recordings) { recording in
                                Button { open(recording) } label: {
                                    Label("Recording of \(shown.member(recording.uploadedByUserId)?.userName ?? "")", systemImage: "waveform")
                                        .frame(minHeight: 44, alignment: .leading)
                                }
                                .accessibilityIdentifier("callRecording-\(recording.id)")
                            }
                        }
                    }
                    Section("Transcript") {
                        if segments.isEmpty {
                            Text("No recording or transcript is available.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(segment.userName ?? "").font(.footnote.weight(.semibold))
                                    if let startMS = segment.startMS {
                                        Text(VoiceMessageRules.clockText(Double(startMS) / 1000)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text(segment.text ?? "")
                            }
                        }
                    }
                }
            }
        }
        .portalList()
        .navigationTitle("Call")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                detail = try await model.connection.chatCall(id: call.id)
                phase = .loaded
            } catch {
                phase = .failed(String(localized: "Could not load the transcript."))
            }
        }
    }

    private func open(_ recording: ChatCallRecording) {
        Task {
            guard let account = appModel.activeAccount else { return }
            await appModel.openInApp(account.server.endpoint("/api/v1/attachment/\(recording.id)"), account: account)
        }
    }
}
