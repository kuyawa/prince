import Testing
@testable import PoPCore

// M6c: finishing a level.
//
// The level change itself lives in `PoPHost.GameCoordinator`, which is SpriteKit plumbing. What
// is testable here is the mechanism that triggers it: the exit's `NEXTLEVEL` opcode reaching the
// simulation's effect list.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

/// Opens room 9's exit door and puts the Prince on it.
private func simulationAtTheOpenExit() throws -> Simulation {
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    simulation.world.pressButton(at: TileRef(room: 9, x: 0, y: 0))
    for _ in 0..<44 { simulation.world.update() }
    #expect(simulation.world.state.trob(at: TileRef(room: 9, x: 4, y: 1))?.exitDoor?.isOpen == true)

    simulation.world.actors[0].room = 9
    simulation.world.actors[0].charBlockX = 4
    simulation.world.actors[0].charBlockY = 1
    simulation.world.actors[0].charX = CoordinateSpace.x(fromBlockX: 4)
    simulation.world.actors[0].charY = CoordinateSpace.y(fromBlockY: 1)
    simulation.world.actors[0].charFdx = 0
    simulation.world.actors[0].charFfoot = 0
    simulation.world.actors[0].action = "stand"
    simulation.world.actors[0].hasSword = true
    return simulation
}

@Test func climbingTheExitRunsTheStairsSequence() throws {
    var simulation = try simulationAtTheOpenExit()
    // The up key on an open exit is `climbstairs`.
    simulation.tick(intents: [.up])

    #expect(simulation.world.prince.action == "climbstairs")
    #expect(simulation.world.prince.charBlockX == 3, "he steps onto the left half")
}

@Test func theStairsSequenceEndsInNextLevel() throws {
    // `climbstairs`'s sequence carries the NEXTLEVEL opcode, which is what ends a level.
    let kid = try GameData.animationTable(named: "kid")
    let stairs = try #require(kid.sequence("climbstairs"))
    #expect(stairs.contains { $0.command == Opcode.nextLevel.rawValue })
}

@Test func nextLevelSurfacesAsAnEffectTheHostCanActOn() throws {
    var simulation = try simulationAtTheOpenExit()

    // Effects are drained every tick, so both are tracked across the run: `leavingLevel` is
    // emitted when he starts climbing, `advanceToNextLevel` when the sequence reaches its opcode.
    var sawNextLevel = false
    var sawLeaving = false
    for _ in 0..<400 {
        simulation.tick(intents: [.up])
        if simulation.effects.contains(.leavingLevel) { sawLeaving = true }
        if simulation.effects.contains(.advanceToNextLevel) {
            sawNextLevel = true
            break
        }
    }
    #expect(sawNextLevel, "the Prince climbed out")
    #expect(sawLeaving)
}

@Test func healthCarriesAcrossALevelChange() throws {
    // `CMD_NEXTLEVEL` does `PrinceJS.maxHealth = this.maxHealth` and passes the health onward.
    let wounded = try Simulation(level: try levelOne(), seed: 1, princeHealth: 1, princeMaxHealth: 5)
    #expect(wounded.world.prince.health == 1)
    #expect(wounded.world.prince.maxHealth == 5)

    // Health is clamped to the maximum rather than trusted.
    let overfull = try Simulation(level: try levelOne(), seed: 1, princeHealth: 9, princeMaxHealth: 3)
    #expect(overfull.world.prince.health == 3)
}

@Test func aFreshLevelStartsWithAnUnharmedPrince() throws {
    let fresh = try Simulation(level: try levelOne())
    #expect(fresh.world.prince.health == 3)
    #expect(fresh.world.prince.maxHealth == 3)
}

// MARK: - The sword overlay

