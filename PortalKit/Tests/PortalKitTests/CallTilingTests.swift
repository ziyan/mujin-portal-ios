import Foundation
import Testing

@testable import PortalKit

@Suite struct CallTilingTests {
    let phone = (width: 361.0, height: 560.0)

    func covered(_ tiles: [CallTile]) -> Double { tiles.reduce(0) { $0 + $1.width * $1.height } }

    @Test func aloneTheTileIsTheWholeStage() {
        let tiles = CallTiling.tiles(count: 1, width: phone.width, height: phone.height)
        #expect(tiles == [CallTile(index: 0, x: 0, y: 0, width: phone.width, height: phone.height)])
    }

    @Test func fourPeopleFillTheStageInTwoByTwo() {
        let tiles = CallTiling.tiles(count: 4, width: phone.width, height: phone.height)
        #expect(tiles.count == 4)
        #expect(Set(tiles.map(\.x)).count == 2 && Set(tiles.map(\.y)).count == 2)
        let spent = covered(tiles) + CallTiling.spacing * (phone.height + phone.width - CallTiling.spacing)
        #expect(abs(spent - phone.width * phone.height) < 1)
    }

    @Test func threePeopleAreTwoOnTopAndOneWideBelow() {
        let tiles = CallTiling.tiles(count: 3, width: phone.width, height: phone.height)
        #expect(tiles[0].y == tiles[1].y && tiles[2].y > tiles[0].y)
        #expect(tiles[2].x == 0 && tiles[2].width == phone.width)
        #expect(tiles[0].width < tiles[2].width)
    }

    @Test func fivePeopleOnAPhoneUseTwoColumnsAndTheLastIsWide() {
        #expect(CallTiling.columnCount(count: 5, width: phone.width, height: phone.height) == 2)
        let tiles = CallTiling.tiles(count: 5, width: phone.width, height: phone.height)
        #expect(tiles.count == 5)
        #expect(tiles[4].width == phone.width)
        #expect(tiles.allSatisfy { $0.x >= 0 && $0.x + $0.width <= phone.width + 0.001 && $0.y + $0.height <= phone.height + 0.001 })
    }

    @Test func eightPeopleOnAWideStageTakeTheColumnsThatMakeTheLargestTiles() {
        let columns = CallTiling.columnCount(count: 8, width: 1_000, height: 600)
        #expect(columns == 4)
        let tiles = CallTiling.tiles(count: 8, width: 1_000, height: 600)
        #expect(tiles.count == 8 && Set(tiles.map(\.width)).count == 1)
        #expect(CallTiling.columnCount(count: 8, width: 361, height: 560) == 2)
        #expect(CallTiling.columnCount(count: 8, width: 361, height: 560, isWide: true) >= 2)
    }

    @Test func threeOnAVeryWideStageSitInOneRow() {
        let tiles = CallTiling.tiles(count: 3, width: 1_000, height: 400)
        #expect(Set(tiles.map(\.y)).count == 1 && tiles.count == 3)
    }

    @Test func aShortRowOfThreeColumnsIsCentered() {
        let tiles = CallTiling.tiles(count: 5, width: 1_000, height: 400, isWide: true)
        let columns = CallTiling.columnCount(count: 5, width: 1_000, height: 400, isWide: true)
        #expect(columns >= 3)
        let last = tiles.filter { $0.y == tiles.last!.y }
        let left = last.map(\.x).min()!
        let right = last.map { $0.x + $0.width }.max()!
        #expect(abs(left - (1_000 - right)) < 0.001)
    }

    @Test func noTilesWithoutPeopleOrRoom() {
        #expect(CallTiling.tiles(count: 0, width: 300, height: 400).isEmpty)
        #expect(CallTiling.tiles(count: 3, width: 0, height: 400).isEmpty)
    }

    @Test func thePictureInPictureIsAboutAQuarterWideAndUpright() {
        let size = CallTiling.pictureInPictureSize(stageWidth: 361)
        #expect(size.width > 361 * 0.2 && size.width < 361 * 0.3)
        #expect(abs(size.height / size.width - 4.0 / 3.0) < 0.001)
        #expect(CallTiling.pictureInPictureSize(stageWidth: 100).width == 84)
        #expect(CallTiling.pictureInPictureSize(stageWidth: 2_000).width == 180)
    }

