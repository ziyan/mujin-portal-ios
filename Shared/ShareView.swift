import PortalKit
import SwiftUI

/// ShareView is the sheet the share extension shows, and the app shows it
/// for the demo: pick the account, pick where it goes, say what to add, send.
struct ShareView: View {
    @State var model: ShareModel
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .editing: form
                case .sending: progress
                case .done: finished
                case .failed(let message, let canContinueWithoutFiles): failure(message: message, canContinueWithoutFiles: canContinueWithoutFiles)
                }
            }
            .navigationTitle("Share to Portal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.phase == .sending ? "Close" : "Cancel", action: onCancel)
                }
                if model.phase == .editing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await model.send() } }
                            .disabled(!model.canSend)
                    }
                }
            }
        }
        .task(id: model.selectedAccountKey + model.destination.rawValue) { await model.loadSites() }
    }

    private var form: some View {
        Form {
            if model.accounts.count > 1 {
                Section("Account") {
                    Picker("Account", selection: $model.selectedAccountKey) {
                        ForEach(model.accounts, id: \.accountKey) { account in
                            Text("\(account.displayName) (\(account.server.displayHost))").tag(account.accountKey)
                        }
                    }
                }
            } else if let account = model.selectedAccount {
                Section("Account") {
                    LabeledContent(account.displayName, value: account.server.displayHost)
                }
            }
            Section {
                Picker("Send to", selection: $model.destination) {
                    Text("Ask the assistant").tag(ShareModel.Destination.assistant)
                    Text("New ticket").tag(ShareModel.Destination.ticket)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if model.destination == .ticket {
                Section("Ticket") {
                    TextField("Title", text: $model.title)
                    if model.isLoadingSites {
                        ProgressView()
                    } else if let error = model.sitesError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    } else if !model.sites.isEmpty {
                        Picker("Site", selection: $model.siteId) {
                            Text("Choose a site").tag("")
                            ForEach(model.sites) { site in
                                Text(site.name ?? site.id).tag(site.id)
                            }
                        }
                    }
                    Picker("Priority", selection: $model.priority) {
                        ForEach(ShareModel.priorities, id: \.self) { priority in
                            Text(Self.priorityName(priority)).tag(priority)
                        }
                    }
                }
            }
            Section(model.destination == .ticket ? "Description" : "Message") {
                TextEditor(text: $model.text)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("shareText")
            }
            if !model.files.isEmpty || !model.skippedMessages.isEmpty {
                Section("Attachments") {
                    ForEach(model.files) { file in
                        FileRow(file: file)
                    }
                    ForEach(model.skippedMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Sending")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Sent")
                .font(.title3.weight(.semibold))
            Button("Done", action: onFinish)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            onFinish()
        }
    }

    private func failure(message: String, canContinueWithoutFiles: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Could not send")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if canContinueWithoutFiles {
                Button("Send without the files") { Task { await model.continueWithoutFiles() } }
                    .buttonStyle(.borderedProminent)
            }
            Button("Back to editing") { model.edit() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func priorityName(_ priority: String) -> String {
        switch priority {
        case "low": String(localized: "Low")
        case "high": String(localized: "High")
        case "urgent": String(localized: "Urgent")
        default: String(localized: "Normal")
        }
    }
}

private struct FileRow: View {
    let file: SharedFile

    var body: some View {
        HStack(spacing: 12) {
            if let data = file.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: file.contentType == "application/pdf" ? "doc.richtext" : file.isImage ? "photo" : "doc")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
