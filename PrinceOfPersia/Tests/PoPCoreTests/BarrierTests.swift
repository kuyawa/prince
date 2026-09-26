import Testing
@testable import PoPCore

// M3c: `checkBarrier` and the bump.
//
// This was the last stub in the port. Everything here is measured screen geometry over cel sizes
// from the atlas, so the tests are mostly about *which* rectangle the reference asks for and how
// far apart the two of them are.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

/// A kid interpreter: the bump chain runs the sequence, and `bump` and `bumpfall` both step it.
private func kidInterpreter() -> SequenceInterpreter {
    SequenceInterpreter(
        table: try! GameData.animationTable(named: "kid"), actorClass: .kid
    )
}

/// Level 1 room 17, row 2: `W W P Po P F F W W W`. Columns 5 and 6 are floor, column 7 is wall.
private func princeWalkingAtWall() throws -> (World, ActorState) {
    var world = World(try levelOne())
    var prince = world.actors[0]
    prince.room = 17
    prince.charBlockX = 6
    prince.charBlockY = 2
    prince.charY = CoordinateSpace.y(fromBlockY: 2)
    prince.charFace = 1
    prince.action = "running"
    prince.charFrame = 8
    prince.charFdx = 0
    prince.charFfoot = 0
    prince.charFood = false
    prince.charX = CoordinateSpace.x(fromBlockX: 6)
    world.actors[0] = prince
    return (world, prince)
}

// MARK: - The rectangles

@Test func touchingCountsAsIntersectingButEmptyDoesNot() {
    // Phaser tests separation with strict comparisons — a.right < b.x — so two rectangles that
    // share an edge are NOT separated and therefore DO intersect. An off-by-one here moves where a
    // wall stops the Prince by a pixel, which is the kind of thing that feels wrong without ever
    // looking wrong.
    let a = ScreenRect(x: 0, y: 0, width: 10, height: 10)
    let touching = ScreenRect(x: 10, y: 0, width: 10, height: 10)
    let clear = ScreenRect(x: 11, y: 0, width: 10, height: 10)
    let overlapping = ScreenRect(x: 9, y: 0, width: 10, height: 10)

    #expect(a.intersects(touching), "a.right == b.x is not separated")
    #expect(a.intersects(overlapping))
    #expect(a.intersects(a))
    #expect(!a.intersects(clear), "one pixel further apart and it is")

    // A rectangle with no area never intersects anything. That is how a tile whose cel is missing
    // from the atlas stops colliding, rather than colliding with the whole room.
    let empty = ScreenRect(x: 5, y: 5, width: 0, height: 10)
    #expect(!a.intersects(empty))
    #expect(!empty.intersects(a))
}

@Test func aTilesTwoBoundsDisagreeOnPurpose() throws {
    let world = World(try levelOne())
    let wall = world.tile(x: 7, y: 2, room: 17)
    let atlas = world.atlasName

    // `getBounds`: a four-pixel strip forty pixels into the cell — which is eight pixels past a
    // 32-pixel cell, in the next one. Not a typo.
    let bounds = wall.screenBounds(column: 7, row: 2)
    #expect(bounds.x == 7 * 32 + 40)
    #expect(bounds.width == 4)
    #expect(bounds.height == 63)
    #expect(bounds.y == 2 * 63)

    // `getBoundsAbs`: the full cel at the tile origin, which carries the 13-pixel overhang.
    let abs = wall.screenBoundsAbs(column: 7, row: 2, atlas: atlas)
    #expect(abs.x == 7 * 32)
    #expect(abs.y == 2 * 63 - Geometry.tileOverhang)
    #expect(abs.width == SpriteMetrics.width(atlas: atlas, frame: "dungeon_20"))
    #expect(abs.height == 63, "a flat 63, not the cel height")
}

@Test func anActorsTwoBoundsAreAlsoDifferent() throws {
    let (_, prince) = try princeWalkingAtWall()

    let fromFrameData = prince.charBounds()
    let fromTheSprite = prince.charBoundsAbs()

    #expect(fromFrameData.height == prince.celSize().height)
    #expect(fromTheSprite.height == prince.celSize().height)
    #expect(fromFrameData != fromTheSprite, "they are built from different things, and differ")

    // Facing right the body is drawn to the *left* of the origin: all but five pixels of the
    // width are subtracted. Facing left it is not.
    var mirrored = prince
    mirrored.charFace = -1
    #expect(mirrored.charBounds().x > prince.charBounds().x)
}

@Test func aMirrorCollidesAsWideAsAFloorTile() throws {
    // `Tile.Mirror` hands `TILE_FLOOR` to `Base`, so there is no `dungeon_13` cel at all and the
    // mirror is as wide as a floor tile. Reading its own element would give a width of zero and a
    // collision rectangle that never fires.
    let world = World(try LevelRuntime(try GameData.level(4)))
    let atlas = world.atlasName
    let mirror = Tile(kind: .mirror, modifier: 0)
    #expect(mirror.collisionElement == TileKind.floor.rawValue)
    #expect(mirror.screenBoundsAbs(column: 0, row: 0, atlas: atlas).width > 0)
}

