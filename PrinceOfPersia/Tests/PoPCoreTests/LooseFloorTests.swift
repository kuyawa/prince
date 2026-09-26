import Testing
@testable import PoPCore

// M6d: `floorStopFall` — what happens when a collapsing board finishes falling.
//
// Two halves, and the second is the one that is easy to miss: the board leaves rubble on the tile
// it lands on, *and* anything standing there takes a wound.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

/// A loose board with something solid directly beneath it, so the board has somewhere to land.
private func boardOverFloor(_ world: World) -> TileRef? {
    for (ref, trob) in world.state.trobs where trob.looseBoard != nil {
        for row in (ref.y + 1)..<Geometry.roomRows {
            let below = world.level.tile(x: ref.x, y: row, room: ref.room)
            if below.kind != .space { return ref }
        }
    }
    return nil
}

@Test func aBoardThatLandsLeavesRubbleOnTheFloorBeneath() throws {
    var world = World(try levelOne())
    let ref = try #require(boardOverFloor(world), "level 1 has a board over a floor")

    // Shake it hard enough to give way, then run it down.
    world.shakeLooseBoard(at: ref)
    var sounds: [SoundEffect] = []
    for _ in 0..<40 {
        var effects: [ActorEffect] = []
        world.update(effects: &effects)
        for effect in effects {
            if case let .sound(sound) = effect { sounds.append(sound) }
        }
        if !world.state.lastLandings.isEmpty { break }
    }

    let landing = try #require(world.state.lastLandings.first, "the board should have landed")
    #expect(landing.x == ref.x, "it falls straight down")
    #expect(landing.y > ref.y)
    #expect(landing.room == ref.room)

    // `addDebris` — the tile it landed on is now rubble, and the landing is audible.
    #expect(world.tile(x: landing.x, y: landing.y, room: landing.room).kind == .debris)
    #expect(sounds.contains(.looseFloorLands))

    // And the hole it left is still a hole.
    #expect(world.tile(x: ref.x, y: ref.y, room: ref.room).kind == .space)
}

@Test func aBoardLandingOnThePrinceWoundsHim() throws {
    // `damageStruck` does not take a point off directly. It sets `fallingBlocks = 2` and calls the
    // ordinary landing, so the board reuses the medium-landing path — which is why a board can
    // finish off a Prince who is already at one health.
    var world = World(try levelOne())
    let ref = try #require(boardOverFloor(world), "level 1 has a board over a floor")

    // Work out where it will land, and stand him there.
    var landing = ref
    for row in (ref.y + 1)..<Geometry.roomRows {
        if world.level.tile(x: ref.x, y: row, room: ref.room).kind != .space {
            landing = TileRef(room: ref.room, x: ref.x, y: row)
            break
        }
    }

    var prince = world.actors[0]
    prince.room = landing.room
    prince.charBlockX = landing.x
    prince.charBlockY = landing.y
    prince.charX = CoordinateSpace.x(fromBlockX: landing.x)
    prince.charY = CoordinateSpace.y(fromBlockY: landing.y)
    prince.action = "stand"
    prince.charFrame = 15
    prince.health = 3
    world.actors[0] = prince

    world.shakeLooseBoard(at: ref)
    let interpreter = makeKidInterpreter()
    for _ in 0..<40 {
        var effects: [ActorEffect] = []
        world.update(effects: &effects, interpreter: interpreter)
        if world.actors[0].health < 3 { break }
    }

    #expect(world.actors[0].health == 2, "a board on the head costs a point")
    #expect(world.actors[0].action == "medland", "and it arrives as a medium landing")
}

@Test func aBoardLandingOnOneHealthFinishesHim() throws {
    // The consequence of reusing `land`: at one health, `damageLife` calls `die`.
    var world = World(try levelOne())
    let ref = try #require(boardOverFloor(world))

    var landing = ref
    for row in (ref.y + 1)..<Geometry.roomRows {
        if world.level.tile(x: ref.x, y: row, room: ref.room).kind != .space {
            landing = TileRef(room: ref.room, x: ref.x, y: row)
            break
        }
    }

    var prince = world.actors[0]
    prince.room = landing.room
    prince.charBlockX = landing.x
    prince.charBlockY = landing.y
    prince.charX = CoordinateSpace.x(fromBlockX: landing.x)
    prince.charY = CoordinateSpace.y(fromBlockY: landing.y)
    prince.action = "stand"
    prince.charFrame = 15
    prince.health = 1
    world.actors[0] = prince

    world.shakeLooseBoard(at: ref)
    let interpreter = makeKidInterpreter()
    for _ in 0..<40 {
        var effects: [ActorEffect] = []
        world.update(effects: &effects, interpreter: interpreter)
        if !world.actors[0].isAlive { break }
    }

    #expect(!world.actors[0].isAlive)
    #expect(world.actors[0].health == 0)
}

@Test func guardsAreNotHurtByFallingBoards() throws {
    // `Fighter.checkLooseFloor` is `function (tile) {}` — empty. Only the Kid is checked.
    var world = World(try levelOne())
    let ref = try #require(boardOverFloor(world))

    var landing = ref
    for row in (ref.y + 1)..<Geometry.roomRows {
        if world.level.tile(x: ref.x, y: row, room: ref.room).kind != .space {
            landing = TileRef(room: ref.room, x: ref.x, y: row)
            break
        }
    }

    var foe = world.actors[1]
    foe.room = landing.room
    foe.charBlockX = landing.x
    foe.charBlockY = landing.y
    foe.charX = CoordinateSpace.x(fromBlockX: landing.x)
    foe.charY = CoordinateSpace.y(fromBlockY: landing.y)
    foe.action = "stand"
    foe.charFrame = 16
    let startingHealth = foe.health
    world.actors[1] = foe

    // Move the Prince well clear.
    var prince = world.actors[0]
    prince.room = 99
    world.actors[0] = prince

    world.shakeLooseBoard(at: ref)
    let interpreter = makeKidInterpreter()
    for _ in 0..<40 {
        var effects: [ActorEffect] = []
        world.update(effects: &effects, interpreter: interpreter)
    }
    #expect(world.actors[1].health == startingHealth, "a guard shrugs it off")
}
