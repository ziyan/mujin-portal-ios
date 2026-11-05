import Foundation
import Testing

@testable import PortalKit

@Suite struct AppUpdateTests {
    private let installed = InstalledApp(version: "1.0", build: 300)

    private func feed(_ text: String) -> Data { Data(text.utf8) }

    @Test func aNewerTestFlightBuildIsAnUpdateEvenOfTheSameVersion() {
        let update = AppUpdateSource.update(channel: .testFlight, answer: feed(#"{"version":"1.0","build":310}"#), installed: installed)
        #expect(update == AppUpdate(channel: .testFlight, version: "1.0", build: 310))
        #expect(update?.versionText == "1.0 (310)")
    }

    @Test func theSameOrAnOlderTestFlightBuildIsNot() {
        #expect(AppUpdateSource.update(channel: .testFlight, answer: feed(#"{"version":"1.0","build":300}"#), installed: installed) == nil)
        #expect(AppUpdateSource.update(channel: .testFlight, answer: feed(#"{"version":"1.0","build":299}"#), installed: installed) == nil)
    }

    @Test func anAnswerThatSaysNothingUsableIsNoUpdate() {
        for text in ["", "not json", "{}", #"{"version":"1.0"}"#, #"{"version":"1.0","build":"310"}"#, #"{"results":[]}"#] {
            #expect(AppUpdateSource.update(channel: .testFlight, answer: feed(text), installed: installed) == nil)
            #expect(AppUpdateSource.update(channel: .appStore, answer: feed(text), installed: installed) == nil)
        }
    }

    @Test func theAppStoreComparesVersionsAndHasNoBuild() {
        let newer = AppUpdateSource.update(channel: .appStore, answer: feed(#"{"resultCount":1,"results":[{"version":"1.1"}]}"#), installed: installed)
        #expect(newer == AppUpdate(channel: .appStore, version: "1.1"))
        #expect(newer?.versionText == "1.1")
        #expect(AppUpdateSource.update(channel: .appStore, answer: feed(#"{"results":[{"version":"1.0"}]}"#), installed: installed) == nil)
    }

    @Test func versionsCompareByNumberAndNotByText() {
        #expect(AppUpdateSource.isVersion("1.10", newerThan: "1.9"))
        #expect(!AppUpdateSource.isVersion("1.9", newerThan: "1.10"))
        #expect(AppUpdateSource.isVersion("2", newerThan: "1.9.9"))
        #expect(!AppUpdateSource.isVersion("1.0", newerThan: "1.0.0"))
        #expect(!AppUpdateSource.isVersion("1.0.0", newerThan: "1.0"))
    }

    @Test func eachChannelInstallsFromItsOwnPlace() {
        #expect(AppUpdate(channel: .testFlight, version: "1.0", build: 310).installUrl.host == "testflight.apple.com")
        #expect(AppUpdate(channel: .appStore, version: "1.1").installUrl.host == "apps.apple.com")
    }

    @Test func eachChannelAsksItsOwnSource() {
        #expect(AppUpdateSource.requestUrl(channel: .testFlight, bundleIdentifier: nil, region: nil)?.lastPathComponent == "testflight.json")
        let lookup = AppUpdateSource.requestUrl(channel: .appStore, bundleIdentifier: "com.example.app", region: "JP")
        #expect(lookup?.absoluteString == "https://itunes.apple.com/lookup?bundleId=com.example.app&country=JP")
        #expect(AppUpdateSource.requestUrl(channel: .appStore, bundleIdentifier: "", region: "JP") == nil)
    }

    @Test func aDismissalCoversThatUpdateAloneAndOutlivesTheModel() throws {
        let name = "AppUpdateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let update = AppUpdate(channel: .testFlight, version: "1.0", build: 310)
        #expect(!AppUpdateDismissal.isDismissed(update, in: defaults))
        AppUpdateDismissal.dismiss(update, in: defaults)
        #expect(AppUpdateDismissal.isDismissed(AppUpdate(channel: .testFlight, version: "1.0", build: 310), in: defaults))
        #expect(!AppUpdateDismissal.isDismissed(AppUpdate(channel: .testFlight, version: "1.0", build: 311), in: defaults))
        #expect(!AppUpdateDismissal.isDismissed(AppUpdate(channel: .appStore, version: "1.0"), in: defaults))
    }

    @Test func theInstalledAppIsReadFromTheBundle() {
        #expect(InstalledApp(infoDictionary: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "300"]) == installed)
        #expect(InstalledApp(infoDictionary: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "dev"]) == nil)
        #expect(InstalledApp(infoDictionary: nil) == nil)
    }
}
