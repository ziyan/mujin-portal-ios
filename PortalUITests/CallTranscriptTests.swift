import XCTest

/// A chat's history holds a call without its words: they are read when the transcript is opened, with each recording.
@MainActor
final class CallTranscriptTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testShowingATranscriptReadsItsWordsAndRecordings() {
        let app = DemoApp.launch(screen: "chat-call-banner")
        let toggle = DemoApp.element(app, "callTranscriptToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 60), "A call with a transcript offers none.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.waitUntilHittable(toggle, timeout: 30), "The transcript cannot be opened.\n\(app.debugDescription)")
        toggle.tap()
        let recording = DemoApp.element(app, "callRecording-recording-sam")
        XCTAssertTrue(recording.waitForExistence(timeout: 30), "The recording did not show.\n\(app.debugDescription)")
        XCTAssertTrue(DemoApp.element(app, "callRecording-recording-alex").exists, "A person's recording is missing.\n\(app.debugDescription)")
        let words = NSPredicate(format: "label CONTAINS %@", "the scanner lost its connection")
        XCTAssertTrue(app.staticTexts.matching(words).firstMatch.waitForExistence(timeout: 10), "The words did not show.\n\(app.debugDescription)")
    }
}
