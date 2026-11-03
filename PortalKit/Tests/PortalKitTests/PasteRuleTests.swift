import Foundation
import Testing

@testable import PortalKit

@Suite struct PasteRuleTests {
    @Test func aLoneAddressThatCameWithAPictureIsNotTyped() {
        let decision = PasteRule.decide(pictureCount: 1, texts: ["https://images.example.com/photos/42/large.jpg?size=2"], alreadyAttached: 0)
        #expect(decision.attachmentCount == 1)
        #expect(decision.textToInsert == nil)
        #expect(decision.refusal == nil)
    }

    @Test func aLoneFileNameThatCameWithAPictureIsNotTyped() {
        for name in ["IMG_0042.HEIC", "Screenshot 2030-01-02 at 9.30.00.png", "dock-photo.jpeg", "file:///var/mobile/Media/DCIM/100APPLE/IMG_0042.JPG"] {
            let decision = PasteRule.decide(pictureCount: 1, texts: [name], alreadyAttached: 0)
            #expect(decision.textToInsert == nil, "\(name)")
        }
    }

    @Test func aNameTheClipboardGivesForThePictureIsNotTypedEvenWithoutAnExtension() {
        let decision = PasteRule.decide(pictureCount: 1, texts: ["Pallet label"], pictureNames: ["Pallet label"], alreadyAttached: 0)
        #expect(decision.textToInsert == nil)
        let withExtension = PasteRule.decide(pictureCount: 1, texts: ["pallet label"], pictureNames: ["Pallet label.png"], alreadyAttached: 0)
        #expect(withExtension.textToInsert == nil)
    }

    @Test func aRealSentenceCopiedWithAPictureIsKept() {
        let sentence = "The label on this pallet is torn, can you check it?"
        let decision = PasteRule.decide(pictureCount: 1, texts: [sentence], alreadyAttached: 0)
        #expect(decision.attachmentCount == 1)
        #expect(decision.textToInsert == sentence)
    }

    @Test func anAddressInsideASentenceIsKept() {
        let text = "Compare with https://images.example.com/a.png please"
        #expect(PasteRule.decide(pictureCount: 1, texts: [text], alreadyAttached: 0).textToInsert == text)
        let endsInName = "Please use the file named logo.png"
        #expect(PasteRule.decide(pictureCount: 1, texts: [endsInName], alreadyAttached: 0).textToInsert == endsInName)
    }

    @Test func aCaptionThatIsNotAnAddressOrNameIsKept() {
        #expect(PasteRule.decide(pictureCount: 2, texts: ["Pallet 7"], alreadyAttached: 0).textToInsert == "Pallet 7")
    }

    @Test func linesThatAreAllReferencesAreDroppedButAMixedTextIsKeptWhole() {
        let references = "https://images.example.com/a.png\nIMG_0001.PNG\n\n"
        #expect(PasteRule.decide(pictureCount: 2, texts: [references], alreadyAttached: 0).textToInsert == nil)
        let mixed = "https://images.example.com/a.png\nSee the second one"
        #expect(PasteRule.decide(pictureCount: 2, texts: [mixed], alreadyAttached: 0).textToInsert == mixed)
    }

    @Test func theSameStringOnTheClipboardTwiceIsOneString() {
        #expect(PasteRule.combinedText(["Hello", "Hello", "  ", "World"]) == "Hello\nWorld")
        let decision = PasteRule.decide(pictureCount: 1, texts: ["https://images.example.com/a.png", "https://images.example.com/a.png"], alreadyAttached: 0)
        #expect(decision.textToInsert == nil)
    }

    @Test func aPictureWithNoTextAttachesAndTypesNothing() {
        let decision = PasteRule.decide(pictureCount: 3, texts: [], alreadyAttached: 0)
        #expect(decision.attachmentCount == 3 && decision.textToInsert == nil && decision.refusal == nil)
    }

    @Test func noPicturesLeavesTheTextToBeTypedAsBefore() {
        let decision = PasteRule.decide(pictureCount: 0, texts: ["https://example.com/page"], alreadyAttached: 0)
        #expect(decision.attachmentCount == 0)
        #expect(decision.textToInsert == "https://example.com/page")
    }

    @Test func everyPictureIsAttachedUpToTheLimitOnFiles() {
        let limit = AttachmentLimits.maximumFileCount
        #expect(PasteRule.decide(pictureCount: limit, texts: [], alreadyAttached: 0).attachmentCount == limit)
        let crowded = PasteRule.decide(pictureCount: 5, texts: [], alreadyAttached: limit - 2)
        #expect(crowded.attachmentCount == 2)
        #expect(crowded.refusal == "You can attach up to \(limit) files to one message.")
        let full = PasteRule.decide(pictureCount: 1, texts: ["Look at this"], alreadyAttached: limit)
        #expect(full.attachmentCount == 0 && full.refusal != nil)
        #expect(full.textToInsert == "Look at this")
        #expect(PasteRule.attachableCount(pictureCount: 4, alreadyAttached: limit + 3) == 0)
    }

    @Test func addressesAreRecognizedOnlyWhenTheyAreWholeAddresses() {
        #expect(PasteRule.isOnlyPictureReference("www.example.com/cat.gif"))
        #expect(PasteRule.isOnlyPictureReference("data:image/png;base64,AAAA"))
        #expect(!PasteRule.isOnlyPictureReference("https://"))
        #expect(!PasteRule.isOnlyPictureReference("mailto:someone@example.com"))
        #expect(!PasteRule.isOnlyPictureReference("   "))
        #expect(!PasteRule.isOnlyPictureReference("notes.txt"))
    }
}
