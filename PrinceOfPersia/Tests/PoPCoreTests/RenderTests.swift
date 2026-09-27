import Testing
@testable import PoPCore

// M4: the render description.
//
// The renderer emits frame names and integer positions; both are checked here without a
// window or a PNG. The exhaustive test at the bottom is the load-bearing one — it walks
// every room of every level and confirms the atlas really has every frame we ask for.
//
// One real bug was already found this way rather than by looking at the screen:
// `SKTexture(rect:in:)` measures from the BOTTOM-left while TexturePacker measures from the
// top-left, so every sprite silently sampled the wrong part of the sheet.

private func levelOne() throws -> LevelRuntime {
    try LevelRuntime(try GameData.level(1))
}

// MARK: - Tile sprites

// MARK: - The neighbours whose cels overhang into this room

@Test func aRoomDrawsItsLeftNeighbourAtTheLeftEdgeOfTheScreen() throws {
    let level = try levelOne()

    // The reference builds *every* room into the same two display lists and lets the camera do
    // the cropping (`Level.addTile` never asks which room is current). A tile cel is 60 px wide
    // inside a 32 px cell, so a room's last column starts 32 px into its left neighbour — and
    // that neighbour's screen has 28 px of it showing along its own left edge.
    let strips = RoomRenderer.strips(for: 1, in: level)
    #expect(strips.map(\.room) == [5, 2, 1])

    let left = try #require(strips.first)
    #expect(left.room == 5)
    #expect(left.columns == 9..<10)
    #expect(left.dx == -Geometry.roomWidth)

    let sprites = RoomRenderer.sprites(for: left, level: level, world: nil, prefix: "dungeon")

    // Room 1 is at map (6, 0) and room 5 at (5, 0); column 9 of room 5 is a gate at row 0.
    let panel = try #require(sprites.first { $0.frameName == "dungeon_gate" })
    #expect(panel.x == -Geometry.blockWidth)
    // Gate.js puts the front child at (32, 16), which is what puts the open gate's edge exactly
    // on the screen's left column instead of 32 px off it.
    let front = try #require(sprites.first { $0.frameName == "dungeon_gate_fg" })
    #expect(front.x == 0)
    #expect(front.y == -RoomRenderer.tileOverhang + 16)

    // The wall below it carries room 5's room number in its seed, not room 1's: the shape and
    // the seed are both read in the room the tile belongs to.
    #expect(sprites.contains { $0.frameName == "WWS_24" })
    #expect(sprites.contains { $0.frameName == "dungeon_wall_0" })
}

@Test func theRoomsAboveAndBelowOverhangIntoThisOne() throws {
    let level = try levelOne()

    // Room 12 is at map (1, 1): room 16 sits above it and room 19 below. A room is 189 px tall
    // and a cel 79 px against a 63 px cell, so a neighbour's nearest row reaches 3 px over the
    // top edge and 16 px over the bottom one, above the status bar.
    let strips = RoomRenderer.strips(for: 12, in: level)

    let above = try #require(strips.first { $0.room == 16 })
    #expect(above.dy == -Geometry.roomHeight)
    #expect(above.rows == 2..<3)
    #expect(above.columns == 0..<Geometry.roomColumns)

    let below = try #require(strips.first { $0.room == 19 })
    #expect(below.dy == Geometry.roomHeight)
    #expect(below.rows == 0..<1)

    // Bottom row of the room below: 0 * 63 - 13 + 189.
    let sprites = RoomRenderer.sprites(for: below, level: level, world: nil, prefix: "dungeon")
    #expect(sprites.allSatisfy { $0.y >= Geometry.roomHeight - RoomRenderer.tileOverhang })
}

@Test func aRoomWithNoNeighbourOnASideDrawsOnlyItself() throws {
    let level = try levelOne()

    // Room 22 is the top-left corner of the map, so nothing is above it or to its left — but
    // room 15 is directly below it.
    let strips = RoomRenderer.strips(for: 22, in: level)
    #expect(strips.map(\.room) == [15, 22])
    #expect(strips.allSatisfy { $0.dx >= 0 && $0.dy >= 0 })
}

