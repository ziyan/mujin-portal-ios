import UIKit
import XCTest

/// Pastes from the system clipboard into the message boxes that take attachments, in demo mode. A picture on the
/// clipboard must become an attachment chip at once, with or without the text a browser or Photos puts beside it.
@MainActor
final class PasteTests: XCTestCase {
    private static let address = "https://images.example.com/photos/pallet.png"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func pictureData(color: UIColor) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        return image.pngData() ?? Data()
    }

    /// One clipboard item the way a browser or Photos writes it: the picture, and its address as a link and as text.
    private func pictureItem(color: UIColor, extra: [String: Any] = [:]) -> [String: Any] {
        var item: [String: Any] = ["public.png": pictureData(color: color)]
        item.merge(extra) { _, new in new }
        return item
    }

    private func paste(into screen: String, field fieldIdentifier: String, items: [[String: Any]]) -> (app: XCUIApplication, field: XCUIElement) {
        UIPasteboard.general.setItems(items, options: [:])
        let app = DemoApp.launch(screen: screen)
        let field = DemoApp.element(app, fieldIdentifier)
        XCTAssertTrue(field.waitForExistence(timeout: 45), "The message box never appeared")
        field.tap()
        field.press(forDuration: 1.0)
        let pasteItem = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Paste")).firstMatch
        XCTAssertTrue(pasteItem.waitForExistence(timeout: 15), "The Paste menu did not appear")
        pasteItem.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        return (app, field)
    }

    private func pastedPictures(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Pasted picture"))
    }

    private func text(of field: XCUIElement) -> String {
        (field.value as? String) ?? ""
    }

    func testPicturePastesAsAttachmentInAChat() {
        let (app, field) = paste(into: "chat-reply", field: "chatMessageField", items: [pictureItem(color: .systemTeal)])
        XCTAssertTrue(pastedPictures(in: app).firstMatch.waitForExistence(timeout: 20), "No attachment appeared")
        XCTAssertEqual(text(of: field), "", "Nothing should have been typed")
    }

    func testPictureWithItsAddressAttachesAndTypesNothing() {
        let extra: [String: Any] = ["public.url": URL(string: Self.address)!, "public.utf8-plain-text": Self.address]
        let (app, field) = paste(into: "chat-reply", field: "chatMessageField", items: [pictureItem(color: .systemOrange, extra: extra)])
        XCTAssertTrue(pastedPictures(in: app).firstMatch.waitForExistence(timeout: 20), "No attachment appeared")
        XCTAssertEqual(text(of: field), "", "The picture's own address should not be typed")
    }

    func testPictureWithASentenceKeepsTheSentence() {
        let sentence = "The label on this pallet is torn, can you check it?"
        let (app, field) = paste(into: "chat-reply", field: "chatMessageField", items: [pictureItem(color: .systemPink, extra: ["public.utf8-plain-text": sentence])])
        XCTAssertTrue(pastedPictures(in: app).firstMatch.waitForExistence(timeout: 20), "No attachment appeared")
        XCTAssertEqual(text(of: field), sentence)
    }

    func testTwoPicturesBecomeTwoAttachments() {
        let (app, _) = paste(into: "chat-reply", field: "chatMessageField", items: [pictureItem(color: .systemRed), pictureItem(color: .systemGreen)])
        XCTAssertTrue(pastedPictures(in: app).element(boundBy: 1).waitForExistence(timeout: 20), "Two attachments should have appeared")
    }

    func testPicturePastesAsAttachmentInTheAssistantConversation() {
        let (app, field) = paste(into: "conversation-reply", field: "messageField", items: [pictureItem(color: .systemIndigo)])
        XCTAssertTrue(pastedPictures(in: app).firstMatch.waitForExistence(timeout: 20), "No attachment appeared")
        XCTAssertEqual(text(of: field), "")
    }
}
