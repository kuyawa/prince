import Testing
@testable import PoPCore

// M6b: guards in the level.
//
// Level 1's two guards are both plain `guard` type at skill 0 with colour 2:
//   { room: 21, location: 7,  skill: 0, colors: 2, type: "guard", direction: -1 }
//   { room: 3,  location: 18, skill: 0, colors: 2, type: "guard", direction: -1 }

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

@Test func levelOneSpawnsThePrinceAndBothGuards() throws {
    let world = World(try levelOne())
    #expect(world.actors.count == 3)
    #expect(world.actors[0].charName == "kid", "the Prince is always index 0")
    #expect(world.enemies.count == 2)

    let first = try #require(world.enemies.first)
    #expect(first.room == 21)
    #expect(first.charBlockX == 7)
    #expect(first.charBlockY == 0)
}

@Test func aGuardTakesItsSpriteNameFromItsColour() throws {
    // Enemy: `if (key === "guard") { key = "guard-" + color; }`.
    let world = World(try levelOne())
    #expect(world.enemies.allSatisfy { $0.charName == "guard-2" })
}

@Test func aGuardReadsTheFighterTableWithTheFighterOpcodes() {
    // Enemy passes "fighter" as the animKey for everything except the shadow.
    #expect(ActorKind.animationTable(for: "guard-2") == "fighter")
    #expect(ActorKind.animationTable(for: "fatguard") == "fighter")
    #expect(ActorKind.animationTable(for: "skeleton") == "fighter")
    #expect(ActorKind.animationTable(for: "shadow") == "shadow")
    #expect(ActorKind.animationTable(for: "kid") == "kid")

    // And the opcode set follows: a guard has ACT and DIE but not UP or JARD.
    #expect(ActorKind.actorClass(for: "guard-2") == .fighter)
    #expect(ActorKind.actorClass(for: "kid") == .kid)
    #expect(ActorKind.actorClass(for: "shadow") == .fighter, "the shadow is an Enemy")
}

@Test func guardNamesComeFromTypeAndColour() {
    #expect(ActorKind.enemyCharName(type: .guard, colour: 3) == "guard-3")
    #expect(ActorKind.enemyCharName(type: .guard, colour: 0) == "guard-1", "clamped into 1...7")
    #expect(ActorKind.enemyCharName(type: .guard, colour: 99) == "guard-7")
    #expect(ActorKind.enemyCharName(type: .skeleton, colour: 2) == "skeleton")
    #expect(ActorKind.enemyCharName(type: .fatguard, colour: 1) == "fatguard")
    #expect(ActorKind.enemyCharName(type: .shadow, colour: 1) == "shadow")
}

@Test func guardsGetTheirHealthFromSkillAndLevel() throws {
    let world = World(try levelOne())
    // Skill 0, level 1 -> EXTRA_STRENGTH[0] + STRENGTH[1] = 0 + 3.
    #expect(world.enemies.allSatisfy { $0.health == 3 })
    #expect(world.enemies.allSatisfy { $0.maxHealth == 3 })
}

@Test func aGuardStartsFacingTheWayTheLevelSays() throws {
    let world = World(try levelOne())
    let guardState = try #require(world.enemies.first)
    // direction -1, no reverse, so it faces left — towards the Prince.
    #expect(guardState.charFace == -1)
    // Enemy's constructor nudges him seven x-units along his facing.
    #expect(guardState.charX == CoordinateSpace.x(fromBlockX: 7) - 7)
}

@Test func aGuardHasNotNoticedThePrinceYet() throws {
    let world = World(try levelOne())
    #expect(world.enemies.allSatisfy { !$0.hasStartedFight })
}

@Test func visibilityAndActivityFlagsAreHonoured() {
    // Game.js: `if (data.visible === false) enemy.setInvisible();` and the same for active.
    var spawn = GuardSpawn(
        room: 21, location: 5, skill: 0, colors: 1, type: .guard, direction: -1,
        active: false, visible: false, reverse: nil, bias: nil, sneak: nil
    )
    var actor = ActorState.enemy(from: spawn, levelNumber: 1)
    #expect(!actor.isActive)
    #expect(!actor.isVisible)

    spawn = GuardSpawn(
        room: 21, location: 5, skill: 0, colors: 1, type: .guard, direction: -1,
        active: nil, visible: nil, reverse: nil, bias: nil, sneak: nil
    )
    actor = ActorState.enemy(from: spawn, levelNumber: 1)
    #expect(actor.isActive)
    #expect(actor.isVisible)
}

// MARK: - The simulation

