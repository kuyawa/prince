import Testing
@testable import PoPCore

// M7c-2: the choppers.
//
// Level 3 room 16 is the cascade test in the game: three blades side by side on row 2, with open
// floor either side.
//
//   row 0:  W  W  W  T  T  Po F  .  .  W
//   row 1:  W  W  W  W  W  W  P  .  .  W
//   row 2:  P  F  P  CH CH CH P  F  F  W

private func levelThree() throws -> LevelRuntime { try LevelRuntime(try GameData.level(3)) }
private func worldThree() throws -> World { World(try levelThree()) }

/// Where the Prince has to stand for a given chopper to be in range.
///
/// Found by measuring `chopDistance` rather than by deriving it: the formula mixes a 60-pixel tile
/// cel with a 32-pixel cell, and the arithmetic is easier to trust than to re-derive.
private func standInRange(of column: Int, world: inout World) -> ActorState {
    var prince = world.actors[0]
    prince.room = 16
    prince.charBlockY = 2
    prince.charFace = 1
    // tryChopperTile spares an actor whose action is turn, and level 3 spawns turning.
    prince.action = "running"
    prince.charFrame = 14
    prince.charFdx = 0
    prince.charFfoot = 0
    prince.charFood = false
    // Seven x-units right of the centre of the column before the blades.
    prince.charBlockX = column - 1
    prince.charX = CoordinateSpace.x(fromBlockX: column - 1) + 7
    return prince
}

// MARK: - The blade cycle

@Test func theBladesCutOnlyOnTheFirstThreeStepsOfFifteen() {
    var chopper = Chopper()
    #expect(!chopper.isActive)
    #expect(chopper.frameIndex == 5, "the resting pose is frame 5; there is no frame 0")

    chopper.chop(audible: true)
    var cuts: [Int] = []
    var sounds: [SoundEffect] = []
    // Fifteen updates close a fifteen-step cycle: step counts 1...14 and the fifteenth resets it.
    for _ in 0...Chopper.lastStep {
        let outcome = chopper.update()
        if outcome.chopped { cuts.append(chopper.step) }
        if let sound = outcome.sound { sounds.append(sound) }
    }
    #expect(cuts == [Chopper.cutStep], "one cut per cycle, on step 3")
    #expect(sounds == [.slicerBladesClash])
    #expect(!chopper.isActive, "the cycle ends after fifteen steps")
}

@Test func anOffScreenChopperCutsSilently() {
    // `handleChop` passes `tile.room === currentCameraRoom`. A room away, the blades still move
    // and still cut — they just do it without a sound.
    var quiet = Chopper()
    quiet.chop(audible: false)
    var sound: SoundEffect?
    for _ in 0..<Chopper.lastStep {
        let outcome = quiet.update()
        if let heard = outcome.sound { sound = heard }
    }
    #expect(sound == nil)
}

@Test func theBladesRestOnFrameFiveAndNeverAskForFrameZero() {
    // The atlas has `dungeon_chopper_1` through `_5` and no `_0`: `update` increments before it
    // names a frame, so step 0 is never drawn.
    var chopper = Chopper()
    var frames: Set<Int> = [chopper.frameIndex]
    chopper.chop(audible: true)
    for _ in 0...Chopper.lastStep {
        chopper.update()
        frames.insert(chopper.frameIndex)
    }
    #expect(frames == [1, 2, 3, 4, 5])
    #expect(!frames.contains(0))
}

// MARK: - Distance

@Test func theCuttingWindowIsWhereTheBladesAre() throws {
    // Measured, not derived. Each blade owns a band about twelve screen pixels wide, and that
    // band sits just *before* the column the blades hang in — you are cut as you come under
    // them, not after you are past.
    var world = try worldThree()
    let atlas = world.level.atlasName

    let inRange = standInRange(of: 4, world: &world)
    let distance = TileChecks.chopDistance(inRange, tileColumn: 4, levelAtlas: atlas)
    #expect(abs(distance) < 6, "expected to be under the blades, got \(distance)")
    #expect(TileChecks.inChopDistance(inRange, tileColumn: 4, levelAtlas: atlas))

    // A whole column further back is safely clear.
    var far = inRange
    far.charX = CoordinateSpace.x(fromBlockX: 1)
    far.charBlockX = 1
    #expect(!TileChecks.inChopDistance(far, tileColumn: 4, levelAtlas: atlas))
}

