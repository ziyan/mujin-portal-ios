import Foundation
import Testing

@testable import PortalKit

@Suite struct BareLinkTests {
    func linkedText(_ text: AttributedString) -> [String: URL] {
        var result: [String: URL] = [:]
        for run in text.runs {
            if let url = run.link { result[String(text[run.range].characters)] = url }
        }
        return result
    }

    func linked(_ markdown: String) -> [String: URL] {
        let parsed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
        return linkedText(BareLinks.linked(parsed))
    }

    @Test func aBareAddressBecomesALink() {
        #expect(linked("The checklist is here: https://example.test/docs/suction") == ["https://example.test/docs/suction": URL(string: "https://example.test/docs/suction")!])
        #expect(linked("see HTTP://example.test/a now")["HTTP://example.test/a"] != nil)
    }

    @Test func punctuationAfterAnAddressIsNotPartOfIt() {
        #expect(Set(linked("Read https://example.test/a.").keys) == ["https://example.test/a"])
        #expect(Set(linked("Is it https://example.test/a?").keys) == ["https://example.test/a"])
        #expect(Set(linked("One https://example.test/a, two https://example.test/b; done").keys) == ["https://example.test/a", "https://example.test/b"])
        #expect(Set(linked("Query https://example.test/a?x=1&y=2.").keys) == ["https://example.test/a?x=1&y=2"])
    }

    @Test func aClosingBracketOnlyBelongsToTheAddressWhenItIsBalanced() {
        #expect(Set(linked("(see https://example.test/a)").keys) == ["https://example.test/a"])
        #expect(Set(linked("(see https://example.test/a).").keys) == ["https://example.test/a"])
        #expect(Set(linked("also https://example.test/wiki/Item_(thing) here").keys) == ["https://example.test/wiki/Item_(thing)"])
    }

    @Test func anAddressInsideCodeIsNotALink() {
        #expect(linked("run `curl https://example.test/a` first").isEmpty)
    }

    @Test func aMarkdownLinkIsKeptAsItIs() {
        let links = linked("[the docs](https://example.test/docs) and [https://example.test/x](https://example.test/y)")
        #expect(links["the docs"] == URL(string: "https://example.test/docs"))
        #expect(links["https://example.test/x"] == URL(string: "https://example.test/y"))
        #expect(links.count == 2)
    }

    @Test func mailAddressesAndOtherSchemesAreLeftAlone() {
        #expect(linked("write to sam@example.test or ftp://example.test/a or example.test/b").isEmpty)
        #expect(linked("see mailto:sam@example.test").isEmpty)
    }

    @Test func aWordEndingInTheSchemeIsNotAnAddress() {
        #expect(linked("xhttps://example.test/a").isEmpty)
        #expect(linked("https://").isEmpty)
    }

    @Test func plainTextIsLinkedAsWritten() {
        let text = BareLinks.linked(plainText: "Got it https://example.test/a")
        #expect(linkedText(text) == ["https://example.test/a": URL(string: "https://example.test/a")!])
    }
}
