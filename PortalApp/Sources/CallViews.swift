import PortalKit
import SwiftUI

/// CallBar is the minimized call: a bar at the top of the app with the chat's name, how long the call has run, mute and hang up.
/// A tap anywhere else brings the call screen back. It stays over every tab.
struct CallBar: View {
    let center: CallCenter
    let call: ChatCallSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = AnyLayout(HStackLayout(spacing: 10))
        layout {
            Button { center.show() } label: {
                HStack(spacing: 10) {
                    Image(systemName: call.isCameraOn ? "video.fill" : "phone.fill")
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Color.statusSuccess, in: .circle)
                        .fixedSize()
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(call.chatTitle).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(call.statusText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            if call.isTranscriptionOn { RecordingMark() }
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to the call")
            .accessibilityIdentifier("callBar")
            HStack(spacing: 8) {
                Button { center.setMuted(!call.isMuted) } label: {
                    Image(systemName: call.isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(call.isMuted ? Color.black : Color.primary)
                        .frame(width: 36, height: 36)
                        .background(call.isMuted ? Color.white : Color.clear, in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(call.isMuted ? "Unmute" : "Mute")
                Button { center.hangUp() } label: {
                    Image(systemName: "phone.down.fill")
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.statusError, in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave call")
            }
        }
        // The bar keeps to one line of controls: its text stops growing at the largest ordinary size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

/// RecordingMark is the red dot and the word that say a call is being recorded, beside its time wherever the call is put away.
struct RecordingMark: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.statusError).frame(width: 7, height: 7)
            Text("Recording").font(.caption.weight(.semibold)).foregroundStyle(Color.statusError).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("This call is being recorded and transcribed."))
    }
}

/// CallBanner tells a chat that a call is going and offers to join it, or to go back to it when the person is on it.
struct CallBanner: View {
    let call: ChatCall
    let isOnThisCall: Bool
    let onJoin: () -> Void
    let onReturn: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var names: String {
        let joined = call.joinedMembers.map(\.shownName)
        return joined.isEmpty ? (call.startedByUserName ?? "") : joined.joined(separator: ", ")
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(spacing: 10) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Color.statusSuccess, in: .circle)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Call in progress").font(.subheadline.weight(.semibold))
                    if !names.isEmpty { Text(names).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 4)
            }
            Button(action: isOnThisCall ? onReturn : onJoin) {
                Text(isOnThisCall ? "Return" : "Join")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("joinCallButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// CallLineView is a call in the chat's history: who called, how long it lasted or how it ended, and the transcript when there is one.
struct CallLineView: View {
    @ScaledMetric(relativeTo: .body) private var iconColumnWidth = 26
    let call: ChatCall
    let currentUserId: String
    /// Reads the call's words and recordings, which the chat's history leaves out.
    let loadDetail: () async throws -> ChatCall
    let openRecording: (ChatCallRecording) -> Void

    @State private var isShowingTranscript = false
    @State private var detail: ChatCall?
    @State private var isLoading = false
    @State private var didFailToLoad = false

    /// The call with its words and recordings once they are read.
    private var shownCall: ChatCall { detail ?? call }

    private var callerText: String {
        call.startedByUserId == currentUserId ? String(localized: "You called") : String(localized: "\(call.startedByUserName ?? String(localized: "Someone")) called")
    }

    private var outcomeText: String {
        switch ChatCallRules.outcome(of: call) {
        case .going: return String(localized: "In progress")
        case .missed: return String(localized: "Missed")
        case .declined: return String(localized: "Declined")
        case .failed: return String(localized: "Call failed")
        case .ended(let duration): return duration.map { ChatCallRules.elapsedText($0) } ?? String(localized: "Ended")
        }
    }

    private var isMissed: Bool {
        let outcome = ChatCallRules.outcome(of: call)
        return outcome == .missed || outcome == .declined || outcome == .failed
    }

    var body: some View {
        let segments = shownCall.spokenSegments()
        let recordings = shownCall.recordingAttachments ?? []
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isMissed ? "phone.down.fill" : "phone.fill")
                    .foregroundStyle(isMissed ? Color.statusError : Color.statusSuccess)
                    // The two symbols differ in width, so a fixed column keeps the words of every row on one line.
                    .frame(width: iconColumnWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(callerText).font(.subheadline.weight(.semibold))
                    Text(outcomeText).font(.footnote).foregroundStyle(isMissed ? Color.statusError : Color.secondary)
                }
                if call.transcriptStatus == .ready || !segments.isEmpty {
                    Spacer(minLength: 8)
                    Button { isShowingTranscript.toggle() } label: {
                        Text(isShowingTranscript ? "Hide transcript" : "Show transcript").font(.footnote.weight(.medium)).multilineTextAlignment(.trailing)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("callTranscriptToggle")
                }
            }
            switch call.transcriptStatus {
            case .transcribing:
                statusText("Transcribing…")
            case .failed:
                statusText("No recording or transcript is available.")
            case .none, .ready:
                EmptyView()
            }
            if isShowingTranscript {
                VStack(alignment: .leading, spacing: 6) {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if didFailToLoad {
                        Text("Could not load the transcript.").font(.footnote).foregroundStyle(Color.statusError)
                    }
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        (Text((segment.userName ?? "") + ": ").font(.footnote.weight(.semibold)) + Text(segment.text ?? "").font(.footnote))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(recordings) { recording in
                            Button { openRecording(recording) } label: {
                                Label("Recording of \(shownCall.member(recording.uploadedByUserId)?.userName ?? "")", systemImage: "waveform")
                                    .font(.footnote.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("callRecording-\(recording.id)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("callTranscript")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear {
            if DemoOptions.screen == "chat-call-transcript", call.transcriptStatus == .ready { isShowingTranscript = true }
        }
        .task(id: isShowingTranscript) {
            if isShowingTranscript { await loadDetailIfNeeded() }
        }
    }

    private func statusText(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.footnote).foregroundStyle(Color.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadDetailIfNeeded() async {
        guard detail == nil, !isLoading else { return }
        isLoading = true
        didFailToLoad = false
        defer { isLoading = false }
        do {
            detail = try await loadDetail()
        } catch {
            didFailToLoad = !Task.isCancelled
        }
    }
}

/// CallPeoplePicker picks the people a call rings: when choosing who to call, with a choice of voice or video, and when ringing
/// people who have not joined yet.
struct CallPeoplePicker: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let people: [ChatMember]
    let showsVideoChoice: Bool
    /// The most people a call holds. Until the server says, the app's own number.
    var maximumPeople = ChatCallRules.maximumParticipants
    let onConfirm: ([String], Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: Set<String> = DemoOptions.screen == "call-picker" ? ["user03"] : []
    @State private var isVideo = false
    @State private var searchText = ""

    /// With this many people to pick from, the list can be searched.
    private static let searchablePersonCount = 9

    private var shownPeople: [ChatMember] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return people }
        return people.filter { $0.shownName.localizedCaseInsensitiveContains(text) || ($0.organizationName ?? "").localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    if showsVideoChoice {
                        Section {
                            Picker("Kind of call", selection: $isVideo) {
                                Text("Voice").tag(false)
                                Text("Video").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    Section {
                        if people.isEmpty {
                            Text("Everyone is already on the call.").foregroundStyle(.secondary)
                        }
                        ForEach(shownPeople) { person in
                            Button {
                                if selected.contains(person.userId) { selected.remove(person.userId) } else { selected.insert(person.userId) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selected.contains(person.userId) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(person.userId) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                        .accessibilityHidden(true)
                                    if !dynamicTypeSize.isAccessibilitySize { UserAvatar(userId: person.userId, name: person.shownName, size: 32) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.shownName).foregroundStyle(.primary).portalNameLine()
                                        if let organization = person.organizationName, !organization.isEmpty {
                                            Text(organization).font(.footnote).foregroundStyle(.secondary).portalNameLine()
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected.contains(person.userId) ? .isSelected : [])
                        }
                    } footer: {
                        Text(String(localized: "A call holds up to \(maximumPeople) people."))
                    }
                }
            }
            .portalList()
            .searchablePeople(isOn: people.count >= Self.searchablePersonCount, text: $searchText)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        onConfirm(people.filter { selected.contains($0.userId) }.map(\.userId), isVideo)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
