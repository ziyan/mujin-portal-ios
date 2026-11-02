import Foundation
import Testing

@testable import PortalKit

@Suite struct BareLinkTests {
    @Test func aBareAddressBecomesAnAutolink() {
        #expect(BareLinks.markdown("The checklist is here: https://example.test/docs/suction") == "The checklist is here: <https://example.test/docs/suction>")
        #expect(BareLinks.markdown("see HTTP://example.test/a now") == "see <HTTP://example.test/a> now")
        #expect(BareLinks.markdown("no address here") == "no address here")
    }

    @Test func punctuationAfterAnAddressIsNotPartOfIt() {
        #expect(BareLinks.markdown("Read https://example.test/a.") == "Read <https://example.test/a>.")
        #expect(BareLinks.markdown("Is it https://example.test/a?") == "Is it <https://example.test/a>?")
        #expect(BareLinks.markdown("One https://example.test/a, two https://example.test/b; done") == "One <https://example.test/a>, two <https://example.test/b>; done")
        #expect(BareLinks.markdown("Query https://example.test/a?x=1&y=2.") == "Query <https://example.test/a?x=1&y=2>.")
        #expect(BareLinks.markdown("Bold **https://example.test/a**") == "Bold **<https://example.test/a>**")
    }

    @Test func aClosingBracketOnlyBelongsToTheAddressWhenItIsBalanced() {
        #expect(BareLinks.markdown("(see https://example.test/a)") == "(see <https://example.test/a>)")
        #expect(BareLinks.markdown("(see https://example.test/a).") == "(see <https://example.test/a>).")
        #expect(BareLinks.markdown("also https://example.test/wiki/Item_(thing) here") == "also <https://example.test/wiki/Item_(thing)> here")
    }

    @Test func anAddressInsideCodeIsLeftAlone() {
        #expect(BareLinks.markdown("run `curl https://example.test/a` first") == "run `curl https://example.test/a` first")
        #expect(BareLinks.markdown("run ``a ` https://example.test/a`` first") == "run ``a ` https://example.test/a`` first")
        #expect(BareLinks.markdown("`code` then https://example.test/a") == "`code` then <https://example.test/a>")
    }

    @Test func existingLinksAreLeftAlone() {
        let text = "[the docs](https://example.test/docs) and [https://example.test/x](https://example.test/y) and <https://example.test/z> and ![shot](https://example.test/p.png)"
        #expect(BareLinks.markdown(text) == text)
        #expect(BareLinks.markdown("[docs](https://example.test/d) or https://example.test/e") == "[docs](https://example.test/d) or <https://example.test/e>")
    }

    @Test func mailAddressesAndOtherSchemesAreLeftAlone() {
        let text = "write to sam@example.test or ftp://example.test/a or example.test/b or mailto:sam@example.test"
        #expect(BareLinks.markdown(text) == text)
    }

    @Test func aWordEndingInTheSchemeIsNotAnAddress() {
        #expect(BareLinks.markdown("xhttps://example.test/a") == "xhttps://example.test/a")
        #expect(BareLinks.markdown("https://") == "https://")
    }

    @Test func plainTextIsLinkedAsWritten() {
        let text = BareLinks.linked(plainText: "Got it https://example.test/a.")
        let links = text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
        #expect(links.count == 1)
        #expect(links.first?.0 == "https://example.test/a")
        #expect(links.first?.1 == URL(string: "https://example.test/a"))
    }
}

@Suite struct FirstEmojiTests {
    @Test func theFirstEmojiIsTaken() {
        #expect(Reactions.firstEmoji(in: "\u{1F525}") == "\u{1F525}")
        #expect(Reactions.firstEmoji(in: "ab \u{2764}\u{FE0F} \u{1F389}") == "\u{2764}\u{FE0F}")
    }

    @Test func lettersAndDigitsAreNotEmoji() {
        #expect(Reactions.firstEmoji(in: "abc 123 #*") == nil)
        #expect(Reactions.firstEmoji(in: "") == nil)
    }
}