// MARK: - Which actions are checked

@Test func theCheckIsSkippedForActionsThatOwnTheirOwnMovement() {
    for action in ["jumpup", "highjump", "climbup", "climbdown", "climbfail",
                   "stand", "turn", "fastsheathe", "jumphanglong", "jumpbackhang"] {
        #expect(Barrier.skips(action), "\(action) should skip the check")
    }

    // The two prefix tests. `step` covers `step`, `step2`...`step14` and `stepfall`.
    for action in ["step", "step3", "step13", "stepfall"] {
        #expect(Barrier.skips(action), "\(action) is a step")
    }

    // Every hang except `hangdrop`, which is a Prince dropping and so able to hit something.
    #expect(Barrier.skips("hang"))
    #expect(Barrier.skips("hangstraight"))
    #expect(!Barrier.skips("hangdrop"))

    #expect(!Barrier.skips("running"))
    #expect(!Barrier.skips("freefall"))
    #expect(!Barrier.skips("bump"))
}

// MARK: - The bump

@Test func runningIntoAWallStopsHimAndBumps() throws {
    var (world, prince) = try princeWalkingAtWall()
    let atlas = world.atlasName

    // Find the position where the collision actually fires: it is a few pixels wide and depends
    // on his cel, so asking beats guessing.
    var start: Int?
    for x in 91...110 where start == nil {
        var probe = prince
        probe.charX = x
        let context = kidInterpreter()
        var effects: [ActorEffect] = []
        _ = try? Barrier.checkBarrier(
            &probe, world: world, interpreter: context, effects: &effects
        )
        if probe.action == "bump" { start = x }
    }
    let hitAt = try #require(start, "no position in the row bumps into the wall")

    prince.charX = hitAt
    world.actors[0] = prince
    let interpreter = kidInterpreter()
    var effects: [ActorEffect] = []
    let bumped = try Barrier.checkBarrier(
        &prince, world: world, interpreter: interpreter, effects: &effects
    )

    #expect(bumped)
    #expect(prince.action == "bump")
    #expect(prince.bumpTimer == 10)
    #expect(effects.contains(.sound(.bumpIntoWallSoft)))
    #expect(prince.charX <= hitAt, "a bump never moves him forward")
    #expect(atlas == "dungeon")
}

@Test func theBumpSoundIsRateLimited() throws {
    // `bumpSound` bails while `bumpTimer` is running. Without it a Prince held against a wall
    // plays the thud every tick, which is a buzz rather than a bump.
    var prince = ActorState(location: 0, room: 1, face: 1, action: "running", charName: "kid")
    var effects: [ActorEffect] = []

    Barrier.bumpSound(&prince, effects: &effects)
    #expect(prince.bumpTimer == 10)
    #expect(effects.count == 1)

    Barrier.bumpSound(&prince, effects: &effects)
    #expect(effects.count == 1, "still rate-limited")

    prince.bumpTimer = 0
    Barrier.bumpSound(&prince, effects: &effects)
    #expect(effects.count == 2)
}

@Test func aStandingBumpAlignsHimToTheFloor() throws {
    var (world, prince) = try princeWalkingAtWall()
    prince.charY -= 9
    let interpreter = kidInterpreter()
    var effects: [ActorEffect] = []

    Barrier.setBump(&prince, world: world, effects: &effects)
    #expect(prince.action == "bump")
    #expect(prince.charY == CoordinateSpace.y(fromBlockY: 2), "back onto his row")
    #expect(!prince.isInJumpUp)
}

@Test func aSwordInHandReversesTheKnockback() {
    // `startFall` sets `backwardsFall = this.swordDrawn ? -1 : 1`. So a fighting Prince who bumps
    // into a wall is shoved *forward* — into his opponent rather than away from the wall.
    var unarmed = ActorState(location: 0, room: 1, face: 1, action: "stepfall", charName: "kid")
    unarmed.swordDrawn = false
    #expect(unarmed.backwardsFall == 1, "the default")

    var armed = ActorState(location: 0, room: 1, face: 1, action: "turn", charName: "kid")
    armed.swordDrawn = true
    let interpreter = kidInterpreter()
    var ignored: [ActorEffect] = []
    let world = World(try! LevelRuntime(try! GameData.level(1)))
    try? FallCycle.startFall(&armed, world: world, interpreter: interpreter, effects: &ignored)
    #expect(armed.backwardsFall == -1)
}

@Test func aDeadActorNeverBumps() throws {
    var (world, prince) = try princeWalkingAtWall()
    prince.isAlive = false
    prince.charX = 105
    let interpreter = kidInterpreter()
    var effects: [ActorEffect] = []
    let bumped = try Barrier.checkBarrier(
        &prince, world: world, interpreter: interpreter, effects: &effects
    )
    #expect(!bumped)
    #expect(effects.isEmpty)
}
