import Foundation
import Testing

@testable import PortalKit

@Suite struct SpeakableTextTests {
    @Test func marksThatOnlyMeanSomethingOnAScreenAreDropped() {
        #expect(ReadAloudText.speakable(from: "## Status\n- **Belt two** is stopped.") == "Status Belt two is stopped.")
        #expect(ReadAloudText.speakable(from: "Run `restart` once.") == "Run restart once.")
        #expect(ReadAloudText.speakable(from: "> Quoted line\n> second") == "Quoted line second")
        #expect(ReadAloudText.speakable(from: "1. First\n2) Second") == "First Second")
        #expect(ReadAloudText.speakable(from: "Some *emphasis* and _more_ and ~~gone~~ text.") == "Some emphasis and more and gone text.")
        #expect(ReadAloudText.speakable(from: "snake_case_name stays") == "snake_case_name stays")
    }

    @Test func aLinkSaysItsWordsAndABareAddressIsLeftOut() {
        #expect(ReadAloudText.speakable(from: "See [the ticket](https://example.test/t/1) now.") == "See the ticket now.")
        #expect(ReadAloudText.speakable(from: "Open https://example.test/page please.") == "Open please.")
        #expect(ReadAloudText.speakable(from: "Visit <https://example.test/a>, then stop.") == "Visit, then stop.")
    }

    @Test func anImageAndAnInlineFormulaAreLeftOut() {
        #expect(ReadAloudText.speakable(from: "Look at ![a chart](https://example.test/c.png) here.") == "Look at here.")
        #expect(ReadAloudText.speakable(from: "The area is \\(a^2 + b^2\\) for sure.") == "The area is for sure.")
    }

    @Test func aTableReadsAsItsCellsSeparatedByCommas() {
        let table = "Dips this week:\n\n| Station | Dips | Lowest kPa |\n| :--- | ---: | ---: |\n| Station 3 | 4 | 31 |\n| Station 1 | 1 | 38 |"
        #expect(ReadAloudText.speakable(from: table) == "Dips this week:, Station, Dips, Lowest kPa,, Station 3, 4, 31,, Station 1, 1, 38")
    }

    @Test func aCodeBlockAFormulaAndACommentAreLeftOutWhole() {
        #expect(ReadAloudText.speakable(from: "Run this:\n```\nrm -rf cache\n```\nThen wait.") == "Run this: Then wait.")
        #expect(ReadAloudText.speakable(from: "Before.\n$$\nx = y + 1\n$$\nAfter.") == "Before. After.")
        #expect(ReadAloudText.speakable(from: "Before.\n\\[\nx = y + 1\n\\]\nAfter.") == "Before. After.")
        #expect(ReadAloudText.speakable(from: "Answer.<!--suggestions: [\"One\"] -->") == "Answer.")
    }

    @Test func anUnfinishedCodeBlockHidesTheRestOfTheMessage() {
        #expect(ReadAloudText.speakable(from: "Here it is.\n```swift\nlet value = 1") == "Here it is.")
    }

    @Test func aMessageOfOnlyCodeOrOnlyAPictureHasNothingToRead() {
        #expect(!ReadAloudText.hasSpeakableText("```\nlet value = 1\n```"))
        #expect(!ReadAloudText.hasSpeakableText("![photo](/api/v1/attachment/photo01)"))
        #expect(!ReadAloudText.hasSpeakableText("https://example.test/only-a-link"))
        #expect(!ReadAloudText.hasSpeakableText(""))
        #expect(!ReadAloudText.hasSpeakableText("   \n  "))
        #expect(ReadAloudText.hasSpeakableText("Thanks."))
        #expect(ReadAloudText.hasSpeakableText("```\ncode\n```\nAnd a sentence."))
    }
}

@Suite struct SpeechPieceTests {
    @Test func aShortMessageIsOnePiece() {
        #expect(ReadAloudText.pieces(of: "Door 4 is fixed. Thanks!") == ["Door 4 is fixed. Thanks!"])
        #expect(ReadAloudText.pieces(of: "```\ncode\n```").isEmpty)
    }

    @Test func aLongMessageIsWholeSentencesWithAShortFirstPiece() {
        let text = (1...200).map { "This is sentence \($0) of the long message." }.joined(separator: " ")
        let pieces = ReadAloudText.pieces(of: text)
        #expect(pieces.count > 5)
        #expect(pieces[0].count <= ReadAloudText.firstPieceCharacters)
        #expect(pieces.allSatisfy { $0.count <= ReadAloudText.followingPieceCharacters })
        #expect(pieces.allSatisfy { $0.hasSuffix("message.") })
        #expect(pieces.joined(separator: " ") == text)
    }

    @Test func aSentenceIsNeverCutBetweenPiecesWhenItFits() {
        let pieces = ReadAloudText.split("Alpha beta. Gamma delta. Epsilon zeta.", firstCharacters: 12, followingCharacters: 26, maximumCharacters: 100)
        #expect(pieces == ["Alpha beta.", "Gamma delta. Epsilon zeta."])
    }

    @Test func aDecimalPointDoesNotEndASentence() {
        #expect(ReadAloudText.sentences(of: "The value is 3.5 today. Next.") == ["The value is 3.5 today.", "Next."])
        #expect(ReadAloudText.sentences(of: "Is it fixed? Yes! (Really.) Done") == ["Is it fixed?", "Yes!", "(Really.)", "Done"])
    }

    @Test func fullWidthStopsEndASentenceWithoutASpace() {
        #expect(ReadAloudText.sentences(of: "今日は晴れです。明日は雨です。") == ["今日は晴れです。", "明日は雨です。"])
    }

    @Test func aSentenceOverTheLimitIsCutAtASpaceAndNoPieceIsOverTheLimit() {
        let long = String(repeating: "word ", count: 2_000)
        let pieces = ReadAloudText.split(long)
        #expect(pieces.count == 3)
        #expect(pieces.allSatisfy { $0.count <= ReadAloudText.maximumPieceCharacters })
        #expect(pieces.flatMap { $0.split(separator: " ") }.count == 2_000)
    }

    @Test func aRunWithNoSpaceIsCutAtTheLimit() {
        let pieces = ReadAloudText.split(String(repeating: "x", count: 9_000))
        #expect(pieces.map(\.count) == [4_096, 4_096, 808])
    }

    @Test func manyShortSentencesNeverMakeAPieceOverTheLimit() {
        let text = String(repeating: "Ok. ", count: 5_000)
        let pieces = ReadAloudText.pieces(of: text)
        #expect(pieces.allSatisfy { $0.count <= ReadAloudText.maximumPieceCharacters })
        #expect(pieces.joined(separator: " ").split(separator: " ").count == 5_000)
    }
}
