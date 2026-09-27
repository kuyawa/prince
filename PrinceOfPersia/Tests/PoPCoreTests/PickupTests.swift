import Testing
@testable import PoPCore

// M7c: potions and the sword.
//
// Level 1 has four potions, all of them plain red RECOVER ones, and exactly one sword — in
// room 15. Two usable positions, both reached by dropping onto the tile:
//
//   room 15 (2,2)  the sword, under a two-row shaft from (2,0)
//   room 17 (3,2)  a potion, with open floor above it at (3,1)
//
// The pickup key is the action key pressed *without* down: the reference checks up, then down,
// then the pickup key, so holding down gives a plain crouch and never reaches the item.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

/// A Prince standing on a chosen tile, with the level’s guards left where they are.
private func princeOnTile(_ x: Int, _ y: Int, room: Int) throws -> Simulation {
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    var prince = simulation.world.actors[0]
    prince.room = room
    prince.charBlockX = x
    prince.charBlockY = y
    prince.charX = CoordinateSpace.x(fromBlockX: x)
    prince.charY = CoordinateSpace.y(fromBlockY: y)
    prince.charFace = 1
    simulation.world.actors[0] = prince
    return simulation
}

// MARK: - The bottle itself

@Test func aPotionsColourComesFromItsModifier() {
    #expect(Potion(modifier: 1).color == "red")
    #expect(Potion(modifier: 2).color == "red")
    #expect(Potion(modifier: 3).color == "green")
    #expect(Potion(modifier: 4).color == "green")
    #expect(Potion(modifier: 5).color == "blue")

    // The sprite variant is clamped to 1...5, but `isSpecial` tests the raw modifier, and
    // `POTION_SPECIAL` is 6.
    #expect(Potion(modifier: 9).modifier == 5)
    #expect(Potion(modifier: 0).modifier == 1)
    #expect(Potion(modifier: 6).isSpecial)
    #expect(!Potion(modifier: 5).isSpecial)
}

@Test func eachModifierMapsToItsOwnEffect() {
    #expect(Potion(modifier: 1).effect == .recover)
    #expect(Potion(modifier: 2).effect == .add)
    #expect(Potion(modifier: 3).effect == .buffer)
    #expect(Potion(modifier: 4).effect == .flip)
    #expect(Potion(modifier: 5).effect == .damage)

    // Only two of the five play music, and only the poison plays a one-shot.
    #expect(PotionEffect.recover.music == .potion1)
    #expect(PotionEffect.add.music == .potion2)
    #expect(PotionEffect.buffer.music == nil)
    #expect(PotionEffect.damage.sound == .stabbedByOpponent)
    #expect(PotionEffect.recover.sound == nil)
}

@Test func theBubblesCycleThroughSevenFrames() {
    var potion = Potion(modifier: 1)
    var seen: [Int] = []
    for _ in 0..<14 {
        seen.append(potion.step)
        potion.update()
    }
    #expect(Set(seen).count == Potion.bubbleFrames)
    #expect(potion.step == seen[0], "and back to where it started after two cycles")
}

@Test func theSwordGlintsOnItsOwnSchedule() throws {
    var sword = Sword()
    #expect(!sword.isBright)
    let firstInterval = sword.tick
    #expect(firstInterval >= Sword.minTick && firstInterval < Sword.maxTick)

    // Each update counts one tick up to the interval, flashes for exactly that one tick, then
    // steps a new interval. So the flash positions *are* the intervals, accumulated.
    var flashes: [Int] = []
    for tick in 1...400 {
        sword.update()
        if sword.isBright { flashes.append(tick) }
    }
    #expect(flashes.first == firstInterval, "the first glint lands on the interval it started with")
    #expect(flashes.count >= 3, "and it keeps glinting")

    // A flash lasts exactly one tick: two in a row would mean the reset was lost.
    let distinct = Set(flashes)
    #expect(distinct.count == flashes.count)
    let gaps = zip(flashes, flashes.dropFirst()).map { $1 - $0 }
    #expect(gaps.allSatisfy { $0 >= Sword.minTick && $0 < Sword.maxTick })
}

