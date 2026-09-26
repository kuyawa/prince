/// A decoded level, ready to be queried by the simulation.
///
/// Port source: `reference/PrinceJS/src/LevelBuilder.js` (the grid walk and link
/// derivation) and `Level.js#getTileAt`, `#getRoomX`, `#getRoomY`.
public struct LevelRuntime: Sendable {
    public let data: LevelData

    /// Room number to its position in the level's room grid.
    public let placements: [Int: RoomPlacement]

    /// Row-major room numbers, `-1` for gaps. `layout[y][x]`.
    public let layout: [[Int]]

    /// The tile the reference hands back for anywhere off the map — its `dummyWall`.
    ///
    /// `Level.js#getTileAt` returns this whenever `rooms[room]` is missing, which is
    /// why an actor walking into a gap in the level grid meets a wall rather than
    /// falling out of the world.
    public static let offMapTile = Tile(kind: .wall, modifier: 0)

    public init(_ data: LevelData) throws {
        try data.validate()
        self.data = data

        let width = data.size.width
        let height = data.size.height

        var layout: [[Int]] = []
        var placements: [Int: RoomPlacement] = [:]

        // LevelBuilder walks `index = y * width + x` and skips `id == -1`.
        for y in 0..<height {
            var row: [Int] = []
            for x in 0..<width {
                let index = y * width + x
                guard data.rooms.indices.contains(index) else {
                    row.append(-1)
                    continue
                }
                let room = data.rooms[index]
                row.append(room.exists ? room.id : -1)
                if room.exists {
                    placements[room.id] = RoomPlacement(id: room.id, column: x, row: y, tiles: room.tiles)
                }
            }
            layout.append(row)
        }

        // Links are derived from the grid, never stored — LevelBuilder.js.
        for (id, placement) in placements {
            placements[id]?.links = RoomLinks(
                up: Self.roomNumber(in: layout, column: placement.column, row: placement.row - 1),
                down: Self.roomNumber(in: layout, column: placement.column, row: placement.row + 1),
                left: Self.roomNumber(in: layout, column: placement.column - 1, row: placement.row),
                right: Self.roomNumber(in: layout, column: placement.column + 1, row: placement.row)
            )
        }

        self.layout = layout
        self.placements = placements
    }

    /// `LevelBuilder.getRoomId` — the reference returns **-1** both for off-grid
    /// coordinates and for a gap in the layout.
    ///
    /// Callers test `<= 0`, so -1 and 0 both mean "no room"; the distinction is kept
    /// because reproducing the reference's stored value matters when links are read
    /// directly, as `CMD_UP` does.
    private static func roomNumber(in layout: [[Int]], column: Int, row: Int) -> Int {
        guard layout.indices.contains(row), layout[row].indices.contains(column) else { return -1 }
        return layout[row][column]
    }

    public func placement(of room: Int) -> RoomPlacement? { placements[room] }

    public var roomNumbers: [Int] { placements.keys.sorted() }

    /// A tile, with the reference's off-map semantics.
    ///
    /// Out-of-room columns and rows resolve to `offMapTile`. The reference additionally
    /// follows room links across edges so that a tile one column past the right edge is
    /// the neighbour's first column — that path exists to serve `checkBarrier` and ledge
    /// grabbing, and lands with the rest of M3.
    public func tile(x: Int, y: Int, room: Int) -> Tile {
        guard let placement = placements[room],
              (0..<Geometry.roomColumns).contains(x),
              (0..<Geometry.roomRows).contains(y)
        else { return Self.offMapTile }
        return placement.tile(x: x, y: y)
    }
}

public struct RoomPlacement: Sendable, Equatable {
    public let id: Int
    public let column: Int
    public let row: Int
    public let tiles: [Tile]
    public internal(set) var links = RoomLinks(up: 0, down: 0, left: 0, right: 0)

    /// `tileNumber = y * 10 + x`, row 0 at the top of the room.
    public func tile(x: Int, y: Int) -> Tile {
        tiles[y * Geometry.roomColumns + x]
    }
}

extension LevelRuntime: ActorWorldQuery {
    public func roomLinks(_ room: Int) -> RoomLinks? {
        placements[room]?.links
    }
}

/// The slice of the world the movement code needs.
public protocol TileWorld: ActorWorldQuery {
    func tile(x: Int, y: Int, room: Int) -> Tile

    /// `Tile.Gate#canCross(height)` — whether a gate bars passage.
    ///
    /// Gates begin closed and open when a button is pressed, so "blocking" is the correct
    /// answer for a freshly loaded level. M7 wires the real animated state; until then
    /// the locomotion verbs behave exactly as they do at the start of a room.
    func gateBlocks(x: Int, y: Int, room: Int) -> Bool
}

public extension TileWorld {
    func gateBlocks(x: Int, y: Int, room: Int) -> Bool { true }
}



extension LevelRuntime: TileWorld {}