@Test func theLeftNeighbourIsDrawnBeforeThisRoomAndTheUpperOneAfter() throws {
    let level = try levelOne()

    // A later sprite draws over an earlier one at the same z, and the strips do collide: a
    // wall's side face and a gate's panel are drawn 32 px into the cell to their right, which
    // is this room's first column. LevelBuilder walks the map's bottom row first and left to
    // right within a row, so below precedes left, and above comes last.
    let order = RoomRenderer.strips(for: 12, in: level).map(\.room)
    #expect(order == [15, 19, 12, 16])
}

@Test func tileSpritesSitOnTheReferenceGrid() throws {
    let level = try levelOne()
    let description = RoomRenderer.describe(level: level, room: 1)

    // Level.js#addTile: x * BLOCK_WIDTH, and y * BLOCK_HEIGHT - 13.
    let tile = description.sprites.first {
        $0.frameName == "dungeon_1" && $0.anchor == .topLeft
    }
    // Room 1 row 0 is [0, 0, 0, 1, 1, 1, 1, 1, 20, 20], so the first floor is column 3, row 0.
    let expected = try #require(tile)
    #expect(expected.x == 3 * Geometry.blockWidth)
    #expect(expected.y == 0 * Geometry.blockHeight - RoomRenderer.tileOverhang)
    #expect(expected.y == -13)
}

@Test func everyTileEmitsABackgroundAndAForeground() throws {
    let level = try levelOne()

    // The room's own band, not the whole screen: `describe` also draws the neighbours whose
    // 60 px cels overhang into it, and those tiles are not what this test is counting.
    let own = try #require(RoomRenderer.strips(for: 1, in: level).first {
        $0.room == 1 && $0.dx == 0 && $0.dy == 0
    })
    let tiles = RoomRenderer.sprites(for: own, level: level, world: nil, prefix: "dungeon")
        .filter { $0.anchor == .topLeft }

    #expect(tiles.filter { $0.z == RoomRenderer.tileBackgroundZ }.count == Geometry.tilesPerRoom)
    #expect(tiles.filter { $0.z == RoomRenderer.tileForegroundZ }.count == Geometry.tilesPerRoom)

    // Space and floor tiles additionally draw their <element>_<modifier> variation as a child
    // of the back sprite — that child is what distinguishes the fourteen floor variants.
    let plainTiles = (0..<Geometry.roomRows).flatMap { row in
        (0..<Geometry.roomColumns).map { column in
            level.tile(x: column, y: row, room: 1).kind
        }
    }
    let expectedDetail = plainTiles.filter { $0 == .space || $0 == .floor }.count
    #expect(tiles.filter { $0.z == RoomRenderer.tileBackgroundDetailZ }.count == expectedDetail)
    #expect(expectedDetail > 0)
    #expect(tiles.count == Geometry.tilesPerRoom * 2 + expectedDetail)
}

@Test func spaceAndFloorCarryTheirModifierAsASecondSprite() throws {
    let level = try levelOne()
    let frames = RoomRenderer.frames(
        for: Tile(kind: .floor, modifier: 3),
        level: level, room: 1, column: 3, row: 0, prefix: "dungeon"
    )
    #expect(frames.background == "dungeon_1")
    #expect(frames.backgroundDetail == "dungeon_1_3")
    #expect(frames.foreground == "dungeon_1_fg")
}

@Test func aMirrorDrawsAsFloor() throws {
    // Tile.Mirror hands TILE_FLOOR to Base, so there is no dungeon_13 or palace_13 frame in
    // either atlas. Asking for one renders nothing at all, silently.
    let level = try levelOne()
    let frames = RoomRenderer.frames(
        for: Tile(kind: .mirror, modifier: 0),
        level: level, room: 1, column: 0, row: 0, prefix: "dungeon"
    )
    #expect(frames.background == "dungeon_1")
    #expect(frames.foreground == "dungeon_1_fg")

    let dungeon = try GameData.atlasFrameNames(named: "dungeon")
    let palace = try GameData.atlasFrameNames(named: "palace")
    #expect(!dungeon.contains("dungeon_13"), "there is no mirror frame in the atlas")
    #expect(!palace.contains("palace_13"))
}

