import Foundation

/// CallTile is where one person's tile sits on the call's stage, in points from the stage's top leading corner.
public struct CallTile: Equatable, Sendable {
    public let index: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// CallTiling is the arithmetic of a call's stage: how tiles fill it, and where the small picture of oneself sits in a call of two.
public enum CallTiling {
    public static let spacing = 10.0

    /// The columns for `count` tiles on a stage. Up to four people use one to two columns that fill the stage; five to eight use
    /// two columns on a tall stage (a phone held upright) and, on a wide one (an iPad, or a phone on its side), whichever of two to
    /// four columns gives the largest tiles.
    public static func columnCount(count: Int, width: Double, height: Double, spacing: Double = spacing, isWide: Bool = false) -> Int {
        let wide = isWide || width >= height * 0.9
        switch count {
        case ...1: return 1
        case 2: return wide ? 2 : 1
        case 3: return width >= height * 1.3 ? 3 : 2
        case 4: return 2
        default:
            guard wide else { return 2 }
            var best = 2
            var bestArea = 0.0
            for columns in 2...4 {
                let rows = (count + columns - 1) / columns
                let tileWidth = (width - spacing * Double(columns - 1)) / Double(columns)
                let tileHeight = (height - spacing * Double(rows - 1)) / Double(rows)
                if tileWidth * tileHeight > bestArea {
                    bestArea = tileWidth * tileHeight
                    best = columns
                }
            }
            return best
        }
    }

    /// Frames that fill a `width` by `height` stage with `count` tiles. A last row with one tile in two columns is one wide tile; any
    /// other short last row is centered.
    public static func tiles(count: Int, width: Double, height: Double, spacing: Double = spacing, isWide: Bool = false) -> [CallTile] {
        guard count > 0, width > 0, height > 0 else { return [] }
        let columns = columnCount(count: count, width: width, height: height, spacing: spacing, isWide: isWide)
        let rows = (count + columns - 1) / columns
        let tileWidth = (width - spacing * Double(columns - 1)) / Double(columns)
        let tileHeight = (height - spacing * Double(rows - 1)) / Double(rows)
        var frames: [CallTile] = []
        for row in 0..<rows {
            let first = row * columns
            let inRow = min(columns, count - first)
            let y = Double(row) * (tileHeight + spacing)
            if inRow == 1, columns == 2 {
                frames.append(CallTile(index: first, x: 0, y: y, width: width, height: tileHeight))
                continue
            }
            let rowWidth = Double(inRow) * tileWidth + spacing * Double(inRow - 1)
            let start = (width - rowWidth) / 2
            for column in 0..<inRow {
                frames.append(CallTile(index: first + column, x: start + Double(column) * (tileWidth + spacing), y: y, width: tileWidth, height: tileHeight))
            }
        }
        return frames
    }

    /// The corners the small picture rests in.
    public enum Corner: CaseIterable, Equatable, Sendable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    /// The small picture of oneself: about a quarter of the stage's width, upright.
    public static func pictureInPictureSize(stageWidth: Double) -> (width: Double, height: Double) {
        let width = max(84, min(stageWidth * 0.26, 180))
        return (width, width * 4 / 3)
    }

    /// The top leading point of the small picture resting in `corner`.
    public static func pictureInPictureOrigin(corner: Corner, stageWidth: Double, stageHeight: Double, inset: Double = 12) -> (x: Double, y: Double) {
        let size = pictureInPictureSize(stageWidth: stageWidth)
        let left = inset
        let right = stageWidth - size.width - inset
        let top = inset
        let bottom = stageHeight - size.height - inset
        switch corner {
        case .topLeading: return (left, top)
        case .topTrailing: return (right, top)
        case .bottomLeading: return (left, bottom)
        case .bottomTrailing: return (right, bottom)
        }
    }

    /// The corner nearest to where the picture's center was let go.
    public static func nearestCorner(centerX: Double, centerY: Double, stageWidth: Double, stageHeight: Double) -> Corner {
        let isLeading = centerX < stageWidth / 2
        let isTop = centerY < stageHeight / 2
        switch (isTop, isLeading) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }
}
