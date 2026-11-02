import Foundation
import Testing

@testable import PortalKit

@Suite struct TabBarTests {
    @Test func customersDefaultToChatSitesSurveillanceTickets() {
        #expect(TabBar.defaults(persona: .customer, hasCameras: true) == [.assistant, .site, .surveillance, .tickets])
        #expect(TabBar.tabs(saved: nil, persona: .customer, hasCameras: true) == [.assistant, .site, .surveillance, .tickets, .more])
    }

    @Test func staffDefaultKeepsTheirOrderAndAddsSurveillanceAfterSites() {
        #expect(TabBar.defaults(persona: .staff, hasCameras: true) == [.assistant, .tickets, .site, .surveillance])
    }

    @Test func withoutCamerasTheDefaultStaysAsItWas() {
        #expect(TabBar.tabs(saved: nil, persona: .customer, hasCameras: false) == Navigation.sections(for: .customer))
        #expect(TabBar.tabs(saved: nil, persona: .staff, hasCameras: false) == Navigation.sections(for: .staff))
    }

    @Test func aChoiceKeepsItsOrderAndMoreStaysLast() {
        let saved = ["settings", "releases"]
        #expect(TabBar.tabs(saved: saved, persona: .customer, hasCameras: true) == [.assistant, .settings, .releases, .more])
    }

    @Test func aChoiceHoldsFourAtMostAndChatIsOneOfThem() {
        let saved = ["site", "tickets", "goals", "ideas", "releases"]
        let bar = TabBar.resolve(saved: saved, persona: .customer, hasCameras: true)
        #expect(bar == [.assistant, .site, .tickets, .goals])
        #expect(bar.count == TabBar.capacity)
    }

    @Test func messagesStaysFirstWhateverWasSaved() {
        #expect(TabBar.resolve(saved: ["goals", "assistant", "site"], persona: .customer, hasCameras: true) == [.assistant, .goals, .site])
        #expect(TabBar.tabs(saved: [], persona: .customer, hasCameras: true) == [.assistant, .more])
    }

    @Test func aSectionThatIsNotAllowedIsDroppedAndTheDefaultsFillTheSlot() {
        // Surveillance without cameras, Incidents for a customer, and a name from a newer app.
        let saved = ["goals", "surveillance", "incidents", "future"]
        #expect(TabBar.resolve(saved: saved, persona: .customer, hasCameras: false) == [.assistant, .goals, .site, .tickets])
    }

    @Test func aDroppedSectionDoesNotRefillTheSlotsThePersonLeftEmpty() {
        #expect(TabBar.resolve(saved: ["goals", "surveillance"], persona: .customer, hasCameras: false) == [.assistant, .goals, .site])
    }

    @Test func aRepeatedSectionCountsOnce() {
        #expect(TabBar.resolve(saved: ["goals", "goals"], persona: .customer, hasCameras: true) == [.assistant, .goals, .site])
    }

    @Test func moreAndChatsCannotBeChosen() {
        #expect(TabBar.resolve(saved: ["more", "chats", "goals"], persona: .customer, hasCameras: true) == [.assistant, .goals, .site, .surveillance])
        #expect(!TabBar.choosable(persona: .staff, hasCameras: true).contains(.more))
    }

    @Test func onlyStaffAndPeopleWithCamerasAreOfferedIncidentsAndSurveillance() {
        #expect(TabBar.choosable(persona: .staff, hasCameras: false).contains(.incidents))
        #expect(!TabBar.choosable(persona: .customer, hasCameras: true).contains(.incidents))
        #expect(!TabBar.choosable(persona: .staff, hasCameras: false).contains(.surveillance))
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