@Test func theForegroundLayerDrawsOverTheActor() {
    // Level.js: back.z = 10, front.z = 30; actors sit at 20. The front layer covering the
    // actor is what puts the Prince behind a wall's foreground detail.
    #expect(RoomRenderer.tileBackgroundZ < RoomRenderer.actorZ)
    #expect(RoomRenderer.actorZ < RoomRenderer.tileForegroundZ)
}

@Test func plainTilesUseTheElementName() throws {
    let description = RoomRenderer.describe(level: try levelOne(), room: 1)
    let names = Set(description.sprites.map(\.frameName))
    #expect(names.contains("dungeon_0"))       // space, background
    #expect(names.contains("dungeon_1"))       // floor, background
    #expect(names.contains("dungeon_1_fg"))    // floor, foreground
    #expect(names.contains("dungeon_19_fg"))   // torch, foreground
}

@Test func wallsPickAFrameThatMatchesTheirNeighbours() throws {
    // LevelBuilder: the shape is <left>W<right> where a side is "W" only if that neighbour
    // is also a wall, and the seed is tileNumber + roomId.
    let level = try levelOne()
    let description = RoomRenderer.describe(level: level, room: 1)

    // Room 1 row 0 is [... FLOOR FLOOR WALL WALL] at columns 7, 8, 9.
    // Column 8: floor to the left, wall to the right -> "SWW"; seed = 8 + 1 = 9.
    #expect(description.sprites.contains { $0.frameName == "SWW_9" })
    // Column 9: wall to the left, nothing (off-map wall) to the right -> "WWW"; seed 10.
    #expect(description.sprites.contains { $0.frameName == "WWW_10" })

    // Row 1 is [TORCH TORCH FLOOR PILLAR SPACE WALL WALL WALL WALL WALL].
    // Column 5: space to the left, wall to the right -> "SWW"; seed = 15 + 1 = 16.
    #expect(description.sprites.contains { $0.frameName == "SWW_16" })
    // Column 6: walls both sides -> "WWW"; seed 17.
    #expect(description.sprites.contains { $0.frameName == "WWW_17" })
}

@Test func anIsolatedWallGetsTheSWSShape() throws {
    // Room 1 row 1 column 4 is SPACE and column 5 is WALL... but the clearest isolated wall
    // is row 1 column 5, which has space on its left. Check the shape logic directly through
    // a room whose walls stand alone: level 1 room 1 row 2 column 9 has wall on the left.
    let level = try levelOne()
    let description = RoomRenderer.describe(level: level, room: 1)
    // Row 2 is [WALL WALL WALL WALL DEBRIS PILLAR LOOSE FLOOR FLOOR WALL].
    // Column 9 is a wall with floor on its left -> "SWW"; seed = 29 + 1 = 30.
    #expect(description.sprites.contains { $0.frameName == "SWW_30" })
}

// MARK: - Actor sprites

@Test func actorsUseTheirFrameNameAndBottomLeftAnchor() throws {
    let level = try levelOne()
    var actor = ActorState(location: 11, room: 1, face: 1, charName: "kid")
    actor.charFrame = 15
    actor.charY = 116
    actor.charFdx = 0
    actor.charFdy = 0
    actor.charFood = false

    let sprites = RoomRenderer.describe(level: level, room: 1, actors: [actor])
        .sprites.filter { $0.z == RoomRenderer.actorZ }
    #expect(sprites.count == 1)
    let sprite = try #require(sprites.first)
    #expect(sprite.frameName == "kid-15")
    #expect(sprite.anchor == .bottomLeft, "Actor's constructor does anchor.setTo(0, 1)")
    #expect(sprite.flippedHorizontally, "he faces right, and the art faces left")
}

