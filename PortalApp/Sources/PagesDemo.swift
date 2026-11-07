import Foundation
import PortalKit

/// PagesDemo is the demo's documentation pages of a site, with the shapes the server answers in: a tree three levels deep, a long page
/// with a table, a list, code and a picture, a page that was never published, and the screens for a person who cannot edit, who can
/// edit but not publish, and for a page or a site that is not there. They are served only on their own screens, against a server that
/// says it has the feature; every other screen is shot against one that does not. All the names and words are invented.
enum PagesDemo {
    static let siteId = "site01"
    static let siteName = "Example Yard"

    static let screens: Set<String> = [
        "site-pages-row", "site-pages", "site-pages-readonly", "site-pages-empty", "site-pages-error", "site-pages-missing", "site-pages-search",
        "site-pages-new", "site-page", "site-page-readonly", "site-page-author", "site-page-nested", "site-page-draft", "site-page-missing",
        "site-page-menu", "site-page-history", "site-page-revision", "site-page-edit",
    ]

    static func owns(_ screen: String?) -> Bool { screen.map { screens.contains($0) } ?? false }

    /// What the demo person may do at the site on this screen.
    static func capabilities(screen: String?) -> [String] {
        switch screen ?? "" {
        case "site-pages-readonly", "site-page-readonly": []
        case "site-page-author": ["page:edit"]
        default: ["page:edit", "page:publish", "page:move", "page:delete", "page:revert"]
        }
    }

    /// The screens a demo run pushes on the site page, in order.
    static func routes(for screen: String) -> [PortalRoute] {
        let tree = PortalRoute.sitePages(siteId: siteId)
        func page(_ id: String) -> PortalRoute { .sitePage(id: id, siteId: siteId) }
        switch screen {
        case "site-pages", "site-pages-readonly", "site-pages-empty", "site-pages-error", "site-pages-missing", "site-pages-new": return [tree]
        case "site-page", "site-page-readonly", "site-page-author", "site-page-menu", "site-page-edit": return [tree, page("page01")]
        case "site-page-nested": return [tree, page("page01"), page("page03"), page("page04")]
        case "site-page-draft": return [tree, page("page05")]
        case "site-page-missing": return [page("page-gone")]
        case "site-page-history", "site-page-revision":
            guard let current = decodedPage(id: "page01") else { return [tree, page("page01")] }
            var path: [PortalRoute] = [tree, page("page01"), .sitePageHistory(siteId: siteId, page: current)]
            if screen == "site-page-revision", let older = decodedRevision(id: "revision-page01-2") {
                path.append(.sitePageRevision(siteId: siteId, pageId: "page01", revision: older, isCurrent: false))
            }
            return path
        default: return []
        }
    }

    /// What the server refuses on a screen, in its words, for the screens that show a failure.
    static func refusal(operation: String, screen: String?) -> String? {
        switch (operation, screen ?? "") {
        case ("ListPages", "site-pages-error"): "Pages could not be read just now. Try again in a moment."
        case ("ListPages", "site-pages-missing"), ("GetPage", "site-page-missing"): "not found"
        default: nil
        }
    }

    // MARK: data

    private struct State {
        var pages: [[String: Any]]
        var revisions: [[String: Any]]
        var createdCount = 0
    }

