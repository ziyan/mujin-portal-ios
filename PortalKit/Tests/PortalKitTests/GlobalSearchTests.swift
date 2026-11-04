import Foundation
import Testing

@testable import PortalKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite struct GlobalSearchTests {
    func result(_ kind: GlobalSearchResultKind, _ id: String, title: String = "Title", path: String = "/x") -> GlobalSearchResult {
        GlobalSearchResult(resultKind: kind, id: id, title: title, path: path)
    }

    @Test func theQueryIsTheOneTheWebPaletteSends() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            #expect(operation == "GlobalSearch")
            return [
                "GlobalSearch": [
                    "results": [
                        [
                            "resultKind": "shortcut", "id": "settings.notifications", "title": "Notification preferences", "subtitle": "Account",
                            "path": "/settings/notifications", "iconName": "notifications", "organizationId": NSNull(), "organizationName": NSNull(),
                        ],
                        [
                            "resultKind": "controller", "id": "controller01", "title": "controller01", "subtitle": "Example Yard",
                            "path": "/controller/controller01", "iconName": NSNull(), "organizationId": "organization02", "organizationName": "Example Freight",
                        ],
                    ]
                ]
            ]
        }
        let rows = try await connection.globalSearch(query: "  controller01 ")
        #expect(rows.map(\.id) == ["settings.notifications", "controller01"])
        #expect(rows[0].iconName == "notifications")
        #expect(rows[0].foreignOrganizationName == nil)
        #expect(rows[1].foreignOrganizationName == "Example Freight")
        #expect(rows[1].organizationId == "organization02")
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["query"] as? String == "controller01")
        #expect((variables["limit"] as? NSNumber)?.intValue == 30)
    }

    @Test func aRowOfAKindThisAppDoesNotKnowIsLeftOut() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "GlobalSearch": [
                    "results": [
                        ["resultKind": "hologram", "id": "h1", "title": "A hologram", "subtitle": "", "path": "/hologram/h1"],
                        ["resultKind": "ticket", "id": "12", "title": "Gripper drops boxes", "path": "/ticket/12"],
                    ]
                ]
            ]
        }
        let rows = try await connection.globalSearch(query: "gripper")
        #expect(rows.map(\.id) == ["12"])
        #expect(rows[0].subtitle == "")
    }

    @Test func anEmptyAnswerIsNoRows() async throws {
        let (connection, _) = scriptedConnection { _, _ in ["GlobalSearch": ["results": []]] }
        #expect(try await connection.globalSearch(query: "zzz").isEmpty)
        let (nothing, _) = scriptedConnection { _, _ in ["GlobalSearch": NSNull()] }
        #expect(try await nothing.globalSearch(query: "zzz").isEmpty)
    }

    @Test func resultsAreGroupedInTheServersOrder() {
        let rows = [
            result(.ticket, "12"), result(.controller, "controller01"), result(.shortcut, "settings.tokens"), result(.ticket, "13"),
            result(.directChat, "chatconv01"), result(.groupChat, "chatconv02"), result(.shortcut, "settings.vpn"),
        ]
        let sections = GlobalSearchRules.sections(rows)
        #expect(sections.map(\.group) == [.ticket, .controller, .shortcut, .chat])
        #expect(sections[2].results.map(\.id) == ["settings.tokens", "settings.vpn"])
        #expect(sections[0].results.map(\.id) == ["12", "13"])
        #expect(sections[3].results.map(\.id) == ["chatconv01", "chatconv02"])
    }

    @Test func withoutShortcutsTheBestRowDecidesWhichGroupLeads() {
        let sections = GlobalSearchRules.sections([result(.site, "site01"), result(.ticket, "12"), result(.site, "site02")])
        #expect(sections.map(\.group) == [.site, .ticket])
    }

    @Test func aRowTheServerSentTwiceIsShownOnce() {
        let sections = GlobalSearchRules.sections([result(.ticket, "12"), result(.ticket, "12"), result(.release, "12")])
        #expect(sections.map(\.group) == [.ticket, .release])
        #expect(sections[0].results.count == 1)
    }

    @Test func noRowsMakeNoSections() {
        #expect(GlobalSearchRules.sections([]).isEmpty)
    }

    @Test func everyKindHasAGroupWithTheWebsHeading() {
        for kind in GlobalSearchResultKind.allCases { #expect(!GlobalSearchGroup(kind: kind).title.isEmpty) }
        #expect(GlobalSearchGroup(kind: .shortcut).title == "Go to")
        #expect(GlobalSearchGroup(kind: .groupChat).title == "Chats")
        #expect(GlobalSearchGroup(kind: .conversation).title == "Assistant conversations")
        #expect(Set(GlobalSearchResultKind.allCases.map { GlobalSearchGroup(kind: $0) }) == Set(GlobalSearchGroup.allCases))
    }

    @Test func aQueryNeedsTwoCharactersAfterTrimming() {
        #expect(!GlobalSearchRules.isSearching(""))
        #expect(!GlobalSearchRules.isSearching("  a "))
        #expect(GlobalSearchRules.isSearching(" ab"))
        #expect(GlobalSearchRules.normalized("\n set \t") == "set")
    }

    @Test func aFailureIsSortedIntoWhatTheScreenSays() {
        #expect(GlobalSearchFailure.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(GlobalSearchFailure.classify(URLError(.timedOut)) == .offline)
        #expect(GlobalSearchFailure.classify(PortalError.refused("Cannot query field \"GlobalSearch\" on type \"Query\".")) == .unavailable)
        #expect(GlobalSearchFailure.classify(PortalError.refused("Too many requests.")) == .other("Too many requests."))
        #expect(GlobalSearchFailure.classify(URLError(.badServerResponse)) != .offline)
    }

    @Test func theServerOffersSearchWhenItListsTheQueryOrWhenItsListCouldNotBeRead() {
        #expect(ServerCapabilities(queryNames: ["globalSearch", "listTickets"]).offersGlobalSearch)
        #expect(ServerCapabilities(queryNames: ["GlobalSearch"]).offersGlobalSearch)
        #expect(!ServerCapabilities(queryNames: ["listTickets"]).offersGlobalSearch)
        #expect(ServerCapabilities().offersGlobalSearch)
    }

    @Test func aRecentGoesToTheHeadOnceAndTheListHoldsFive() {
        var rows: [GlobalSearchResult] = []
        for index in 1...7 { rows = GlobalSearchRecents.adding(result(.ticket, "\(index)"), to: rows) }
        #expect(rows.map(\.id) == ["7", "6", "5", "4", "3"])
        rows = GlobalSearchRecents.adding(result(.ticket, "4"), to: rows)
        #expect(rows.map(\.id) == ["4", "7", "6", "5", "3"])
        rows = GlobalSearchRecents.adding(result(.release, "4"), to: rows)
        #expect(rows.map(\.rowKey) == ["release|4", "ticket|4", "ticket|7", "ticket|6", "ticket|5"])
    }

    @Test func theStoreKeepsOneListPerAccountAndSurvivesUnreadableData() throws {
        let suite = "GlobalSearchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlobalSearchRecents(defaults: defaults)
        store.remember(result(.ticket, "12", title: "Gripper drops boxes", path: "/ticket/12"), accountKey: "server-one|user01")
        store.remember(result(.controller, "controller01", path: "/controller/controller01"), accountKey: "server-one|user01")
        #expect(store.load(accountKey: "server-one|user01").map(\.id) == ["controller01", "12"])
        #expect(store.load(accountKey: "server-two|user01").isEmpty)
        defaults.set(Data("not json".utf8), forKey: "globalSearchRecents|server-three|user01")
        #expect(store.load(accountKey: "server-three|user01").isEmpty)
        store.clear(accountKey: "server-one|user01")
        #expect(store.load(accountKey: "server-one|user01").isEmpty)
    }

    @Test func aRememberedRowKeepsEveryField() throws {
        let suite = "GlobalSearchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlobalSearchRecents(defaults: defaults)
        let row = GlobalSearchResult(
            resultKind: .site, id: "site01", title: "Example Yard", subtitle: "Example Logistics", path: "/site/site01", iconName: nil,
            organizationId: "organization02", organizationName: "Example Freight")
        store.remember(row, accountKey: "key")
        #expect(store.load(accountKey: "key") == [row])
    }
}