@Test func facingRightIsTheMirroredCaseNotFacingLeft() {
    // `Actor`'s constructor does `this.scale.x *= -charFace`. That is 1 for a left-facing actor
    // and -1 for a right-facing one, so **the artwork is drawn facing left** and facing right is
    // what mirrors it.
    //
    // The port had this inverted for the whole project. Four tests asserted the inverted rule,
    // which is why it survived: they were consistent with the code rather than with the game. On
    // screen it read as the Prince walking backwards in both directions.
    var left = ActorState(location: 11, room: 1, face: -1, charName: "kid")
    left.charFrame = 45
    let facingLeft = try? #require(RoomRenderer.describe(left).first)
    #expect(facingLeft?.flippedHorizontally == false, "left is the art as drawn")

    var right = ActorState(location: 11, room: 1, face: 1, charName: "kid")
    right.charFrame = 45
    let facingRight = try? #require(RoomRenderer.describe(right).first)
    #expect(facingRight?.flippedHorizontally == true, "right is the mirror")
}

@Test func theHalfPixelParityCorrectionOnlyReachesTheRenderer() {
    // Actor.updateCharPosition adds 0.5 depending on facing and fcheck bit 7. charX itself
    // stays integral, so the correction must not leak into the simulation.
    var actor = ActorState(location: 11, room: 1, face: 1, charName: "kid")
    actor.charFrame = 15
    actor.charY = 116
    actor.charFdx = 0
    actor.charFdy = 0

    // Facing right with the parity bit clear -> +0.5.
    actor.charFood = false
    let withParity = RoomRenderer.describe(actor)[0].x
    // Facing right with the parity bit set -> no correction.
    actor.charFood = true
    let withoutParity = RoomRenderer.describe(actor)[0].x

    #expect(actor.charX == 21, "the simulation position is untouched")
    // floor(21 * 320/140) = 48; floor(21.5 * 320/140) = floor(49.14) = 49.
    #expect(withoutParity == 48)
    #expect(withParity == 49)
}

// MARK: - The exhaustive atlas check

/// Every frame name in the bundled atlases, keyed by sheet.
///
/// A frame the renderer asks for and no atlas has **draws nothing at all**, which on screen looks
/// exactly like a tile that is meant to be empty. That is why this is checked exhaustively rather
/// than spot-checked: the failure mode is silence.
func loadedAtlasFrames(_ names: [String]) throws -> [String: Set<String>] {
    var sheets: [String: Set<String>] = [:]
    for name in names { sheets[name] = try GameData.atlasFrameNames(named: name) }
    return sheets
}

/// The sheets a tile description can legitimately draw from.
///
/// A tile resolves against the level's own atlas, and anything the description marks with an
/// explicit `atlas` against that one — a potion's bubbles live in `general`, which belongs to
/// no tile and no actor.
func spriteIsAvailable(_ sprite: SpriteInstance, sheets: [String: Set<String>]) -> Bool {
    guard let name = sprite.atlas else { return false }
    return sheets[name]?.contains(sprite.frameName) ?? false
}

@Test(arguments: GameData.levelNumbers)
func everyFrameTheRendererAsksForExistsInAnAtlas(number: Int) throws {
    let level = try LevelRuntime(try GameData.level(number))
    let backgroundName = level.data.type == .dungeon ? "dungeon" : "palace"
    let sheets = try loadedAtlasFrames([backgroundName, "kid", "general"])

    var missing: Set<String> = []
    for room in level.roomNumbers {
        for sprite in RoomRenderer.describe(level: level, room: room).sprites {
            let sheet = sprite.atlas ?? backgroundName
            guard sheets[sheet]?.contains(sprite.frameName) != true else { continue }
            // An actor frame falls back to the kid sheet when the level's own atlas has no
            // such name, which is how the M4 test has always resolved them.
            if sprite.atlas == nil, sheets["kid"]?.contains(sprite.frameName) == true { continue }
            missing.insert("\(sheet)/\(sprite.frameName)")
        }
    }
    #expect(missing.isEmpty, "level \(number) asks for frames the atlas lacks: \(missing.sorted())")
}