@Test func swordFramesResolveThroughTheOffsetTable() throws {
    // `Fighter.updateSwordFrame`: `swordtab[framedef.fsword - 1]`, and the entry's `id` names the
    // sprite. It is the reference's clearest 1-based positional index — open question 9.
    let table = try GameData.swordOffsetTable()
    let first = try #require(table.offset(at: 0))
    #expect(first.id == 1)
    #expect(first.dx == 0)
    #expect(first.dy == -9)

    // Frame 150's definition carries fsword 16, so it resolves to swordtab[15].
    let sixteen = try #require(table.offset(at: 15))
    #expect(try GameData.atlasFrameNames(named: "sword").contains("sword\(sixteen.id)"))
}

@Test func everySwordFrameTheRendererAsksForExists() throws {
    let world = World(try levelOne())
    let available = try GameData.atlasFrameNames(named: "sword")
    let offsets = try GameData.swordOffsetTable()

    var missing: Set<String> = []
    for actor in world.actors {
        var probe = actor
        // Walk the whole frame table so every fsword in the data is exercised.
        let table = try GameData.animationTable(named: ActorKind.animationTable(for: actor.charName))
        for index in table.frameDefs.indices {
            probe.applyFrameDefinition(table.frameDefs[index], swordOffsets: offsets)
            guard probe.hasSwordFrame else { continue }
            for sprite in RoomRenderer.describe(probe)
            where sprite.z == RoomRenderer.swordZ && !available.contains(sprite.frameName) {
                missing.insert(sprite.frameName)
            }
        }
    }
    #expect(missing.isEmpty, "sword frames the atlas lacks: \(missing.sorted())")
}

@Test func aFrameWithoutASwordDrawsNoBlade() throws {
    // There is no `swordDrawn` test in the renderer: whether the frame carries an `fsword` *is*
    // the sword-drawn state.
    var actor = ActorState(location: 11, room: 1, face: 1, charName: "kid")
    actor.charFrame = 15
    actor.swordDrawn = true          // drawn, but frame 15 has no fsword
    actor.applyFrameDefinition(
        FrameDef(dx: 0, dy: 0, check: FrameCheck(rawValue: 0), swordFrame: nil, comment: nil),
        swordOffsets: try GameData.swordOffsetTable()
    )
    #expect(!actor.hasSwordFrame)
    #expect(!RoomRenderer.describe(actor).contains { $0.z == RoomRenderer.swordZ })
}

@Test func theSwordDrawsAboveTheActorAndMirrorsWithFacing() throws {
    // Find a frame the fighter table actually gives a sword to, rather than assuming an index.
    let table = try GameData.animationTable(named: "fighter")
    let entry = try #require(
        table.frameDefs.enumerated().first { $0.element.swordFrame != nil }
    )

    var actor = ActorState(location: 11, room: 1, face: 1, charName: "guard-2")
    actor.baseCharName = "guard"
    actor.charFrame = entry.offset
    actor.applyFrameDefinition(entry.element, swordOffsets: try GameData.swordOffsetTable())
    #expect(actor.hasSwordFrame)

    let sprites = RoomRenderer.describe(actor)
    let blade = try #require(sprites.first { $0.z == RoomRenderer.swordZ })
    let body = try #require(sprites.first { $0.z == RoomRenderer.actorZ })
    #expect(blade.frameName == "sword\(actor.swordFrame)")
    #expect(blade.x == body.x + actor.swordDx * actor.charFace)
    #expect(blade.y == body.y + actor.swordDy)
    #expect(blade.anchor == .bottomLeft)

    // Facing left mirrors it — and the body moves too, because the half-pixel parity correction
    // depends on facing. Re-read both rather than reusing the right-facing positions.
    actor.charFace = -1
    let mirroredSprites = RoomRenderer.describe(actor)
    let mirrored = try #require(mirroredSprites.first { $0.z == RoomRenderer.swordZ })
    let mirroredBody = try #require(mirroredSprites.first { $0.z == RoomRenderer.actorZ })
    #expect(mirrored.flippedHorizontally)
    #expect(mirroredBody.flippedHorizontally)
    #expect(mirrored.x == mirroredBody.x + actor.swordDx * -1)
}