@Test func theSimulationTicksEveryActor() throws {
    let simulation = try Simulation(level: try levelOne())
    #expect(simulation.world.actors.count == 3)
}

@Test func theSimulationIsReproducibleFromItsSeed() throws {
    func run(seed: Int) throws -> [String] {
        var simulation = try Simulation(level: try levelOne(), seed: seed)
        simulation.run(200, intents: .none)
        return simulation.world.actors.map { "\($0.charName) \($0.action) \($0.charX) \($0.charY)" }
    }
    #expect(try run(seed: 5) == run(seed: 5))
}

@Test func thePrinceIsIndexZeroAndOpponentsResolveToGuards() throws {
    var simulation = try Simulation(level: try levelOne())
    // Move the Prince next to the first guard so an opponent is in range.
    simulation.world.actors[0].room = 21
    simulation.world.actors[0].charBlockY = 0

    let opponent = simulation.opponentIndex(for: 0)
    #expect(opponent != nil, "a guard shares his room")

    // And a guard always faces the Prince.
    #expect(simulation.opponentIndex(for: 1) == 0)
}

@Test func aGuardEngagesOnceTheSimulationBringsThemTogether() throws {
    var simulation = try Simulation(level: try levelOne(), seed: 11)
    // Put the Prince in the guard's room, a few tiles away.
    simulation.world.actors[0].room = 21
    simulation.world.actors[0].charBlockY = 0
    simulation.world.actors[0].charBlockX = 3
    simulation.world.actors[0].charX = CoordinateSpace.x(fromBlockX: 3)
    simulation.world.actors[0].charY = CoordinateSpace.y(fromBlockY: 0)

    simulation.run(120, intents: .none)

    let guardState = simulation.world.actors[1]
    #expect(guardState.hasStartedFight, "it noticed him")
}

@Test func guardsTickWithoutThePrinceBeingStepped() throws {
    // Guards update first, matching the reference's creation order.
    var simulation = try Simulation(level: try levelOne(), seed: 2)
    simulation.run(30, intents: .none)
    #expect(simulation.world.actors.count == 3)
}

// MARK: - Rendering

@Test func guardsAppearInTheRenderDescription() throws {
    let world = World(try levelOne())
    // Level 1's first guard is in room 21.
    let description = RoomRenderer.describe(
        world: world, room: 21, actors: world.actors.filter { $0.room == 21 }
    )
    let actorSprites = description.sprites.filter { $0.z == RoomRenderer.actorZ }
    // Only the guard is in room 21 — the Prince spawns in room 1.
    #expect(actorSprites.count == 1)
    #expect(actorSprites.allSatisfy { $0.frameName.hasPrefix("guard-2-") })
}

@Test(arguments: GameData.levelNumbers)
func everyGuardFrameTheRendererAsksForExistsOnceRunning(number: Int) throws {
    // The exhaustive M4 test only walks tiles, and M7a's only adds gate parts. Guards arrive with
    // M6, so this is the first check that their atlases actually hold what we ask for.
    //
    // The ticks matter. `ActorState` starts at `charFrame = 0`, and **`shadow.json` and
    // `vizier.json` have no frame 0 at all** — the shadow's frames start at 1. That placeholder
    // is never displayed in practice, because the first `CMD_FRAME` replaces it before anything
    // is drawn; `LevelScene.makeNode` simply returns nil for a missing texture, which is what
    // Phaser does too.
    var simulation = try Simulation(level: try LevelRuntime(try GameData.level(number)), seed: 1)
    simulation.run(3)
    let world = simulation.world
    guard !world.enemies.isEmpty else { return }

    var available: Set<String> = []
    for name in Set(world.actors.map(\.charName)) {
        available.formUnion(try GameData.atlasFrameNames(named: ActorKind.atlasName(for: name)))
    }

    var missing: Set<String> = []
    for actor in world.actors {
        for sprite in RoomRenderer.describe(actor) where !available.contains(sprite.frameName) {
            missing.insert(sprite.frameName)
        }
    }
    #expect(missing.isEmpty, "level \(number) needs actor frames the atlas lacks: \(missing.sorted())")
}

@Test func theShadowAtlasHasNoFrameZero() throws {
    // Worth pinning: it is the one place where an actor's initial frame is not a real sprite.
    let shadow = try GameData.atlasFrameNames(named: "shadow")
    #expect(!shadow.contains("shadow-0"))
    #expect(shadow.contains("shadow-1"))

    // The others are complete from zero.
    for name in ["kid", "guard-1", "guard-2", "skeleton", "fatguard"] {
        #expect(try GameData.atlasFrameNames(named: name).contains("\(name)-0"))
    }
}
