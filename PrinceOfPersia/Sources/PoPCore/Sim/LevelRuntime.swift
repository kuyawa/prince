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

    /// A tile by its flat index within a room, with no cross-room resolution.
    /// The tile atlas this level draws from: `dungeon` or `palace`.
    ///
    /// `LevelBuilder` picks it from the level type and every tile of a level shares it, which is
    /// why `chopDistance` can ask for it here rather than threading it through the check.
    public var atlasName: String { data.type == .dungeon ? "dungeon" : "palace" }

    public func tile(atIndex index: Int, room: Int) -> Tile {
        guard let placement = placements[room],
              (0..<Geometry.tilesPerRoom).contains(index)
        else { return Self.offMapTile }
        return placement.tiles[index]
    }

    /// Where a lookup actually landed, or `nil` when it fell off the map.
    ///
    /// `tile(x:y:room:)` throws this information away, but the interactive-tile layer needs it:
    /// a gate a column past an edge belongs to the *neighbouring* room, and looking its state up
    /// under the original room number would find nothing.
    public func resolve(x: Int, y: Int, room: Int) -> TileRef? {
        guard placements[room] != nil else { return nil }

        var newRoom: Int
        var newX = x
        let newY: Int

        let horizontal = roomX(room: room, x: x)
        if horizontal.room > 0 {
            newRoom = horizontal.room
            newX = horizontal.x
            let vertical = roomY(room: newRoom, y: y)
            newRoom = vertical.room
            newY = vertical.y
        } else {
            let vertical = roomY(room: room, y: y)
            newRoom = vertical.room
            newY = vertical.y
            if vertical.room > 0 {
                let second = roomX(room: newRoom, x: x)
                newRoom = second.room
                newX = second.x
            }
        }

        guard newRoom > 0, placements[newRoom] != nil,
              (0..<Geometry.roomColumns).contains(newX),
              (0..<Geometry.roomRows).contains(newY)
        else { return nil }

        return TileRef(room: newRoom, x: newX, y: newY)
    }

    public var roomNumbers: [Int] { placements.keys.sorted() }

    /// A tile, resolving across room edges exactly as `Level.js#getTileAt` does.
    ///
    /// ```js
    /// getRoomX: function (room, x) {
    ///   if (x < 0) { room = this.rooms[room].links.left;  x += 10; }
    ///   if (x > 9) { room = this.rooms[room].links.right; x -= 10; }
    ///   return { room, x };
    /// }
    /// getRoomY: function (room, y) {
    ///   if (y < 0) { room = this.rooms[room].links.up;   y += 3; }
    ///   if (y > 2) { room = this.rooms[room].links.down; y -= 3; }
    ///   return { room, y };
    /// }
    /// ```
    ///
    /// `getTileAt` applies X first; only if that produced no room does it apply Y and then X
    /// again. Anything landing outside a real room becomes `offMapTile` — the reference's
    /// `dummyWall`.
    ///
    /// **This is what makes room traversal work.** Without it the tile one column past a
    /// room's edge reads as a wall, so an actor at the threshold sees a barrier where the
    /// neighbouring room has open floor, and refuses to walk through.
    public func tile(x: Int, y: Int, room: Int) -> Tile {
        guard placements[room] != nil else { return Self.offMapTile }

        var newRoom: Int
        var newX = x
        let newY: Int

        let horizontal = roomX(room: room, x: x)
        if horizontal.room > 0 {
            newRoom = horizontal.room
            newX = horizontal.x
            let vertical = roomY(room: newRoom, y: y)
            newRoom = vertical.room
            newY = vertical.y
        } else {
            let vertical = roomY(room: room, y: y)
            newRoom = vertical.room
            newY = vertical.y
            if vertical.room > 0 {
                let second = roomX(room: newRoom, x: x)
                newRoom = second.room
                newX = second.x
            }
        }

        guard newRoom > 0, let placement = placements[newRoom],
              (0..<Geometry.roomColumns).contains(newX),
              (0..<Geometry.roomRows).contains(newY)
        else { return Self.offMapTile }

        return placement.tile(x: newX, y: newY)
    }

    /// `Level.js#getRoomX`. The second lookup deliberately reads the *updated* room's links,
    /// matching the reference — in practice the two branches cannot both fire.
    private func roomX(room: Int, x: Int) -> (room: Int, x: Int) {
        var room = room
        var x = x
        if x < 0 {
            room = placements[room]?.links.left ?? -1
            x += Geometry.roomColumns
        }
        if x >= Geometry.roomColumns {
            room = placements[room]?.links.right ?? -1
            x -= Geometry.roomColumns
        }
        return (room, x)
    }

    /// `Level.js#getRoomY`.
    private func roomY(room: Int, y: Int) -> (room: Int, y: Int) {
        var room = room
        var y = y
        if y < 0 {
            room = placements[room]?.links.up ?? -1
            y += Geometry.roomRows
        }
        if y >= Geometry.roomRows {
            room = placements[room]?.links.down ?? -1
            y -= Geometry.roomRows
        }
        return (room, y)
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

    /// The interactive tile at a position, if the world keeps any.
    ///
    /// `climbup` and `climbdown` need more than "does this gate block": they check whether it is
    /// mid-slam against a *different* height. A bare `LevelRuntime` has no trobs, which is why
    /// this defaults to `nil`.
    func trob(x: Int, y: Int, room: Int) -> Trob?

    /// Which tile a lookup names. A bare level cannot cross rooms, so the default is direct.
    func resolve(x: Int, y: Int, room: Int) -> TileRef?
}

public extension TileWorld {
    func gateBlocks(x: Int, y: Int, room: Int) -> Bool { true }
    func trob(x: Int, y: Int, room: Int) -> Trob? { nil }
    func resolve(x: Int, y: Int, room: Int) -> TileRef? { TileRef(room: room, x: x, y: y) }
}



extension LevelRuntime: TileWorld {}
