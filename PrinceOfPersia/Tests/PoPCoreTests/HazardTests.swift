import Testing
@testable import PoPCore

// M7c: spikes, potions and swords.
//
// Level 1 has nine spike fields, four potions and the sword. Room 6 of level 1 is the cleanest
// spike test in the game, because it is a trap the level designer built on purpose:
//
//   row 0:  T  F  rb .  P  F  F  T  F  P
//   row 1:  W  W  W  .  W  W  W  W  W  W
//   row 2:  W  W  W  S  S  W  W  W  W  W
//
// The raise button at (2,0) has open space to its right at (3,0), and a two-row shaft down to a
// spike field at (3,2). Walk right and you press the button and fall onto the spikes.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }
private func worldOne() throws -> World { World(try levelOne()) }

/// Room 6’s spike field, and the shaft that leads to it.
private func spikeRef() -> TileRef { TileRef(room: 6, x: 3, y: 2) }

// MARK: - The spike state machine

@Test func spikesRiseOverFiveFramesThenRetractOverFive() throws {
    var field = Spikes(modifier: 0)
    #expect(field.phase == .inactive)
    #expect(field.frameIndex == 0)

    #expect(field.raise() == .impaledBySpikes, "coming up out of the floor is what makes the noise")
    #expect(field.phase == .raising)
    for expected in 1...5 {
        field.update()
        #expect(field.frameIndex == expected)
    }
    // Frame 5 is the last raise step and immediately becomes the dwell.
    #expect(field.phase == .fullOut)
    #expect(field.frameIndex == 5, "fully out, whatever step the dwell is on")

    // Sixteen ticks at the top, then it drops.
    for _ in 0..<Spikes.dwellTicks { field.update() }
    #expect(field.phase == .fullOut)
    field.update()
    #expect(field.phase == .dropping)

    // The drop *skips* frame 3 outright: step 4, then 4-1=3, then the extra decrement makes it
    // 2. So the retraction is four ticks to the raise's five, and frame 3 never appears going
    // down even though it does going up.
    var frames: [Int] = []
    while field.phase != .inactive {
        field.update()
        frames.append(field.frameIndex)
    }
    #expect(frames == [4, 2, 1, 0], "frame 3 is skipped on the way down")
}

@Test func raisingAnAlreadyRaisedFieldOnlyRestartsTheDwell() throws {
    var field = Spikes(modifier: 0)
    field.raise()
    for _ in 0..<5 { field.update() }
    #expect(field.phase == .fullOut)
    field.update()
    #expect(field.step == 1)

    // Standing on a field that is already out resets the timer and makes no sound.
    #expect(field.raise() == nil)
    #expect(field.step == 0)
    #expect(field.phase == .fullOut)
}

@Test func theModifierPicksTheSpriteFrameNotTheBehaviour() {
    // The modifier is rewritten for the sprite only: 3-5 collapse to 5, 6 becomes 4, and
    // anything above 6 mirrors back down. Every shipped field is modifier 0, so this is engine
    // trivia — but the mortal flag is read *before* the rewrite, which is the part that would
    // be easy to get backwards.
    #expect(Spikes(modifier: 0).frame == 0)
    #expect(Spikes(modifier: 1).frame == 1)
    #expect(Spikes(modifier: 2).frame == 2)
    #expect(Spikes(modifier: 3).frame == 5)
    #expect(Spikes(modifier: 5).frame == 5)
    #expect(Spikes(modifier: 6).frame == 4)
    #expect(Spikes(modifier: 7).frame == 2)
    #expect(Spikes(modifier: 9).frame == 0)

    #expect(Spikes(modifier: 4).mortal, "mortal is modifier < 5, tested before the rewrite")
    #expect(!Spikes(modifier: 5).mortal)
}

// MARK: - Raising

@Test func levelOneRegistersEverySpikeFieldAsATrob() throws {
    // LevelBuilder only makes a trob of a field whose modifier is zero. Every spike in all
    // fourteen levels is modifier zero, so the guard excludes nothing — but it is there, and
    // this test is what would notice if a level ever broke the pattern.
    let world = try worldOne()
    let fields = world.state.trobs.compactMapValues(\.spikes)
    #expect(fields.count == 9, "level 1 has nine spike fields")
    #expect(fields.values.allSatisfy { $0.phase == .inactive })
}

