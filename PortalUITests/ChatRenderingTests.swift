import XCTest

/// Pictures every message of the chat rendering fixture (Fixtures/chat-rendering) and checks what each must show. The messages are
/// shown in light and dark, at the default text size and at the largest, and each picture is named `<key>-<appearance>-<size>.png`.
/// Pictures are written to the folder RENDERING_SHOTS_DIRECTORY names, when the run sets it, and attached to the result besides.
///
/// The fixture's checks are written for the web's page. Each is asserted here as what it means on the phone, under its own words,
/// so a failure names the broken check, the message and the look.
@MainActor
final class ChatRenderingTests: XCTestCase {
    private struct FixtureMessage {
        let key: String
        let surface: String
        let viewer: String
    }

    private struct Look {
        let appearance: XCUIDevice.Appearance
        let appearanceName: String
        let isLargestText: Bool
        var sizeName: String { isLargestText ? "largest" : "default" }
    }

    private static let looks = [
        Look(appearance: .light, appearanceName: "light", isLargestText: false), Look(appearance: .dark, appearanceName: "dark", isLargestText: false),
        Look(appearance: .light, appearanceName: "light", isLargestText: true), Look(appearance: .dark, appearanceName: "dark", isLargestText: true),
    ]

    private static let fixtureMessages: [FixtureMessage] = {
        guard let url = Bundle(for: ChatRenderingTests.self).url(forResource: "messages", withExtension: "json"),
            let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return (object["messages"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let key = entry["key"] as? String, let surface = entry["surface"] as? String else { return nil }
            return FixtureMessage(key: key, surface: surface, viewer: entry["viewer"] as? String ?? "customer")
        }
    }()

    override func setUp() async throws {
        // Every check of every message is reported, not only the first that fails.
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        XCUIDevice.shared.appearance = .light
    }

    func testTheChatMessagesAsTheCustomerReadsThem() {
        picture(screen: "rendering-chat", persona: nil, messages: Self.fixtureMessages.filter { $0.surface == "chat" && $0.viewer == "customer" })
    }

    func testTheInternalNoteAsStaffReadIt() {
        picture(screen: "rendering-chat-staff", persona: "staff", messages: Self.fixtureMessages.filter { $0.surface == "chat" && $0.viewer == "staff" })
    }

    func testTheAssistantMessages() {
        picture(screen: "rendering-assistant", persona: nil, messages: Self.fixtureMessages.filter { $0.surface == "assistant" })
    }

    // MARK: picturing

    private func picture(screen: String, persona: String?, messages: [FixtureMessage]) {
        XCTAssertFalse(messages.isEmpty, "The fixture lists no messages for \(screen).")
        for look in Self.looks {
            XCUIDevice.shared.appearance = look.appearance
            var arguments = ["-showToolCallDetails", "YES"]
            if look.isLargestText { arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            let app = DemoApp.launch(screen: screen, persona: persona, arguments: arguments)
            guard let last = messages.last, DemoApp.waitUntilExists(container(last.key, app), timeout: 90) else {
                XCTFail("[\(screen) \(look.appearanceName) \(look.sizeName)] the messages did not show.\n\(app.debugDescription)")
                app.terminate()
                continue
            }
            Thread.sleep(forTimeInterval: 2)
            // From the newest up, since the list opens at its end.
            for message in messages.reversed() {
                let name = "\(message.key)-\(look.appearanceName)-\(look.sizeName)"
                guard container(message.key, app).exists else {
                    XCTFail("[\(name)] the message is not on the screen.")
                    continue
                }
                reveal(message.key, app)
                waitForPictures(message.key, app)
                save(shot(message.key, app), name: name)
                check(message.key, look: name, app)
            }
            app.terminate()
        }
    }

    private func container(_ key: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "rendered-render-\(key)").firstMatch
    }

    /// The message and what belongs to it: its thread's replies, tool lines and artifact.
    private func parts(_ key: String, _ app: XCUIApplication) -> [XCUIElement] {
        let identifier = "rendered-render-\(key)"
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR identifier BEGINSWITH %@", identifier, identifier + "~")).allElementsBoundByIndex
    }

    private func frame(of key: String, _ app: XCUIApplication) -> CGRect {
        parts(key, app).map(\.frame).filter { !$0.isEmpty }.reduce(CGRect.null) { $0.union($1) }
    }

    /// The part of the window the messages show in: below the navigation bar and above the composer.
    private func visibleArea(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : window.minY + 100
        let field = app.textViews.firstMatch
        let bottom = field.exists && field.frame.minY > top + 100 ? field.frame.minY - 16 : window.maxY * 0.8
        return CGRect(x: window.minX, y: top, width: window.width, height: max(bottom - top, 100))
    }

    /// Scrolls until the message is wholly in view, or its top is when it is taller than the screen.
    private func reveal(_ key: String, _ app: XCUIApplication) {
        for _ in 0..<30 {
            let area = visibleArea(app)
            let message = frame(of: key, app)
            guard !message.isNull else { return }
            let wantedTop: CGFloat
            if message.height <= area.height - 16 {
                if message.minY >= area.minY + 4, message.maxY <= area.maxY - 4 { return }
                wantedTop = area.minY + (area.height - message.height) / 2
            } else {
                if abs(message.minY - (area.minY + 8)) < 8 { return }
                wantedTop = area.minY + 8
            }
            let distance = max(min(wantedTop - message.minY, area.height * 0.7), -area.height * 0.7)
            let startY = distance > 0 ? area.minY + 24 : area.maxY - 24
            let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: area.midX, dy: startY))
            let end = start.withOffset(CGVector(dx: 0, dy: distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(600), thenHoldForDuration: 0.3)
        }
    }

