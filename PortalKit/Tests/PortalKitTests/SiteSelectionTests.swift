import Foundation
import Testing

@testable import PortalKit

@Suite struct SiteSelectionTests {
    @Test func reloadingKeepsTheCurrentSiteWhileItIsListed() {
        #expect(SiteSelection.resolve(current: "site02", remembered: "site03", availableIds: ["site01", "site02", "site03"]) == "site02")
    }

    @Test func aRememberedSiteIsRestoredWhenNothingIsSelected() {
        #expect(SiteSelection.resolve(current: nil, remembered: "site02", availableIds: ["site01", "site02"]) == "site02")
    }

    @Test func theFirstSiteIsPickedOnlyWhenNothingElseApplies() {
        #expect(SiteSelection.resolve(current: nil, remembered: nil, availableIds: ["site01", "site02"]) == "site01")
        #expect(SiteSelection.resolve(current: "gone", remembered: "also-gone", availableIds: ["site01"]) == "site01")
        #expect(SiteSelection.resolve(current: nil, remembered: nil, availableIds: []) == nil)
    }

    @Test func theChoiceIsRememberedPerAccountAndScope() throws {
        let suite = "site-selection-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SiteSelectionStore(defaults: defaults)
        store.save("site02", accountKey: "account01", organizationKey: "")
        store.save("site05", accountKey: "account01", organizationKey: "organization02")
        #expect(store.load(accountKey: "account01", organizationKey: "") == "site02")
        #expect(store.load(accountKey: "account01", organizationKey: "organization02") == "site05")
        #expect(store.load(accountKey: "account02", organizationKey: "") == nil)
    }
}