@Test func walkingNearAFieldRaisesTheColumnBelowIt() throws {
    // The field is at (3,2) and the Prince is at (2,0) — two rows above it, in the next column
    // along. checkSpikes fires the column ahead when he is within five units of his tile edge,
    // and trySpikes walks *down* until a wall stops it.
    var world = try worldOne()
    var prince = world.actors[0]
    prince.room = 6
    prince.charBlockX = 2
    prince.charBlockY = 0
    prince.charFace = 1
    prince.charFdx = 0
    prince.charFfoot = 0
    prince.charY = CoordinateSpace.y(fromBlockY: 0)

    // Standing in the middle of his tile, the column ahead is *not* probed: his foot is 13 units
    // from the edge and the gate is 5. Column 2 is a wall at row 1 anyway, so nothing rises.
    prince.charX = CoordinateSpace.x(fromBlockX: 2)
    var atTheCentre: [ActorEffect] = []
    TileChecks.checkSpikes(&prince, world: &world, effects: &atTheCentre)
    #expect(atTheCentre.isEmpty)
    #expect(world.spikes(at: spikeRef())?.phase == .inactive)

    // Walk to the edge of the tile and the column ahead is probed. trySpikes walks *down* from
    // (3,0): space, space, and then the field at (3,2).
    prince.charX = 45
    #expect(FallCycle.distanceToEdge(prince) < 5, "close enough to the edge to look ahead")

    var effects: [ActorEffect] = []
    TileChecks.checkSpikes(&prince, world: &world, effects: &effects)

    #expect(world.spikes(at: spikeRef())?.phase == .raising)
    #expect(effects.contains(.sound(.impaledBySpikes)))

    // A field that is already up makes no sound when disturbed again.
    var again: [ActorEffect] = []
    TileChecks.checkSpikes(&prince, world: &world, effects: &again)
    #expect(again.isEmpty)
}

@Test func thePrinceIsImpaledFallingOntoARaisedField() throws {
    // The whole trap, played out: walk right from (1,0), press the button at (2,0), step into
    // the shaft and land on the spikes two rows down.
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    var prince = simulation.world.actors[0]
    prince.room = 6
    prince.charBlockX = 1
    prince.charBlockY = 0
    prince.charX = CoordinateSpace.x(fromBlockX: 1)
    prince.charY = CoordinateSpace.y(fromBlockY: 0)
    prince.charFace = 1
    simulation.world.actors[0] = prince

    for _ in 0..<30 { simulation.tick(intents: [.right]) }

    let dead = simulation.world.actors[0]
    #expect(!dead.isAlive)
    #expect(dead.health == 0)
    #expect(dead.action == "impale", "impaled, not merely fallen")
    #expect(dead.charBlockX == 3 && dead.charBlockY == 2, "on the field, not beside it")
    #expect(dead.room == 6)
}

@Test func landingOnSpikesIsLoudInTwoWays() throws {
    // One sound for the field coming up and one for the Prince. Losing either is the kind of
    // thing that only shows up as a game that feels subtly wrong.
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    var prince = simulation.world.actors[0]
    prince.room = 6
    prince.charBlockX = 1
    prince.charBlockY = 0
    prince.charX = CoordinateSpace.x(fromBlockX: 1)
    prince.charY = CoordinateSpace.y(fromBlockY: 0)
    prince.charFace = 1
    simulation.world.actors[0] = prince

    var heard: [SoundEffect] = []
    for _ in 0..<30 {
        simulation.tick(intents: [.right])
        for effect in simulation.effects {
            if case let .sound(sound) = effect { heard.append(sound) }
        }
    }
    #expect(heard.contains(.impaledBySpikes), "the field coming up")
    #expect(heard.contains(.spikedBySpikes), "the Prince landing on it")
}

// MARK: - Aligning to a tile

@Test func aBodyAlignsToTheTileItDiedOn() {
    // Fighter.alignToTile pins him two units inside the tile left edge when he faces left, and
    // one unit inside its right edge when he faces right. The asymmetry is the reference’s.
    var left = ActorState(location: 0, room: 5, face: -1, action: "stand", charName: "kid")
    FallCycle.alignToTile(&left, to: TileRef(room: 6, x: 3, y: 2))
    #expect(left.charX == CoordinateSpace.x(fromBlockX: 3) - 2)
    #expect(left.charY == CoordinateSpace.y(fromBlockY: 2))
    #expect(left.room == 6, "he is moved to the room the tile is in")

    var right = ActorState(location: 0, room: 5, face: 1, action: "stand", charName: "kid")
    FallCycle.alignToTile(&right, to: TileRef(room: 6, x: 3, y: 2))
    #expect(right.charX == CoordinateSpace.x(fromBlockX: 4) + 1)
    #expect(right.charX != left.charX)
}

@Test func aSpikeDeathDoesNotMoveASkeleton() throws {
    // dieSpikes and die both bail out for a skeleton: the bones cannot be killed twice.
    var skeleton = ActorState(location: 0, room: 1, face: 1, action: "stand", charName: "skeleton")
    skeleton.isAlive = true
    var effects: [ActorEffect] = []
    TileChecks.dieSpikes(&skeleton, effects: &effects)
    #expect(skeleton.isAlive)
    #expect(effects.isEmpty)
}
