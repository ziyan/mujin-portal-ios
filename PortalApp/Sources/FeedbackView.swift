import PortalKit
import SwiftUI
import UIKit

/// FeedbackRequest is a feedback sheet that is open or about to open: the picture of the screen when a screenshot opened it, and
/// the name of the tab the person was on.
struct FeedbackRequest: Identifiable {
    let id = UUID()
    let pictureData: Data?
    let screenName: String?
}

/// FeedbackPreference is the choice, kept on this phone, to be asked for feedback after a screenshot. It is on until turned off.
enum FeedbackPreference {
    static let askAfterScreenshotKey = "shouldAskForFeedbackAfterScreenshot"

    static var shouldAskAfterScreenshot: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: askAfterScreenshotKey) == nil ? true : defaults.bool(forKey: askAfterScreenshotKey)
    }
}

/// ScreenPicture draws the app's own window. The system's screenshot notification carries no image, and reading the one it saved
/// would need access to Photos, so the app draws what it shows itself. Video and camera surfaces can come out blank.
@MainActor
enum ScreenPicture {
    static func captureKeyWindow() -> Data? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window, window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.pngData()
    }
}

/// FeedbackDevice names the kind of phone, such as "iPhone17,1". The name the person gave the phone is personal and is not sent.
enum FeedbackDevice {
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// PortalFeedbackLabel marks a ticket that is feedback about Portal itself.
struct PortalFeedbackLabel: View {
    var body: some View {
        Label("Portal feedback", systemImage: "text.bubble")
            .labelStyle(InlineLabelStyle())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("portalFeedbackLabel")
    }
}

/// FeedbackView is where a person tells the Portal team what is wrong with the app or what could be better. It opens as a sheet
/// after a screenshot, with the picture of the screen attached, and from Settings at any time. Nothing is sent until Send is pressed.
struct FeedbackView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let request: FeedbackRequest

    @State private var feedbackText = ""
    @State private var drafts = AttachmentDrafts()
    @State private var hasAddedPicture = false
    @State private var isSending = false
    @State private var errorText: String?
    @State private var sentTicket: Ticket?
    @State private var isOpeningSiteTicket = false

    var body: some View {
        NavigationStack {
            Group {
                if let sentTicket {
                    sent(sentTicket)
                } else {
                    form
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sentTicket == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSending)
                            .accessibilityIdentifier("feedbackCancelButton")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button("Send") { Task { await send() } }
                                .disabled(!PortalFeedback.canSend(feedbackText: feedbackText, isSending: isSending))
                                .accessibilityIdentifier("feedbackSendButton")
                        }
                    }
                }
            }
            .attachmentPickers(drafts)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Words that were typed are not lost to a swipe; Cancel is the way out.
        .interactiveDismissDisabled(isSending || (sentTicket == nil && !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        .task {
            guard !hasAddedPicture, let pictureData = request.pictureData else { return }
            hasAddedPicture = true
            await drafts.addPicture(data: pictureData, source: .screenshot)
        }
    }

    private var form: some View {
        Form { PortalRows {
            Section {
                Text("This goes to the Portal team, for problems with the app or ideas to improve it. For a problem at a site, open a ticket for that site instead.")
                    .font(.subheadline)
                    .accessibilityIdentifier("feedbackNotice")
                Button {
                    isOpeningSiteTicket = true
                } label: {
                    HStack {
                        Label("Open a ticket for a site", systemImage: "building.2")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                // A row that opens something reads as a navigation row: plain text, not the accent a Button takes in a list.
                .buttonStyle(.plain)
                .accessibilityIdentifier("feedbackSiteTicketButton")
            }
            Section {
                TextField("What's wrong, or what could be better?", text: $feedbackText, axis: .vertical)
                    .lineLimit(4...12)
                    .accessibilityIdentifier("feedbackWordsField")
            }
            Section {
                AttachmentStrip(drafts: drafts)
                AttachMenu(drafts: drafts)
                if let message = drafts.errorText {
                    Text(message).font(.footnote).foregroundStyle(Color.statusError)
                }
            } header: {
                Text("Pictures")
            } footer: {
                Text(readersText)
                    .accessibilityIdentifier("feedbackReaders")
            }
            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(Color.statusError)
                        .accessibilityIdentifier("feedbackError")
                }
            }
        } }
        .portalList()
        .sheet(isPresented: $isOpeningSiteTicket) {
            TicketCreateView { ticketId in
                session.cache.remove(CacheKey(accountKey: session.account.accountKey, name: "tickets", variables: ""))
                session.ticketToOpen = ticketId
                session.selectedSection = .tickets
                dismiss()
            }
        }
    }

    /// Who can read what is sent, said before it is sent.
    private var readersText: LocalizedStringKey {
        if drafts.items.contains(where: { $0.filename.hasPrefix(String(localized: "Screenshot")) }) {
            return "The screenshot is sent with your words. The Portal team can read them, and so can people in your organization who can read all tickets."
        }
        if !drafts.items.isEmpty {
            return "The pictures are sent with your words. The Portal team can read them, and so can people in your organization who can read all tickets."
        }
        return "Your words are sent as a ticket. The Portal team can read it, and so can people in your organization who can read all tickets."
    }

    private func sent(_ ticket: Ticket) -> some View {
        ContentUnavailableView {
            Label("Feedback sent", systemImage: "checkmark.circle")
        } description: {
            if let sequence = ticket.sequence {
                Text("Your feedback was sent as ticket #\(sequence). You can follow it under My feedback.")
            } else {
                Text("Your feedback was sent. You can follow it under My feedback.")
            }
        } actions: {
            Button("My feedback") { showMyFeedback() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("feedbackMyFeedbackButton")
            Button("Done") { dismiss() }
                .accessibilityIdentifier("feedbackDoneButton")
        }
    }

    private func showMyFeedback() {
        session.moreScreenToOpen = .myFeedback
        session.selectedSection = .more
        dismiss()
    }

    /// Uploads the pictures, then sends the words. A failure leaves the words and the pictures as they were, and says why.
    private func send() async {
        guard PortalFeedback.canSend(feedbackText: feedbackText, isSending: isSending) else { return }
        isSending = true
        errorText = nil
        defer { isSending = false }
        do {
            let connection = appModel.connection(for: session.account)
            let files = try await drafts.upload(using: connection)
            sentTicket = try await connection.submitPortalFeedback(
                PortalFeedbackRequest(
                    feedbackText: feedbackText, attachmentIds: files.map(\.id), clientVersion: AboutView.versionText, deviceName: FeedbackDevice.modelIdentifier,
                    systemVersion: UIDevice.current.systemVersion, screenName: request.screenName))
            session.cache.remove(CacheKey(accountKey: session.account.accountKey, name: "tickets", variables: ""))
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }
}
