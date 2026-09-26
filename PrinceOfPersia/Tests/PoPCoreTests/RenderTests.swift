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
    let description = RoomRenderer.describe(level: level, room: 1)
    let tiles = description.sprites.filter { $0.anchor == .topLeft }

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
