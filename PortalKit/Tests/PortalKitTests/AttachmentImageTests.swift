import Foundation
import Testing

@testable import PortalKit

@Suite struct AttachmentImageTests {
    @Test func aSmallPictureGoesUpUntouchedInItsOwnFormat() {
        let jpeg = AttachmentImages.plan(pixelWidth: 1200, pixelHeight: 800, sourceFormat: .jpeg, byteCount: 300_000)
        #expect(jpeg.keepsOriginalBytes && jpeg.outputFormat == .jpeg)
        let png = AttachmentImages.plan(pixelWidth: 2048, pixelHeight: 1000, sourceFormat: .png, byteCount: 900_000)
        #expect(png.keepsOriginalBytes && png.outputFormat == .png)
    }

    @Test func aLargePictureIsScaledDownAndKeepsItsFormat() {
        let plan = AttachmentImages.plan(pixelWidth: 4032, pixelHeight: 3024, sourceFormat: .jpeg, byteCount: 3_000_000)
        #expect(!plan.keepsOriginalBytes)
        #expect(plan.longestSidePixels == AttachmentImages.longestSidePixels)
        #expect(plan.outputFormat == .jpeg)
        #expect(AttachmentImages.plan(pixelWidth: 3000, pixelHeight: 3000, sourceFormat: .png, byteCount: 100).outputFormat == .png)
    }

    @Test func aSmallPictureOverTheByteLimitIsReencodedWithoutScaling() {
        let overLimit = Int(AttachmentLimits.maximumFileBytes) + 1
        let plan = AttachmentImages.plan(pixelWidth: 1500, pixelHeight: 1000, sourceFormat: .png, byteCount: overLimit)
        #expect(!plan.keepsOriginalBytes)
        #expect(plan.longestSidePixels == 1500)
    }

    @Test func aFormatThatIsNotKeptBecomesJPEG() {
        let plan = AttachmentImages.plan(pixelWidth: 1000, pixelHeight: 1000, sourceFormat: nil, byteCount: 10)
        #expect(!plan.keepsOriginalBytes && plan.outputFormat == .jpeg)
        #expect(AttachmentImageFormat(typeIdentifier: "public.heic") == nil)
        #expect(AttachmentImageFormat(typeIdentifier: "public.PNG") == .png)
        #expect(AttachmentImageFormat(typeIdentifier: "public.jpeg") == .jpeg)
    }

    @Test func aPNGStillTooBigAfterScalingFallsBackToJPEG() {
        let overLimit = Int(AttachmentLimits.maximumFileBytes) + 1
        #expect(AttachmentImages.fallbackFormat(for: .png, encodedByteCount: overLimit) == .jpeg)
        #expect(AttachmentImages.fallbackFormat(for: .png, encodedByteCount: 1000) == .png)
        #expect(AttachmentImages.fallbackFormat(for: .jpeg, encodedByteCount: overLimit) == .jpeg)
    }

    @Test func scalingKeepsTheShapeAndNeverReachesZero() {
        let landscape = AttachmentImages.fittedSize(pixelWidth: 4096, pixelHeight: 3072)
        #expect(landscape.width == 2048 && landscape.height == 1536)
        let small = AttachmentImages.fittedSize(pixelWidth: 640, pixelHeight: 480)
        #expect(small.width == 640 && small.height == 480)
        let strip = AttachmentImages.fittedSize(pixelWidth: 40_000, pixelHeight: 3)
        #expect(strip.width == 2048 && strip.height == 1)
    }

    @Test func aNameThatIsTakenGetsANumber() {
        #expect(AttachmentImages.uniqueName("Photo 1.jpg", among: []) == "Photo 1.jpg")
        #expect(AttachmentImages.uniqueName("Photo 1.jpg", among: ["photo 1.JPG"]) == "Photo 1 2.jpg")
        #expect(AttachmentImages.uniqueName("Photo 1.jpg", among: ["Photo 1.jpg", "Photo 1 2.jpg"]) == "Photo 1 3.jpg")
        #expect(AttachmentImages.uniqueName("notes", among: ["notes"]) == "notes 2")
    }

    @Test func eachFormatKnowsItsContentTypeAndExtension() {
        #expect(AttachmentImageFormat.png.contentType == "image/png" && AttachmentImageFormat.png.fileExtension == "png")
        #expect(AttachmentImageFormat.jpeg.contentType == "image/jpeg" && AttachmentImageFormat.jpeg.fileExtension == "jpg")
    }

    @Test func aChatMessageWithLinksMustStillFitTheChatLimit() {
        let file = UploadedFile(id: "file01", filename: "plan.png", contentType: "image/png")
        #expect(AttachmentLimits.chatMessageRefusal(text: "Look at this", files: [file]) == nil)
        let long = String(repeating: "a", count: ChatRules.maximumMessageCharacters - 10)
        #expect(AttachmentLimits.chatMessageRefusal(text: long, files: [file]) != nil)
        #expect(AttachmentLimits.chatMessageRefusal(text: long, files: []) == nil)
    }
}
