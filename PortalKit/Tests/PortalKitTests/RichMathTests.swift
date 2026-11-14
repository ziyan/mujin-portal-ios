import Foundation
import Testing

@testable import PortalKit

/// Formulas are found as the web finds them: between the four delimiters, and only where the content reads as math.
@Suite struct RichMathTests {
    @Test func whatReadsAsMathIsAFormula() {
        #expect(RichMath.isFormula("\\frac{n}{t}"))
        #expect(RichMath.isFormula("x"))
        #expect(RichMath.isFormula("xy"))
        #expect(RichMath.isFormula("a + b"))
        #expect(RichMath.isFormula("2"))
        #expect(!RichMath.isFormula("and"))
        #expect(!RichMath.isFormula(" and "))
        #expect(!RichMath.isFormula("5 and "))
        #expect(!RichMath.isFormula("costs 5 and more"))
    }

    @Test func moneyAndPlainWordsStayText() {
        #expect(RichMath.pieces(of: "The pads cost $5 and $10 a pair") == [.text("The pads cost $5 and $10 a pair")])
        #expect(RichMath.pieces(of: "between $$ and $$") == [.text("between $$ and $$")])
        #expect(!RichMath.hasFormula("Use `$x$` in code"))
    }

    @Test func eachDelimiterMakesAFormula() {
        #expect(RichMath.pieces(of: "rate $r = \\frac{n}{t}$ now") == [.text("rate "), .formula(tex: "r = \\frac{n}{t}", isDisplay: false), .text(" now")])
        #expect(RichMath.pieces(of: "see \\(x^2\\)") == [.text("see "), .formula(tex: "x^2", isDisplay: false)])
        #expect(RichMath.pieces(of: "$$\\sigma$$") == [.formula(tex: "\\sigma", isDisplay: true)])
        #expect(RichMath.pieces(of: "\\[a+b\\]") == [.formula(tex: "a+b", isDisplay: true)])
    }

    @Test func theDrawingPageGetsEscapedWordsAndFormulaSpans() {
        #expect(RichMath.html(of: "**Rate** <b> $x$") == "<strong>Rate</strong> &lt;b&gt; <span class=\"tex\">x</span>")
    }

    @Test func aBracketedDisplayBlockIsReadAsMath() {
        #expect(MarkdownBlocks.parse("\\[\n\\sigma = 1\n\\]") == [.code(language: "math", text: "\\sigma = 1")])
        #expect(MarkdownBlocks.parse("$$ and $$") == [.paragraph("$$ and $$")])
    }

    @Test func aLineThatOnlyStartsWithDollarsLeavesTheRestOfTheMessageBe() {
        // An amount at the start of a line, with no closing $$ after it, is words, and so is everything under it.
        #expect(MarkdownBlocks.parse("$$5 million deal closed\n\nThe next step is Friday.") == [
            .paragraph("$$5 million deal closed"), .paragraph("The next step is Friday."),
        ])
        #expect(MarkdownBlocks.parse("\\[see the note\n\nmore words") == [.paragraph("\\[see the note"), .paragraph("more words")])
        // A real display formula over several lines is still one.
        #expect(MarkdownBlocks.parse("$$\n\\sigma = 1\n$$") == [.code(language: "math", text: "\\sigma = 1")])
    }
}