@Test func takingAPotionLeavesPlainFloor() throws {
    // `Level.removeObject` splices the tile out of `trobs` and replaces it with floor. Losing
    // the splice is how a bottle gets drunk twice.
    var world = World(try levelOne())
    let ref = TileRef(room: 17, x: 3, y: 2)
    #expect(world.state.trob(at: ref)?.potion != nil)

    world.removeObject(at: ref)
    #expect(world.state.trob(at: ref) == nil)
    #expect(world.tile(x: 3, y: 2, room: 17).kind == .floor)
    #expect(world.tile(x: 3, y: 2, room: 17).modifier == 0)
}

// MARK: - And what is drawn afterwards

@Test func aDrankPotionIsNoLongerDrawn() throws {
    // The simulation half of this is `takingAPotionLeavesPlainFloor`; this is the other half, and
    // it was the half that was missing. `removeObject` replaces the tile with floor as an
    // *override*, and the renderer used to read the immutable level — so a drunk bottle stayed on
    // the floor for ever while the Prince drank from a copy of it.
    var world = World(try levelOne())
    let cell = { (s: [SpriteInstance]) in
        s.filter { $0.x == 3 * Geometry.blockWidth && $0.y == 2 * Geometry.blockHeight - 13 }
            .map(\.frameName)
    }

    let before = cell(RoomRenderer.describe(world: world, room: 17).sprites)
    #expect(before.contains { $0.hasPrefix("dungeon_10") }, "the bottle is drawn: \(before)")

    world.removeObject(at: TileRef(room: 17, x: 3, y: 2))
    let after = cell(RoomRenderer.describe(world: world, room: 17).sprites)
    #expect(!after.contains { $0.hasPrefix("dungeon_10") }, "it is gone: \(after)")
    #expect(after.contains("dungeon_1"), "plain floor is left: \(after)")
}

@Test func aTakenSwordIsNoLongerDrawn() throws {
    // Same override, same bug: "the sword of the first guard is sometimes shown, sometimes not".
    var simulation = try princeOnTile(2, 2, room: 15)
    let cell = { (s: [SpriteInstance]) in
        s.filter { $0.x == 2 * Geometry.blockWidth && $0.y == 2 * Geometry.blockHeight - 13 }
            .map(\.frameName)
    }

    let before = cell(
        RoomRenderer.describe(world: simulation.world, room: 15).sprites
    )
    #expect(before.contains { $0.hasPrefix("dungeon_22") }, "the sword is drawn: \(before)")

    for _ in 0..<8 { simulation.tick(intents: [.action]) }
    #expect(simulation.world.tile(x: 2, y: 2, room: 15).kind == .floor)

    let after = cell(
        RoomRenderer.describe(world: simulation.world, room: 15).sprites
    )
    #expect(!after.contains { $0.hasPrefix("dungeon_22") }, "it is gone: \(after)")
    #expect(after.contains("dungeon_1"), "plain floor is left: \(after)")
}

// MARK: - Picking up

@Test func thePrinceTakesTheSwordInLevelOne() throws {
    // Room 15, (2,2). The action key alone: down would crouch past it.
    var simulation = try princeOnTile(2, 2, room: 15)
    let swordRef = TileRef(room: 15, x: 2, y: 2)
    #expect(simulation.world.state.trob(at: swordRef)?.sword != nil)

    var music: [MusicTrack] = []
    for _ in 0..<8 {
        simulation.tick(intents: [.action])
        for effect in simulation.effects {
            if case let .music(track) = effect { music.append(track) }
        }
    }

    #expect(simulation.world.actors[0].hasSword)
    #expect(simulation.world.actors[0].action == "pickupsword")
    #expect(simulation.world.state.trob(at: swordRef) == nil, "the sword is gone from the floor")
    #expect(simulation.world.tile(x: 2, y: 2, room: 15).kind == .floor)
    #expect(music.contains(.victory))
}

@Test func drinkingAPotionQueuesItsEffectRatherThanApplyingIt() throws {
    // The reference wraps the whole switch in a one-second delay so the animation reads. The
    // bottle goes immediately; what it does waits twelve ticks.
    var simulation = try princeOnTile(3, 2, room: 17)
    simulation.world.actors[0].health = 1

    for _ in 0..<4 { simulation.tick(intents: [.action]) }
    #expect(simulation.world.actors[0].action == "drinkpotion")
    #expect(simulation.world.pendingPotions.count == 1, "queued once, not once per stage")
    #expect(simulation.world.actors[0].health == 1, "not healed yet")

    // Twelve ticks later it lands.
    for _ in 0..<12 { simulation.tick(intents: []) }
    #expect(simulation.world.actors[0].health == 2, "RECOVER heals one")
    #expect(simulation.world.pendingPotions.isEmpty)
}

