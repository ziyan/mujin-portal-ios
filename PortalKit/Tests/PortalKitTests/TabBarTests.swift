import Foundation
import Testing

@testable import PortalKit

@Suite struct TabBarTests {
    @Test func theDefaultBarIsChatSitesAndTicketsAndSurveillanceIsLeftToMoreAndSearch() {
        #expect(TabBar.defaults(persona: .customer, hasCameras: true) == [.assistant, .site, .tickets])
        #expect(TabBar.tabs(saved: nil, persona: .customer, hasCameras: true) == [.assistant, .site, .tickets, .more, .search])
        #expect(TabBar.defaults(persona: .staff, hasCameras: true) == [.assistant, .tickets, .site])
    }

    @Test func theDefaultDoesNotDependOnCameras() {
        #expect(TabBar.tabs(saved: nil, persona: .customer, hasCameras: false) == TabBar.tabs(saved: nil, persona: .customer, hasCameras: true))
        #expect(TabBar.tabs(saved: nil, persona: .staff, hasCameras: false) == Navigation.sections(for: .staff).filter { $0 != .more } + [.more, .search])
    }

    @Test func searchIsAlwaysLastAndMoreIsRightBeforeIt() {
        for saved in [nil, [], ["goals"], ["site", "tickets", "goals", "ideas"]] as [[String]?] {
            let tabs = TabBar.tabs(saved: saved, persona: .customer, hasCameras: true)
            #expect(Array(tabs.suffix(2)) == [.more, .search])
            #expect(tabs.count <= 5)
        }
    }

    @Test func aChoiceKeepsItsOrderAndMoreAndSearchStayLast() {
        let saved = ["settings", "releases"]
        #expect(TabBar.tabs(saved: saved, persona: .customer, hasCameras: true) == [.assistant, .settings, .releases, .more, .search])
    }

    @Test func aChoiceHoldsThreeAtMostAndChatIsOneOfThem() {
        let saved = ["site", "tickets", "goals", "ideas", "releases"]
        let bar = TabBar.resolve(saved: saved, persona: .customer, hasCameras: true)
        #expect(bar == [.assistant, .site, .tickets])
        #expect(bar.count == TabBar.capacity)
    }

    @Test func aPersonWhoChoseSurveillanceKeepsItEvenWhenTheBarHasShrunk() {
        // The bar used to hold four sections, so this choice had three besides Chat.
        let saved = ["site", "tickets", "surveillance"]
        #expect(TabBar.resolve(saved: saved, persona: .customer, hasCameras: true) == [.assistant, .site, .surveillance])
        #expect(TabBar.resolve(saved: ["surveillance", "site", "tickets"], persona: .customer, hasCameras: true) == [.assistant, .surveillance, .site])
        #expect(TabBar.resolve(saved: ["site", "surveillance"], persona: .customer, hasCameras: true) == [.assistant, .site, .surveillance])
    }

    @Test func surveillanceIsStillDroppedForAPersonWithoutCameras() {
        #expect(TabBar.resolve(saved: ["site", "tickets", "surveillance"], persona: .customer, hasCameras: false) == [.assistant, .site, .tickets])
    }

    @Test func aChoiceThatFitsIsNotChanged() {
        #expect(TabBar.resolve(saved: ["goals", "site"], persona: .customer, hasCameras: true) == [.assistant, .goals, .site])
        #expect(TabBar.resolve(saved: ["tickets"], persona: .customer, hasCameras: true) == [.assistant, .tickets])
    }

    @Test func messagesStaysFirstWhateverWasSaved() {
        #expect(TabBar.resolve(saved: ["goals", "assistant", "site"], persona: .customer, hasCameras: true) == [.assistant, .goals, .site])
        #expect(TabBar.tabs(saved: [], persona: .customer, hasCameras: true) == [.assistant, .more, .search])
    }

    @Test func aSectionThatIsNotAllowedIsDroppedAndTheDefaultsFillTheSlot() {
        // Surveillance without cameras, Incidents for a customer, and a name from a newer app.
        let saved = ["goals", "surveillance", "incidents", "future"]
        #expect(TabBar.resolve(saved: saved, persona: .customer, hasCameras: false) == [.assistant, .goals, .site])
    }

    @Test func aDroppedSectionDoesNotRefillTheSlotsThePersonLeftEmpty() {
        #expect(TabBar.resolve(saved: ["goals", "surveillance"], persona: .customer, hasCameras: false) == [.assistant, .goals, .site])
        #expect(TabBar.resolve(saved: ["surveillance"], persona: .customer, hasCameras: false) == [.assistant, .site])
    }

    @Test func aRepeatedSectionCountsOnce() {
        #expect(TabBar.resolve(saved: ["goals", "goals"], persona: .customer, hasCameras: true) == [.assistant, .goals, .site])
    }

    @Test func moreSearchAndChatsCannotBeChosen() {
        #expect(TabBar.resolve(saved: ["more", "chats", "search", "goals"], persona: .customer, hasCameras: true) == [.assistant, .goals, .site])
        #expect(!TabBar.choosable(persona: .staff, hasCameras: true).contains(.more))
        #expect(!TabBar.choosable(persona: .staff, hasCameras: true).contains(.search))
    }

    @Test func onlyStaffAndPeopleWithCamerasAreOfferedIncidentsAndSurveillance() {
        #expect(TabBar.choosable(persona: .staff, hasCameras: false).contains(.incidents))
        #expect(!TabBar.choosable(persona: .customer, hasCameras: true).contains(.incidents))
        #expect(!TabBar.choosable(persona: .staff, hasCameras: false).contains(.surveillance))
        #expect(TabBar.choosable(persona: .customer, hasCameras: true).contains(.surveillance))
    }

    @Test func theStoreKeepsOneChoicePerAccountAndResetBringsTheDefaultsBack() throws {
        let suite = "TabBarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TabBarStore(defaults: defaults)
        store.save(["goals"], accountKey: "server-one|user01")
        #expect(store.load(accountKey: "server-one|user01") == ["goals"])
        #expect(store.load(accountKey: "server-two|user01") == nil)
        store.save(nil, accountKey: "server-one|user01")
        #expect(TabBar.resolve(saved: store.load(accountKey: "server-one|user01"), persona: .customer, hasCameras: true) == TabBar.defaults(persona: .customer, hasCameras: true))
    }
}