    @Test func thePictureRestsInTheFourCornersAndSnapsToTheNearest() {
        let size = CallTiling.pictureInPictureSize(stageWidth: 361)
        let topTrailing = CallTiling.pictureInPictureOrigin(corner: .topTrailing, stageWidth: 361, stageHeight: 560)
        #expect(topTrailing.x == 361 - size.width - 12 && topTrailing.y == 12)
        let bottomLeading = CallTiling.pictureInPictureOrigin(corner: .bottomLeading, stageWidth: 361, stageHeight: 560)
        #expect(bottomLeading.x == 12 && bottomLeading.y == 560 - size.height - 12)
        #expect(CallTiling.nearestCorner(centerX: 40, centerY: 500, stageWidth: 361, stageHeight: 560) == .bottomLeading)
        #expect(CallTiling.nearestCorner(centerX: 300, centerY: 100, stageWidth: 361, stageHeight: 560) == .topTrailing)
        #expect(CallTiling.nearestCorner(centerX: 100, centerY: 100, stageWidth: 361, stageHeight: 560) == .topLeading)
        #expect(CallTiling.nearestCorner(centerX: 200, centerY: 300, stageWidth: 361, stageHeight: 560) == .bottomTrailing)
    }
}

@Suite struct CallSpeakerTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func theSpeakerViewStartsAtFivePeople() {
        #expect(!CallTiling.usesSpeakerView(count: 4))
        #expect(CallTiling.usesSpeakerView(count: 5))
        #expect(CallTiling.usesSpeakerView(count: 16))
    }

    @Test func theFirstOtherPersonIsOnTheStageUntilSomeoneSpeaks() {
        var speaker = ActiveSpeaker()
        let first = speaker.update(speaking: [], candidates: ["me", "a", "b"], selfUserId: "me", now: start)
        #expect(first == "a")
    }

    @Test func theStageFollowsWhoIsSpeakingButNotAtOnce() {
        var speaker = ActiveSpeaker()
        _ = speaker.update(speaking: ["a"], candidates: ["me", "a", "b"], selfUserId: "me", now: start)
        #expect(speaker.update(speaking: ["b"], candidates: ["me", "a", "b"], selfUserId: "me", now: start.addingTimeInterval(0.5)) == "a")
        #expect(speaker.update(speaking: ["b"], candidates: ["me", "a", "b"], selfUserId: "me", now: start.addingTimeInterval(2)) == "b")
    }

    @Test func aSpeakerStaysOnTheStageWhileTheyKeepTalkingAndAfterTheyStop() {
        var speaker = ActiveSpeaker()
        _ = speaker.update(speaking: ["a"], candidates: ["me", "a", "b"], selfUserId: "me", now: start)
        #expect(speaker.update(speaking: ["a", "b"], candidates: ["me", "a", "b"], selfUserId: "me", now: start.addingTimeInterval(5)) == "a")
        #expect(speaker.update(speaking: [], candidates: ["me", "a", "b"], selfUserId: "me", now: start.addingTimeInterval(9)) == "a")
    }

    @Test func thePersonThemselfDoesNotTakeTheStageFromOthers() {
        var speaker = ActiveSpeaker()
        _ = speaker.update(speaking: [], candidates: ["me", "a"], selfUserId: "me", now: start)
        #expect(speaker.update(speaking: ["me"], candidates: ["me", "a"], selfUserId: "me", now: start.addingTimeInterval(9)) == "a")
    }

    @Test func aPersonWhoLeavesIsReplaced() {
        var speaker = ActiveSpeaker()
        _ = speaker.update(speaking: ["a"], candidates: ["me", "a", "b"], selfUserId: "me", now: start)
        #expect(speaker.update(speaking: [], candidates: ["me", "b"], selfUserId: "me", now: start.addingTimeInterval(0.1)) == "b")
    }

    @Test func onlyTheMainStageAndTheStripInViewAreAskedFor() {
        let plan = CallSubscriptionPlan.plan(
            remoteUserIds: ["a", "b", "c", "d"], mainUserId: "a", visibleStripUserIds: ["b", "c"], isSpeakerView: true)
        #expect(plan == ["a": .full, "b": .small, "c": .small, "d": .off])
    }

    @Test func outsideTheSpeakerViewEveryoneShownIsFull() {
        let plan = CallSubscriptionPlan.plan(remoteUserIds: ["a", "b"], mainUserId: nil, visibleStripUserIds: [], isSpeakerView: false)
        #expect(plan == ["a": .full, "b": .full])
    }
}