@Test func theFourPotionEffectsDoWhatTheySay() throws {
    // Applied directly rather than through a level, because only level 3 has a buffer potion
    // and only two levels have a flip one — no single level exercises all five.
    func drink(_ effect: PotionEffect, from start: (health: Int, max: Int)) throws -> ActorState {
        var simulation = try princeOnTile(3, 2, room: 17)
        simulation.world.actors[0].health = start.health
        simulation.world.actors[0].maxHealth = start.max
        simulation.world.queuePotionForTesting(effect)
        for _ in 0..<13 { simulation.tick(intents: []) }
        return simulation.world.actors[0]
    }

    // RECOVER heals one and stops at the ceiling.
    #expect(try drink(.recover, from: (1, 3)).health == 2)
    #expect(try drink(.recover, from: (3, 3)).health == 3)

    // ADD raises the ceiling and fills to it, capped at ten.
    let added = try drink(.add, from: (2, 3))
    #expect(added.maxHealth == 4)
    #expect(added.health == 4)
    #expect(try drink(.add, from: (1, 10)).maxHealth == 10)

    // BUFFER turns on the float, which is what makes a long fall survivable.
    let floating = try drink(.buffer, from: (3, 3))
    #expect(floating.isInFloat)
    #expect(floating.floatTicksRemaining > 0)

    // DAMAGE costs a point.
    #expect(try drink(.damage, from: (3, 3)).health == 2)
}

@Test func theFloatPotionWearsOffAfterEighteenSeconds() throws {
    var simulation = try princeOnTile(3, 2, room: 17)
    simulation.world.queuePotionForTesting(.buffer)
    for _ in 0..<13 { simulation.tick(intents: []) }
    #expect(simulation.world.actors[0].isInFloat)

    // 216 ticks is 18 s at 1/12 s, and it clears on the last one.
    for _ in 0..<World.floatTicks { simulation.tick(intents: []) }
    #expect(!simulation.world.actors[0].isInFloat)
    #expect(simulation.world.actors[0].floatTicksRemaining == 0)
}

@Test func aFloatingPrinceSurvivesAFallThatWouldOtherwiseKillHim() throws {
    // `land` reads `this.inFloat ? 0 : this.fallingBlocks`, so the float potion is escape from
    // any drop, not merely a soft landing.
    var simulation = try princeOnTile(3, 0, room: 14)
    simulation.world.actors[0].isInFloat = true
    simulation.world.actors[0].floatTicksRemaining = World.floatTicks

    for _ in 0..<40 { simulation.tick(intents: []) }
    #expect(simulation.world.actors[0].isAlive, "he floated down")
}

@Test func drinkingTwiceIsNotPossibleWithOneBottle() throws {
    // The tile is gone after the first drink, so the second press finds nothing and simply
    // lets him stand up.
    var simulation = try princeOnTile(3, 2, room: 17)
    for _ in 0..<30 { simulation.tick(intents: [.action]) }
    #expect(simulation.world.pendingPotions.isEmpty)
    #expect(simulation.world.state.trob(at: TileRef(room: 17, x: 3, y: 2)) == nil)
}

// MARK: - The effect channel applies each effect once

@Test func anEffectIsAppliedOnceEvenThoughTheTickAppliesSeveralTimes() throws {
    // `effects` accumulates across a whole tick and the world is handed the new ones after each
    // stage. Handing it the *whole* array each time meant a counting effect ran once per later
    // stage — a potion drunk once was queued three times and its theme played three times over.
    var simulation = try princeOnTile(3, 2, room: 17)
    for _ in 0..<6 { simulation.tick(intents: [.action]) }
    #expect(simulation.world.pendingPotions.count == 1)

    var themes = 0
    for _ in 0..<12 {
        simulation.tick(intents: [])
        for effect in simulation.effects {
            if case .music = effect { themes += 1 }
        }
    }
    #expect(themes == 1, "the Potion1 theme played \(themes) times")
}