    /// Pictures load after the message: their boxes hold the room, and the picture is waited for so the shot shows it.
    private func waitForPictures(_ key: String, _ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            let loading = container(key, app).activityIndicators.count
            if loading == 0 { break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func shot(_ key: String, _ app: XCUIApplication) -> Data? {
        let area = visibleArea(app)
        let message = frame(of: key, app)
        guard !message.isNull else { return nil }
        let window = app.windows.firstMatch.frame
        let rect = CGRect(x: window.minX, y: message.minY - 6, width: window.width, height: message.height + 12).intersection(area)
        guard !rect.isNull, rect.height > 4 else { return nil }
        let image = XCUIScreen.main.screenshot().image
        let scale = image.scale
        guard let cropped = image.cgImage?.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
        else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up).pngData()
    }

    private func save(_ png: Data?, name: String) {
        guard let png else {
            XCTFail("[\(name)] no picture could be taken.")
            return
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["RENDERING_SHOTS_DIRECTORY"], !folder.isEmpty {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    // MARK: checks

    /// What a drawn message holds, read once.
    private struct Drawn {
        struct Element {
            let type: XCUIElement.ElementType
            let identifier: String
            let label: String
            let frame: CGRect
            /// Inside a table or code block, which scrolls sideways inside itself.
            let isInScroller: Bool
        }

        let elements: [Element]
        let window: CGRect

        func hasText(_ text: String) -> Bool { elements.contains { $0.label.contains(text) } }
        func hasLabel(_ label: String) -> Bool { elements.contains { $0.label == label } }
        func count(identifier: String) -> Int { elements.filter { $0.identifier == identifier }.count }
        func count(type: XCUIElement.ElementType) -> Int { elements.filter { $0.type == type }.count }
        func frame(ofLabel label: String) -> CGRect? { elements.first { $0.label == label }?.frame }
        func hasSizedButtons(named names: [String]) -> Bool {
            names.allSatisfy { name in elements.contains { $0.label == name && $0.frame.width > 20 && $0.frame.height > 20 } }
        }

        /// Nothing reaches past the window's edges, apart from tables and code, which scroll inside themselves.
        var hasNoOverflow: Bool {
            elements.filter { !$0.isInScroller && !$0.frame.isEmpty }.allSatisfy { $0.frame.minX >= window.minX - 1 && $0.frame.maxX <= window.maxX + 1 }
        }
    }

    private struct Check {
        let name: String
        let passes: (Drawn) -> Bool
        init(_ name: String, _ passes: @escaping (Drawn) -> Bool) {
            self.name = name
            self.passes = passes
        }
    }

    private func drawn(_ key: String, _ app: XCUIApplication) -> Drawn {
        var elements: [Drawn.Element] = []
        func visit(_ element: any XCUIElementSnapshot, isInScroller: Bool) {
            let isScroller = isInScroller || ["markdownTable", "markdownCode"].contains(element.identifier)
            elements.append(Drawn.Element(type: element.elementType, identifier: element.identifier, label: element.label, frame: element.frame, isInScroller: isInScroller))
            for child in element.children { visit(child, isInScroller: isScroller) }
        }
        for part in parts(key, app) {
            if let snapshot = try? part.snapshot() { visit(snapshot, isInScroller: false) }
        }
        return Drawn(elements: elements, window: app.windows.firstMatch.frame)
    }

    private func check(_ key: String, look: String, _ app: XCUIApplication) {
        guard let checks = Self.checks[key] else { return }
        let message = drawn(key, app)
        for check in checks where !check.passes(message) {
            XCTFail("[\(look)] \(check.name)")
        }
    }

    /// The fixture's checks, each under its own words, as what they mean on the phone.
    private static let checks: [String: [Check]] = [
        "headings-and-emphasis": [
            Check("h1 count 1: the first heading shows") { $0.hasLabel("Heading one") },
            Check("h4 count 1: the fourth heading shows") { $0.hasLabel("Heading four") },
            Check("strong minimum 1: the bold words show") { $0.hasText("Some bold") },
            Check("del, s count 1: the struck words show") { $0.hasText("struck through") },
            Check("code minimum 1: the inline code shows") { $0.hasText("inline code") },
        ],
        "lists": [
            Check("ol minimum 1: the steps are numbered") { $0.hasLabel("1.") && $0.hasLabel("3.") },
            Check("ul ul minimum 1: a nested item sits deeper than its parent") { drawn in
                guard let step = drawn.frame(ofLabel: "Clear the belt"), let side = drawn.frame(ofLabel: "left side"),
                    let guardItem = drawn.frame(ofLabel: "under the guard")
                else { return false }
                return side.minX > step.minX && guardItem.minX > side.minX
            },
            Check(".task-box count 3: the task list shows three boxes") { $0.count(identifier: "markdownTaskBox") + $0.count(identifier: "markdownTaskBoxDone") == 3 },
            Check(".task-box--done count 1: one box is ticked") { $0.count(identifier: "markdownTaskBoxDone") == 1 },
        ],
        "table-narrow": [
            Check("table count 1: one table") { $0.count(identifier: "markdownTable") == 1 },
            Check("th count 3: three header cells") { ["Station", "Rate", "State"].allSatisfy($0.hasLabel) },
            Check("tbody tr count 3: three rows") { ["Pick 1", "Pick 2", "Pack"].allSatisfy($0.hasLabel) },
            Check("td code count 3: the code cells show") { $0.hasLabel("slow") && $0.hasLabel("ok") },
            Check("columnAlignment left, right, center: each column, header included, lines up as its Markdown says") { drawn in
                guard let station = drawn.frame(ofLabel: "Station"), let pick = drawn.frame(ofLabel: "Pick 1"),
                    let rate = drawn.frame(ofLabel: "Rate"), let first = drawn.frame(ofLabel: "412"), let second = drawn.frame(ofLabel: "398"),
                    let state = drawn.frame(ofLabel: "State"), let slow = drawn.frame(ofLabel: "slow")
                else { return false }
                let isLeft = abs(station.minX - pick.minX) <= 1
                let isRight = abs(rate.maxX - first.maxX) <= 1 && abs(first.maxX - second.maxX) <= 1
                let isCentered = abs(state.midX - slow.midX) <= 1
                return isLeft && isRight && isCentered
            },
        ],
        "table-wide": [
            Check(".table-wrap count 1: one table, which scrolls sideways") { $0.count(identifier: "markdownTable") == 1 },
            Check("th count 8: eight header cells, each whole") { drawn in
                ["Hour", "Picks", "Faults", "Gripper", "Vision", "Belt", "Operator", "Notes about the hour that run long"].allSatisfy(drawn.hasLabel)
            },
            Check("hasNoOverflow: nothing but the table reaches past the edge") { $0.hasNoOverflow },
            Check("[data-testid=mujin-staff-badge] minimum 1: the author is marked Mujin staff") { $0.hasText("Mujin staff") },
        ],
        "quote-and-rule": [
            Check("blockquote count 1: the quote shows") { $0.hasText("The line stopped twice before the break.") },
            Check("hr count 1: the words after the rule show") { $0.hasText("After the rule, the reply goes on.") },
        ],
        "code-blocks": [
            Check("pre count 7: seven code blocks") { $0.count(identifier: "markdownCode") == 7 },
        ],
        "mermaid-diagrams": [
            Check("drawnDiagrams 4: the four diagrams are drawn") { $0.count(identifier: "mermaidDiagram") == 4 },
        ],
        "mermaid-broken": [
            Check("pre count 1: the broken diagram shows its source") { $0.count(identifier: "markdownCode") == 1 && $0.hasText("this is not a diagram") },
        ],
        "math": [
            Check("katexOutput, .katex minimum 2: the inline formula is drawn") { $0.count(identifier: "mathParagraph") >= 1 },
            Check("katexOutput, .katex-display count 1: the display formula is drawn") { $0.count(identifier: "mathFormula") == 1 },
            Check("textContains $5 and $10: money stays text") { $0.hasText("$5 and $10") },
        ],
        "chart-bar": [Check("svg minimum 1: the bar chart is drawn") { $0.count(identifier: "answerChart") == 1 }],
        "chart-line": [Check("svg minimum 1: the line chart is drawn") { $0.count(identifier: "answerChart") == 1 }],
        "chart-pie": [Check("svg minimum 1: the pie chart is drawn") { $0.count(identifier: "answerChart") == 1 }],
        "image-landscape": [Check("img hasSize: the picture has its size") { $0.hasSizedButtons(named: ["photo-landscape.png"]) }],
        "image-portrait": [Check("img hasSize: the picture has its size") { $0.hasSizedButtons(named: ["photo-portrait.png"]) }],
        "images-several": [
            Check("img minimum 3 hasSize: the three pictures have their sizes") { drawn in
                drawn.hasSizedButtons(named: ["photo-landscape.png", "photo-portrait.png", "photo-square.png"])
            },
        ],
        "video": [Check("video count 1: the video shows") { $0.hasLabel("clip.mp4") }],
        "files": [
            Check("textContains maintenance-checklist.pdf") { $0.hasText("maintenance-checklist.pdf") },
            Check("textContains debug-logs.zip") { $0.hasText("debug-logs.zip") },
            Check("textContains shift-summary.csv") { $0.hasText("shift-summary.csv") },
        ],
        "voice-message": [
            // The fixture's recording is a browser's WebM, which the phone cannot play, so it shows its notice and length instead of a play button.
            Check("[data-testid=voice-message] minimum 1: the voice message shows, with its play button or the notice that it cannot be played") {
                $0.count(identifier: "voicePlayButton") == 1 || $0.hasText("made in a browser")
            },
            Check("the voice message shows its length") { $0.hasText("0:04") },
        ],
        "link-previews-external": [
            Check("textContains Replacing gripper pads: the card with a picture") { $0.hasText("Replacing gripper pads") },
            Check("textContains Belt speed advisory: the card without one") { $0.hasText("Belt speed advisory") },
        ],
        "link-previews-portal": [
            Check("textContains Conveyor jam at packing: the pasted ticket keeps its card") { $0.hasText("Conveyor jam at packing") },
            Check("textContains Chat rendering fixture controller: the controller's card") { $0.hasText("Chat rendering fixture controller") },
            Check("textContains Harbor Works: the site's card") { $0.hasText("Harbor Works") },
        ],
        "link-previews-portal-more": [
            Check("textContains Packing Cell 2: the cell's card") { $0.hasText("Packing Cell 2") },
            Check("textContains Shift handover notes: the page's card") { $0.hasText("Shift handover notes") },
        ],
        "references-mentions-emoji": [
            Check("[data-testid=reference-chip] minimum 2: chips for #7, the controller and the site") { $0.count(identifier: "referenceChip") >= 3 },
            Check("the ticket chip says #7") { drawn in drawn.elements.contains { $0.identifier == "referenceChip" && $0.label.contains("#7") } },
            Check(".mention-chip minimum 1: the reader's name shows") { $0.hasText("@Alex Example") },
        ],
        "long-words": [Check("hasNoOverflow: the long address and word wrap inside the bubble") { $0.hasNoOverflow }],
        "reply-quote": [Check("textContains The line stopped twice: the quote of the answered message") { $0.hasText("The line stopped twice") }],
        "reactions": [Check("textContains the thumbs up reaction") { $0.hasText("\u{1F44D}") }],
        "internal-note": [
            Check("textContains Internal: the note shows to staff") { $0.hasText("Internal: the pads came from the old batch") },
            Check("the note is marked internal") { $0.count(identifier: "internalNoteLabel") >= 1 },
        ],
        "thread-root": [Check("textContains 3 replies: the thread's count") { $0.hasText("3 replies") }],
        "edited": [
            Check("textContains 1.4 meters: the edited words") { $0.hasText("1.4 meters") },
            Check("the message says it was edited") { $0.hasLabel("edited") },
        ],
        "deleted": [Check("the deleted message says so") { $0.hasText("This message was deleted") }],
        "tool-activity": [Check("the tool lines show") { drawn in drawn.elements.contains { $0.identifier.contains("~call") } }],
        "artifact-markdown": [
            Check("textContains Weekly line report: the document's title") { $0.hasText("Weekly line report") },
            Check("textContains Uptime held above 95 percent: the document's words") { $0.hasText("Uptime held above 95 percent") },
        ],
        "artifact-html": [Check("iframe count 1: the page shows") { $0.count(type: .webView) == 1 }],
    ]
}