@Test func aDrawnSwordWidensTheWindowByTenPixels() throws {
    // `6 + (swordDrawn ? 10 : 0)`. As the sprite widens, half its width pushes the centre
    // further from the blades, so the window has to widen with it or a fighting Prince could
    // never be hit at all.
    var world = try worldThree()
    let atlas = world.level.atlasName
    let prince = standInRange(of: 4, world: &world)

    // A little over six pixels off centre: missed unarmed, caught with the sword out.
    var offset = prince
    offset.charX += 6
    while TileChecks.inChopDistance(offset, tileColumn: 4, levelAtlas: atlas), offset.charX < 62 {
        offset.charX += 1
    }
    #expect(!TileChecks.inChopDistance(offset, tileColumn: 4, levelAtlas: atlas))

    offset.swordDrawn = true
    #expect(TileChecks.inChopDistance(offset, tileColumn: 4, levelAtlas: atlas))
}

@Test func theTileCelIsSixtyWideNotThirtyTwo() {
    // The number that makes `chopDistance` awkward: a dungeon tile cel is 60 x 79 packed at the
    // cell origin, so `tile.centerX` is the *cel* centre, 14 pixels right of the cell centre.
    #expect(SpriteMetrics.width(atlas: "dungeon", frame: "dungeon_18") == 60)
    #expect(SpriteMetrics.size(atlas: "dungeon", frame: "dungeon_18")?.height == 79)

    // And an actor really does change width from frame to frame.
    let standing = SpriteMetrics.actorWidth(charName: "kid", frame: 0)
    let running = SpriteMetrics.actorWidth(charName: "kid", frame: 8)
    #expect(standing != running, "a frame-dependent width is the whole reason for the table")
}

// MARK: - The cascade

@Test func wakingARowWakesItsLeftmostChopper() throws {
    var world = try worldThree()
    let left = TileRef(room: 16, x: 3, y: 2)
    #expect(world.chopper(at: left)?.isActive == false)

    // -1 is what an actor walking in passes: the leftmost blade in the row.
    world.activateChopper(after: -1, row: 2, room: 16, cameraRoom: 16)
    #expect(world.chopper(at: left)?.isActive == true)
    #expect(world.chopper(at: TileRef(room: 16, x: 4, y: 2))?.isActive == false,
            "only the leftmost one is woken directly")
}

@Test func aCutSetsTheNextChopperGoing() throws {
    // `onChopped` -> `Level.activateChopper(this.roomX, ...)`, and the scan starts one column to
    // the *right* of that. So a blade reaching its cut wakes the next one along, and a row of
    // three runs as a wave travelling right — which is what makes level 3's room 16 a hazard
    // rather than decoration.
    var world = try worldThree()
    let left = TileRef(room: 16, x: 3, y: 2)
    let middle = TileRef(room: 16, x: 4, y: 2)
    let right = TileRef(room: 16, x: 5, y: 2)

    // Start the left one only, audibly, and let it reach its cut.
    world.chopChopper(at: left, audible: true)

    var sounds: [SoundEffect] = []
    for _ in 0..<Chopper.cutStep {
        var effects: [ActorEffect] = []
        // Room 16 is where the camera is; otherwise the blades cut silently.
        world.update(effects: &effects, cameraRoom: 16)
        for effect in effects {
            if case let .sound(sound) = effect { sounds.append(sound) }
        }
    }
    #expect(world.chopper(at: middle)?.isActive == true, "the cut woke the next blade along")
    #expect(world.chopper(at: right)?.isActive == false, "only the next one, not the whole row")
    #expect(sounds.contains(.slicerBladesClash), "and it was heard, being the camera room")
}

@Test func aCascadeInAnotherRoomIsSilent() throws {
    var world = try worldThree()
    let left = TileRef(room: 16, x: 3, y: 2)
    var chopper = try #require(world.chopper(at: left))
    chopper.chop(audible: false)
    world.chopChopper(at: left, audible: false)

    var sounds: [SoundEffect] = []
    for _ in 0..<Chopper.cutStep {
        var effects: [ActorEffect] = []
        // The Prince is somewhere else entirely.
        world.update(effects: &effects, cameraRoom: 99)
        for effect in effects {
            if case let .sound(sound) = effect { sounds.append(sound) }
        }
    }
    #expect(!sounds.contains(.slicerBladesClash))
}

// MARK: - The death

