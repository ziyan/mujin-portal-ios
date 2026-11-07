import PortalKit
import SwiftUI

/// SitePageEditView changes the title and words of a page, as the web's editor does. Saving keeps a draft that only people who can
/// edit pages see; publishing makes it the page readers see, and is offered only to people who may publish.
struct SitePageEditView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let page: SitePage
    let onSaved: (SitePage, SitePageRevision?) -> Void

    @State private var draft: SitePageDraft
    @State private var startingDraft: SitePageDraft
    @State private var actions = ActionState()
    @State private var isConfirmingDiscard = false

    init(page: SitePage, revision: SitePageRevision?, onSaved: @escaping (SitePage, SitePageRevision?) -> Void) {
        self.page = page
        self.onSaved = onSaved
        let starting = page.editingDraft(revision: revision)
        _draft = State(initialValue: starting)
        _startingDraft = State(initialValue: starting)
    }

    private var isChanged: Bool { draft != startingDraft }
    private var problem: SitePageProblem? { SitePageRules.problem(in: draft) }
    private var canSubmit: Bool { problem == nil && !actions.isWorking }

    private var problemText: LocalizedStringKey? {
        switch problem {
        case .titleIsTooLong: LocalizedStringKey("The title is too long. Keep it under 256 characters.")
        case .contentIsTooLarge: LocalizedStringKey("The page is too long to save. Split it into more than one page.")
        case .summaryIsTooLong: LocalizedStringKey("The note is too long. Keep it under 512 characters.")
        case .titleIsEmpty, nil: nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section("Title") {
                        TextField("Title", text: $draft.title)
                            .accessibilityIdentifier("sitePageTitleField")
                    }
                    Section {
                        TextEditor(text: $draft.content)
                            .frame(minHeight: 280)
                            .font(.body.monospaced())
                            .scrollContentBackground(.hidden)
                            .accessibilityIdentifier("sitePageContentField")
                    } header: {
                        Text("Content")
                    } footer: {
                        Text("Written in Markdown. Pictures are added on the web; the ones already in the page stay.")
                    }
                    Section {
                        TextField("What changed (optional)", text: $draft.summary)
                            .accessibilityIdentifier("sitePageSummaryField")
                    } footer: {
                        Text("Kept with the version a publish makes.")
                    }
                    if let problemText {
                        Section { Text(problemText).foregroundStyle(Color.statusError) }
                    }
                    if page.canPublish {
                        Section {
                            Button("Publish") { Task { await submit(isPublishing: true) } }
                                .disabled(!canSubmit)
                                .accessibilityIdentifier("sitePagePublishButton")
                        } footer: {
                            Text("Publishing makes this the page readers see. Saving a draft keeps it to people who can edit pages.")
                        }
                    }
                }
            }
            .portalList()
            .navigationTitle("Edit page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isChanged { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("sitePageEditCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save draft") { Task { await submit(isPublishing: false) } }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("sitePageSaveDraftButton")
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(isChanged)
            .failureAlert(actions)
        }
    }

    private func submit(isPublishing: Bool) async {
        let connection = appModel.connection(for: session.account)
        let wantedDraft = draft
        let pageId = page.id
        var answeredPage: SitePage?
        let isDone = await actions.run(appModel: appModel, session: session) {
            if isPublishing {
                answeredPage = try await connection.publishSitePage(pageId: pageId, draft: wantedDraft)
            } else {
                answeredPage = try await connection.saveSitePageDraft(pageId: pageId, draft: wantedDraft)
            }
        }
        guard isDone, let answered = answeredPage else { return }
        // The answer has no word on what the person may do, so the page keeps what it was read with.
        let saved = answered.replacingViewerCapabilities(page.viewerCapabilities)
        onSaved(saved, isPublishing ? SitePageRevision.published(draft: wantedDraft, page: saved) : nil)
        dismiss()
    }
}

/// SitePageCreateView asks for the title of a new page and makes it, at the top of the site or inside another page. A new page is
/// a draft until someone who may publish publishes it.
struct SitePageCreateView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let siteId: String
    let parentPageId: String?
    /// The pages beside the new one, to put it after them.
    let siblings: [SitePage]
    let canPublish: Bool
    let onCreated: (SitePage) -> Void

    @State private var title = ""
    @State private var actions = ActionState()

    private var trimmedTitle: String { SitePageRules.trimmedTitle(title) }
    private var isTooLong: Bool { trimmedTitle.utf8.count > SitePageRules.maximumTitleLength }

    var body: some View {
        NavigationStack {
            List {
                PortalRows {
                    Section {
                        TextField("Title", text: $title)
                            .accessibilityIdentifier("sitePageNewTitleField")
                    } footer: {
                        if isTooLong {
                            Text("The title is too long. Keep it under 256 characters.").foregroundStyle(Color.statusError)
                        } else {
                            Text(LocalizedStringKey(canPublish ? "The new page is a draft until you publish it." : "The new page is a draft until someone who can publish pages publishes it."))
                        }
                    }
                }
            }
            .portalList()
            .navigationTitle(LocalizedStringKey(parentPageId == nil ? "New page" : "New page inside"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(isTooLong || actions.isWorking)
                        .accessibilityIdentifier("sitePageCreateButton")
                }
            }
            .failureAlert(actions)
        }
    }

    private func create() async {
        let connection = appModel.connection(for: session.account)
        // A page with no title is called Untitled, as the web calls it.
        let wantedTitle = trimmedTitle.isEmpty ? String(localized: "Untitled") : trimmedTitle
        let position = SitePageTree.appendPosition(afterSiblings: siblings)
        let siteId = siteId
        let parentPageId = parentPageId
        var createdPage: SitePage?
        let isDone = await actions.run(appModel: appModel, session: session) {
            createdPage = try await connection.createSitePage(siteId: siteId, parentPageId: parentPageId, title: wantedTitle, position: position)
        }
        guard isDone, let created = createdPage else { return }
        onCreated(created)
        dismiss()
    }
}
