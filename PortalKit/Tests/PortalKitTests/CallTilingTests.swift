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