@Test func thePrinceIsHalvedByAChopper() throws {
    var world = try worldThree()
    let blades = TileRef(room: 16, x: 4, y: 2)

    // Put the blades on their cutting step and stand him in range.
    var chopper = try #require(world.chopper(at: blades))
    chopper.chop(audible: true)
    for _ in 0..<(Chopper.cutStep - 1) { _ = chopper.update() }
    #expect(chopper.step == Chopper.cutStep - 1)
    world.chopChopper(at: blades, audible: true)
    world.advanceChoppers(to: Chopper.cutStep - 1)

    var prince = standInRange(of: 4, world: &world)
    world.actors[0] = prince

    var effects: [ActorEffect] = []
    TileChecks.checkChoppers(&prince, world: &world, effects: &effects)

    #expect(!prince.isAlive)
    #expect(prince.action == "halve")
    #expect(prince.health == 0)
    #expect(effects.contains(.sound(.halvedByChopper)))
    #expect(world.chopper(at: blades)?.showsBlood == true, "the stain is left behind")
}

@Test func standingInTheBandGetsHimCutWithinOneCycle() throws {
    // The end-to-end version: no hand-placed blade step, just the real tick loop. He stands still
    // in the blades' band and the cycle comes round to him inside fifteen ticks.
    var simulation = try Simulation(level: try levelThree(), seed: 1)
    var prince = simulation.world.actors[0]
    prince.room = 16
    prince.charBlockY = 2
    prince.charY = CoordinateSpace.y(fromBlockY: 2)
    prince.charFace = 1
    prince.action = "stand"
    prince.charFrame = 15
    prince.charFdx = 0
    prince.charFfoot = 3
    prince.charFood = false

    // Where the blades reach is a dozen pixels wide and depends on the actor’s own cel width, so
    // the honest way to place him is to ask. Scanning also documents that the band exists at all:
    // a require failure here would mean the window has closed up entirely.
    // Column 3 is the leftmost blade, and the leftmost is the one `checkChoppers` keeps running.
    let atlas = simulation.world.level.atlasName
    var found: Int?
    for x in 30...62 where found == nil {
        prince.charX = x
        prince.charBlockX = CoordinateSpace.blockX(fromX: x)
        if TileChecks.inChopDistance(prince, tileColumn: 3, levelAtlas: atlas) { found = x }
    }
    let startX = try #require(found, "a standing Prince has no position under the blades")
    prince.charX = startX
    prince.charBlockX = CoordinateSpace.blockX(fromX: startX)
    simulation.world.actors[0] = prince

    var ticks = 0
    while simulation.world.actors[0].isAlive, ticks < Chopper.lastStep + 1 {
        // Held in place each tick. A stationary Prince still drifts a unit or two as the stand
        // sequence settles, which is enough to leave a twelve-pixel window — and this test is
        // about the blades reaching him, not about the drift.
        var held = simulation.world.actors[0]
        held.charX = startX
        held.charBlockX = CoordinateSpace.blockX(fromX: startX)
        simulation.world.actors[0] = held
        simulation.tick(intents: [])
        ticks += 1
    }
    #expect(!simulation.world.actors[0].isAlive, "the blades never reached him in a full cycle")
    #expect(simulation.world.actors[0].action == "halve")
    #expect(ticks <= Chopper.lastStep, "cut on tick \(ticks)")
}

@Test func aTurningPrinceIsSpared() throws {
    var world = try worldThree()
    let blades = TileRef(room: 16, x: 4, y: 2)
    var chopper = try #require(world.chopper(at: blades))
    chopper.chop(audible: false)
    world.chopChopper(at: blades, audible: false)
    world.advanceChoppers(to: Chopper.cutStep - 1)

    var prince = standInRange(of: 4, world: &world)
    prince.action = "turn"
    world.actors[0] = prince

    var effects: [ActorEffect] = []
    TileChecks.checkChoppers(&prince, world: &world, effects: &effects)
    #expect(prince.isAlive, "the reference excludes turn, and only turn")
}

@Test func bonesDoNotBleed() throws {
    var world = try worldThree()
    let blades = TileRef(room: 16, x: 4, y: 2)
    var chopper = try #require(world.chopper(at: blades))
    chopper.chop(audible: false)
    world.chopChopper(at: blades, audible: false)
    world.advanceChoppers(to: Chopper.cutStep - 1)

    var skeleton = standInRange(of: 4, world: &world)
    skeleton.charName = "skeleton"
    skeleton.isAlive = true

    var effects: [ActorEffect] = []
    TileChecks.checkChoppers(&skeleton, world: &world, effects: &effects)
    #expect(skeleton.isAlive)
    #expect(!effects.contains(.sound(.halvedByChopper)))
}