@Suite struct CallVideoSelectionTests {
    @Test func aGridTileAsksForFullOnlyWhenItIsLargeEnough() {
        let plan = CallSubscriptionPlan.plan(
            remoteUserIds: ["a", "b", "c"], mainUserId: nil, visibleStripUserIds: [], isSpeakerView: false,
            tileSizes: [
                "a": .init(width: 360, height: 270), "b": .init(width: 359, height: 400), "c": .init(width: 400, height: 269),
            ])
        #expect(plan == ["a": .full, "b": .small, "c": .small])
    }

    @Test func aMinimizedCallAsksForNothing() {
        let plan = CallSubscriptionPlan.plan(remoteUserIds: ["a", "b"], mainUserId: "a", visibleStripUserIds: ["b"], isSpeakerView: true, isMinimized: true)
        #expect(plan == ["a": .off, "b": .off])
    }

    @Test func onlyAChangedChoiceIsSentAndEveryoneStartsAtSmall() {
        let plan: [String: VideoQuality] = ["a": .full, "b": .small, "c": .off]
        let first = CallSubscriptionPlan.changes(from: [:], to: plan)
        #expect(first.map(\.userId) == ["a", "c"] && first.map(\.videoQuality) == [.full, .off])
        #expect(CallSubscriptionPlan.changes(from: plan, to: plan).isEmpty)
        #expect(CallSubscriptionPlan.changes(from: plan, to: plan, resendAll: true).count == 3)
        #expect(CallSubscriptionPlan.changes(from: ["a": .full], to: ["a": .small]).map(\.videoQuality) == [.small])
    }

    @Test func theMutationCarriesEachPersonAndTheirQuality() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SetChatCallVideoSubscriptions": NSNull()]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        try await connection.setChatCallVideoSubscriptions(id: "call1", subscriptions: [("a", .full), ("b", .off)])
        let sent = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests.last?.httpBody))
        #expect(sent["variables"]?["callId"]?.stringValue == "call1")
        let entries = try #require(sent["variables"]?["subscriptions"]?.arrayValue)
        #expect(entries.count == 2)
        #expect(entries[0]["userId"]?.stringValue == "a" && entries[0]["videoQuality"]?.stringValue == "full")
        #expect(entries[1]["userId"]?.stringValue == "b" && entries[1]["videoQuality"]?.stringValue == "off")
    }

    @Test func aLongListGoesInRequestsOfAtMostSixtyFour() async throws {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["SetChatCallVideoSubscriptions": NSNull()]])) }
        let connection = Connection(account: makeAccount(), transport: transport)
        let many = (0..<70).map { (userId: "u\($0)", videoQuality: VideoQuality.small) }
        try await connection.setChatCallVideoSubscriptions(id: "call1", subscriptions: many)
        #expect(transport.requests.count == 2)
    }

    @Test func theMaximumPersonCountComesFromTheServerOrFallsBack() async {
        let answering = ScriptedTransport { _ in (200, ScriptedTransport.json(["data": ["GetChatCallMaximumPersonCount": 12]])) }
        #expect(await Connection(account: makeAccount(), transport: answering).chatCallMaximumPersonCount() == 12)
        let failing = ScriptedTransport { _ in (200, ScriptedTransport.json(["errors": [["message": "unknown"]]])) }
        #expect(await Connection(account: makeAccount(), transport: failing).chatCallMaximumPersonCount() == ChatCallRules.maximumParticipants)
    }

    @Test func theServerOffersVideoSelectionWhenItHasTheMutation() {
        #expect(ServerCapabilities(mutationNames: ["SetChatCallVideoSubscriptions"]).offersVideoSelection)
        #expect(!ServerCapabilities().offersVideoSelection)
    }
}