    private static func stamp(_ secondsAgo: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-secondsAgo))
    }

    private static let guideWords = """
        # Pick station operating guide

        This guide is for the people who run and look after the pick stations in the yard. It says what to check before a shift, how the station \
        behaves when it is working well, and what to do first when it is not. Read it once through, then keep it open on your phone while you work.

        ## Before the shift starts

        1. Walk the belt from the infeed to the pick area and look for anything lying on it.
        2. Check that the gripper is clean and that the foam pads are not worn through. The cleaning steps are in [Gripper cleaning](/site/site01/page/page04).
        3. Confirm that the light curtain at the front of the station shows green.
        4. Start the station from the controller and wait for the first box to be picked before you leave it.

        ![The pick station as the camera sees it](attachment:imagedemo02)

        ## What a good shift looks like

        | Measure | Normal | Call someone when |
        | --- | ---: | --- |
        | Picks per minute | 22 to 26 | Below 18 for ten minutes |
        | Dropped boxes | 0 to 2 per hour | More than 5 per hour |
        | Vacuum pressure | 62 to 70 kPa | Below 55 kPa |
        | Cycle time | 2.3 to 2.7 s | Above 3.2 s |

        The numbers come from the station screen. They are a guide to what is normal at this yard, not a promise: a tray of small boxes is slower \
        than a tray of large ones.

        ## When something goes wrong

        - If the station stops with an alarm, read the alarm text first. Most alarms say what to do.
        - If boxes are dropped, check the pads, then the vacuum pressure, then the box size setting.
        - If the belt is jammed, stop the station from the controller before you reach in. Never reach in with the station running.

        > Safety comes before throughput. A station that is stopped for five minutes costs less than a hand that is hurt. The rules are on the \
        [Safety rules](/site/site01/page/page02) page.

        ## Restarting after a stop

        ```
        1. Clear the area and check the light curtain.
        2. Acknowledge the alarm on the controller.
        3. Start the station and watch the first three picks.
        ```

        ## Shift handover

        Write down anything the next shift should know: a pad that is nearly worn, a tray type that is giving trouble, an alarm that came back. \
        Leave the notes where the next team lead will see them first.

        ## Who to call

        The yard team lead is the first call for anything on the floor. For anything the lead cannot fix, open a ticket from this app and say which \
        station and what you saw. Include a photo when you can.

        ## Keeping this guide current

        If something here is wrong or missing, tell the person who edits the pages, or change it yourself if you can. A guide that is out of date \
        is worse than none.
        """

    private static func initialState() -> State {
        func page(
            _ id: String, parent: String?, position: Int, title: String, icon: String?, isPublished: Bool = true, draftContent: String = "",
            modifiedSecondsAgo: TimeInterval
        ) -> [String: Any] {
            [
                "id": id, "createdAt": stamp(modifiedSecondsAgo + 864_000), "modifiedAt": stamp(modifiedSecondsAgo), "organizationId": "organization01",
                "siteId": siteId, "parentPageId": parent.map { $0 as Any } ?? NSNull(), "position": position,
                "currentRevisionId": isPublished ? "revision-\(id)-1" : NSNull(), "createdByUserId": "user02", "modifiedByUserId": "user02",
                "deletedAt": NSNull(), "title": title, "icon": icon.map { $0 as Any } ?? NSNull(), "isPublished": isPublished, "draftTitle": title,
                "draftContent": draftContent, "draftSummary": "", "draftModifiedAt": stamp(modifiedSecondsAgo), "draftModifiedByUserId": "user02",
            ]
        }
        var pages: [[String: Any]] = [
            page("page01", parent: nil, position: 0, title: "Pick station operating guide", icon: "\u{1F4D8}", draftContent: guideWords, modifiedSecondsAgo: 7_200),
            page("page02", parent: nil, position: 1, title: "Safety rules", icon: nil, draftContent: safetyWords, modifiedSecondsAgo: 172_800),
            page("page03", parent: "page01", position: 0, title: "Daily start-up checklist", icon: nil, draftContent: checklistWords, modifiedSecondsAgo: 90_000),
            page("page04", parent: "page03", position: 0, title: "Gripper cleaning", icon: "\u{1F9FD}", draftContent: cleaningWords, modifiedSecondsAgo: 400_000),
            page("page05", parent: nil, position: 2, title: "Shift handover notes", icon: nil, isPublished: false, draftContent: handoverWords, modifiedSecondsAgo: 1_800),
            page("page06", parent: nil, position: 3, title: "Reference sheet", icon: nil, draftContent: "Spare parts, contacts and the layout drawing live here.", modifiedSecondsAgo: 2_000_000),
        ]
        // The words of a published page are those of its revisions; the draft mirrors the last one.
        var revisions: [[String: Any]] = []
        func revision(_ pageId: String, _ number: Int, _ title: String, _ content: String, _ summary: String, secondsAgo: TimeInterval) -> [String: Any] {
            [
                "id": "revision-\(pageId)-\(number)", "createdAt": stamp(secondsAgo), "pageId": pageId, "organizationId": "organization01", "revisionNumber": number,
                "title": title, "content": content, "summary": summary, "authorUserId": number == 1 ? "user02" : "user03",
            ]
        }
        for entry in pages where entry["isPublished"] as? Bool == true {
            let id = entry["id"] as? String ?? ""
            revisions.append(revision(id, 1, entry["title"] as? String ?? "", entry["draftContent"] as? String ?? "", "", secondsAgo: 1_000_000))
        }
        // The guide has been published three times; the first two are shorter.
        revisions.removeAll { $0["pageId"] as? String == "page01" }
        revisions += [
            revision("page01", 1, "Pick station guide", "# Pick station guide\n\nCheck the belt, the gripper and the light curtain before you start.", "First version", secondsAgo: 2_000_000),
            revision(
                "page01", 2, "Pick station operating guide", "# Pick station operating guide\n\nCheck the belt, the gripper and the light curtain before you start.\n\n## When something goes wrong\n\n- Read the alarm text first.\n- Stop the station before you reach in.",
                "Added what to do when something goes wrong", secondsAgo: 900_000),
            revision("page01", 3, "Pick station operating guide", guideWords, "Added the measures and the restart steps", secondsAgo: 7_200),
        ]
        pages = pages.map { entry in
            var changed = entry
            if entry["id"] as? String == "page01" { changed["currentRevisionId"] = "revision-page01-3" }
            return changed
        }
        return State(pages: pages, revisions: revisions)
    }

    private static let safetyWords = """
        # Safety rules

        - Stop the station from the controller before you reach into it.
        - Keep the area in front of the light curtain clear.
        - Report a damaged guard at once. Do not run the station without it.
        """

    private static let checklistWords = """
        ## Daily start-up checklist

        - [ ] Belt clear
        - [ ] Gripper clean
        - [ ] Light curtain green
        - [ ] First pick watched
        """

    private static let cleaningWords = """
        ## Gripper cleaning

        Wipe the pads with a damp cloth once a day. Replace a pad when the foam shows through. Never use solvent: it softens the foam.
        """

    private static let handoverWords = """
        ## Shift handover notes

        Pad on station 3 is nearly worn. The small-box tray is slower than usual. No alarms came back overnight.
        """

    private static let state = DemoLocked(initialState())

    // MARK: answers

    private static func withCapabilities(_ row: [String: Any], screen: String?) -> [String: Any] {
        var changed = row
        changed["viewerCapabilities"] = capabilities(screen: screen)
        return changed
    }

    /// The row of a page in a list: no words, which a list does not ask for.
    private static func listRow(_ row: [String: Any], screen: String?) -> [String: Any] {
        var changed = withCapabilities(row, screen: screen)
        for key in ["draftContent", "draftSummary", "draftModifiedAt", "draftModifiedByUserId", "createdAt", "createdByUserId", "modifiedByUserId", "deletedAt"] {
            changed.removeValue(forKey: key)
        }
        return changed
    }

    static func respond(operation: String, variables: [String: Any], screen: String?) -> [String: Any]? {
        guard owns(screen) else { return nil }
        switch operation {
        case "GetSite":
            return ["GetSite": ["id": siteId, "name": siteName, "organizationId": "organization01", "viewerCapabilities": capabilities(screen: screen)]]
        case "ListPages":
            let isEmptySite = screen == "site-pages-empty" || (variables["siteId"] as? String) != siteId
            let pages: [[String: Any]] = isEmptySite ? [] : state.withValue { $0.pages }
            let options = variables["options"] as? [String: Any] ?? [:]
            let offset = options["after"] as? Int ?? 0
            let shown = Array(pages.dropFirst(offset)).map { listRow($0, screen: screen) }
            return ["ListPages": ["pages": shown, "meta": ["totalCount": pages.count]]]
        case "GetPage":
            let row = state.withValue { $0.pages.first { $0["id"] as? String == variables["pageId"] as? String } }
            return ["GetPage": row.map { withCapabilities($0, screen: screen) as Any } ?? NSNull()]
        case "GetPageRevision":
            let row = state.withValue { $0.revisions.first { $0["id"] as? String == variables["pageRevisionId"] as? String } }
            return ["GetPageRevision": row.map { $0 as Any } ?? NSNull()]
        case "ListPageRevisions":
            let rows = state.withValue { $0.revisions.filter { $0["pageId"] as? String == variables["pageId"] as? String } }
            return ["ListPageRevisions": rows]
        case "CreatePage":
            return ["CreatePage": ["page": create(variables)]]
        case "ModifyPage":
            return ["ModifyPage": ["page": change(variables, isPublishing: false)]]
        case "PublishPage":
            return ["PublishPage": ["page": change(variables, isPublishing: true)]]
        default:
            return nil
        }
    }

    /// Makes a draft page, as the server does: the title and words are the draft's, and nothing is published.
    private static func create(_ variables: [String: Any]) -> [String: Any] {
        state.withValue { current in
            current.createdCount += 1
            let title = variables["title"] as? String ?? ""
            let row: [String: Any] = [
                "id": "page-new-\(current.createdCount)", "createdAt": stamp(0), "modifiedAt": stamp(0), "organizationId": "organization01", "siteId": siteId,
                "parentPageId": (variables["parentPageId"] as? String).map { $0 as Any } ?? NSNull(), "position": variables["position"] as? Int ?? 0,
                "currentRevisionId": NSNull(), "createdByUserId": "user01", "modifiedByUserId": "user01", "deletedAt": NSNull(), "title": title,
                "icon": "", "isPublished": false, "draftTitle": title, "draftContent": variables["content"] as? String ?? "", "draftSummary": "",
                "draftModifiedAt": stamp(0), "draftModifiedByUserId": "user01",
            ]
            current.pages.append(row)
            return row
        }
    }

    /// Saves the draft, and with a publish makes it a new revision, as the server does. The answer to a save carries the draft title in
    /// `title`, and that to a publish the published one.
    private static func change(_ variables: [String: Any], isPublishing: Bool) -> [String: Any] {
        state.withValue { current in
            guard let index = current.pages.firstIndex(where: { $0["id"] as? String == variables["pageId"] as? String }) else { return [:] }
            var row = current.pages[index]
            if let title = variables["title"] as? String { row["draftTitle"] = title }
            if let content = variables["content"] as? String { row["draftContent"] = content }
            if let summary = variables["summary"] as? String { row["draftSummary"] = summary }
            row["modifiedAt"] = stamp(0)
            row["draftModifiedAt"] = stamp(0)
            if isPublishing {
                let pageId = row["id"] as? String ?? ""
                let number = current.revisions.filter { $0["pageId"] as? String == pageId }.count + 1
                let revisionId = "revision-\(pageId)-\(number)"
                current.revisions.append([
                    "id": revisionId, "createdAt": stamp(0), "pageId": pageId, "organizationId": "organization01", "revisionNumber": number,
                    "title": row["draftTitle"] as? String ?? "", "content": row["draftContent"] as? String ?? "", "summary": row["draftSummary"] as? String ?? "",
                    "authorUserId": "user01",
                ])
                row["currentRevisionId"] = revisionId
                row["isPublished"] = true
                row["title"] = row["draftTitle"]
                row["draftSummary"] = ""
                current.pages[index] = row
                return row
            }
            current.pages[index] = row
            // The stored title stays the published one; the answer to a save says the draft's.
            var answer = row
            answer["title"] = row["draftTitle"]
            return answer
        }
    }

    // MARK: decoding for the screens that start deep

    static func decodedPage(id: String) -> SitePage? {
        let row = state.withValue { $0.pages.first { $0["id"] as? String == id } }
        guard let row, let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
        return try? JSONDecoder().decode(SitePage.self, from: data)
    }

    static func decodedRevision(id: String) -> SitePageRevision? {
        let row = state.withValue { $0.revisions.first { $0["id"] as? String == id } }
        guard let row, let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
        return try? JSONDecoder().decode(SitePageRevision.self, from: data)
    }
}
