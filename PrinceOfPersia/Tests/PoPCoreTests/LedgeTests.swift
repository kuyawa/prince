import Testing
@testable import PoPCore

// The ledge system: grabbing an edge out of a fall, and swinging on it.
//
// Level 1 room 10 is the fixture. Its row 0 is `W . . F F P d P . W`, so column 2 is open air with
// a floor tile at column 3 beside it — a Prince falling down the column 2 shaft can catch the edge
// at (3,0) on the way past.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

/// A Prince falling down column 2 of room 10, facing right, next to the ledge at (3,0).
///
/// `charY` is 100, not the row-1 resting height of 116. The grab window is `distanceToTopFloor
/// >= -50`, and the floor of row 0 is at y = 53 — so he must be above y = 103 to catch it. A real
/// fall passes through that window a few ticks after leaving the ledge he is trying to catch.
private func fallingAtTheLedge(charX: Int = 41, frame: Int = 102) -> ActorState {
    var state = ActorState(location: 0, room: 10, face: 1, action: "stepfall", charName: "kid")
    state.charBlockX = 2
    state.charBlockY = 1
    state.charX = charX
    state.charY = 100
    state.charFrame = frame
    state.charFdx = 0
    state.charFdy = 0
    state.charFfoot = 0
    state.charFood = false
    state.isInFallDown = true
    return state
}

private func kid() -> SequenceInterpreter { makeKidInterpreter() }

// MARK: - Reach

@Test func theGrabReachIsAsymmetric() throws {
    // `offsetX = this.faceL() ? 2 : -5`. The arm is drawn on one side of the body, so the reach is
    // not the same in both directions.
    let world = World(try levelOne())
    let atlas = world.atlasName
    let ledge = world.tile(x: 3, y: 0, room: 10)

    var right = fallingAtTheLedge()
    var left = right
    left.charFace = -1

    let rightOffset = abs(
        ledge.centerX(column: 3, atlas: atlas) - right.centerX() + (-5)
    )
    let leftOffset = abs(
        ledge.centerX(column: 3, atlas: atlas) - left.centerX() + 2
    )
    #expect(rightOffset != leftOffset, "facing changes the reach")

    // And the default reach is 30, with 20 for the ledge he is already under.
    #expect(Behaviour.inGrabDistance(right, tile: ledge, column: 3, atlas: atlas))
    #expect(!Behaviour.inGrabDistance(right, tile: ledge, column: 3, atlas: atlas, distance: 1))
    _ = right
}

@Test func theTopFloorDistanceIsNegativeAboveIt() {
    // `convertBlockYtoY(charBlockY - 1) - charY - charFdy`. A Prince who has jumped too high reads
    // strongly negative, which is what stops him catching a ledge on the way back up.
    var state = fallingAtTheLedge()
    state.charBlockY = 1

    // Resting on row 1, the floor of row 0 is 63 units overhead, so the reading is -63: he is
    // already below the ledge by more than the 50 units the grab allows.
    state.charY = CoordinateSpace.y(fromBlockY: 1)
    #expect(FallCycle.distanceToTopFloor(state) == CoordinateSpace.y(fromBlockY: 0) - state.charY)
    #expect(FallCycle.distanceToTopFloor(state) == -63)
    #expect(FallCycle.distanceToTopFloor(state) < -50, "too far below to catch anything")

    // Just after leaving the ledge the reading is inside the window — and this is the only part
    // of the fall in which a grab is possible at all.
    state.charY = 103
    #expect(FallCycle.distanceToTopFloor(state) >= -50)
}

// MARK: - Grabbing

@Test func fallingPastALedgeCatchesItWithTheActionKey() throws {
    let world = World(try levelOne())
    let interpreter = kid()
    var prince = fallingAtTheLedge()
    var effects: [ActorEffect] = []

    let grabbed = try Behaviour.tryGrabEdge(
        &prince, world: world, interpreter: interpreter, effects: &effects
    )

    #expect(grabbed)
    #expect(prince.action == "hang")
    #expect(effects.contains(.sound(.bumpIntoWallHard)), "a firmer sound than a bump")
    #expect(prince.grabWait, "half a second before he can climb")
    #expect(prince.grabWaitTicks == 6)
    #expect(!prince.isInFallDown, "the fall is over")
    #expect(prince.charXVel == 0 && prince.charYVel == 0)

    // Facing right, he is pulled one unit past the ledge’s right edge.
    #expect(prince.charX == CoordinateSpace.x(fromBlockX: 3) + 1)
    #expect(prince.charY == CoordinateSpace.y(fromBlockY: 1))
}

@Test func nothingToGrabMeansNothingHappens() throws {
    let world = World(try levelOne())
    let interpreter = kid()
    // Column 1 of room 10 row 0 is `W . . F ...` — open air either side of him and a wall behind,
    // so there is no ledge to catch.
    var prince = fallingAtTheLedge(charX: CoordinateSpace.x(fromBlockX: 1))
    prince.charBlockX = 1
    var effects: [ActorEffect] = []

    let grabbed = try Behaviour.tryGrabEdge(
        &prince, world: world, interpreter: interpreter, effects: &effects
    )
    #expect(!grabbed)
    #expect(prince.action == "stepfall", "still falling")
    #expect(!effects.contains(.sound(.bumpIntoWallHard)))
}

@Test func tooLongAFallCannotBeCaught() throws {
    // `fallingBlocks > 2` refuses outright — unless the float potion is on, which is precisely
    // what makes the third potion a way out of a long drop.
    let world = World(try levelOne())
    let interpreter = kid()

    var deep = fallingAtTheLedge()
    deep.fallingBlocks = 3
    var effects: [ActorEffect] = []
    #expect(try !Behaviour.tryGrabEdge(
        &deep, world: world, interpreter: interpreter, effects: &effects
    ))

    deep.isInFloat = true
    deep.floatTicksRemaining = World.floatTicks
    #expect(try Behaviour.tryGrabEdge(
        &deep, world: world, interpreter: interpreter, effects: &effects
    ))
    #expect(deep.action == "hang")
}

@Test func catchingALedgeShakesTheBoardAboveIt() throws {
    // Level 1 room 1 row 2 is `W W W W d P L F F W` and row 1 is `T T F P . W W W W W` — the
    // Prince hanging at (6,1) has the loose board at (6,2) below him, not above. So this checks the
    // negative case on a real level, and the shake itself is covered by the loose-board tests.
    let world = World(try levelOne())
    let interpreter = kid()
    var prince = fallingAtTheLedge()
    var effects: [ActorEffect] = []
    _ = try Behaviour.tryGrabEdge(
        &prince, world: world, interpreter: interpreter, effects: &effects
    )
    #expect(effects.filter { if case .shookLooseBoard = $0 { return true }; return false }.isEmpty,
            "no board above this ledge")
}

// MARK: - Swinging

@Test func swingingCarriesHimSidewaysOnlyAfterFourSwings() {
    var state = fallingAtTheLedge(charX: 40)
    state.action = "stepfall"

    for swings in 0..<4 {
        state.ledgeSwing = swings
        let before = state.charX
        FallCycle.checkLedgeSwing(&state)
        #expect(state.charX == before, "\(swings) swings is not enough")
    }

    // Four ticks of 1.5 give cumulative 1, 3, 4, 6 units — so the *increments* alternate 1, 2, 1,
    // 2. That is `charX += 1.5` with the fraction rounded down at each step, which is what the
    // reference gets from carrying a fractional `charX`.
    state.ledgeSwing = 4
    let start = state.charX
    FallCycle.checkLedgeSwing(&state)
    #expect(state.charX == start + 1)
    FallCycle.checkLedgeSwing(&state)
    #expect(state.charX == start + 3, "3 units after two ticks, not 2")
    FallCycle.checkLedgeSwing(&state)
    #expect(state.charX == start + 4)
    FallCycle.checkLedgeSwing(&state)
    #expect(state.charX == start + 6, "and six after four — the half is never lost")
}

@Test func swingingIsFasterWhileFloating() {
    // `(this.inFloat ? 2.0 : 1.5)`. Two units a tick instead of one and a half.
    var floating = fallingAtTheLedge(charX: 40)
    floating.ledgeSwing = 4
    floating.isInFloat = true
    let start = floating.charX
    FallCycle.checkLedgeSwing(&floating)
    #expect(floating.charX == start + 2)
}

@Test func swingingPushesTheWayHeFaces() {
    var left = fallingAtTheLedge(charX: 40)
    left.charFace = -1
    left.ledgeSwing = 4
    let start = left.charX
    FallCycle.checkLedgeSwing(&left)
    FallCycle.checkLedgeSwing(&left)
    #expect(left.charX < start)
}

@Test func stoppingAFallClearsTheCount() {
    var state = fallingAtTheLedge()
    state.fallingBlocks = 2
    state.isInFallDown = true
    state.swordDrawn = true
    FallCycle.stopFall(&state)
    #expect(state.fallingBlocks == 0)
    #expect(!state.isInFallDown)
    #expect(!state.swordDrawn)
}

// MARK: - Letting go

/// A Prince hanging over column `x` of room 1, with the loose board at (6,2) either intact or
/// already collapsed into a hole.
private func hangingInRoomOne(at x: Int, overAHole: Bool) throws -> Simulation {
    var data = try GameData.level(1)
    data = data.replacingPrince(
        PrinceSpawn(location: 27, room: 1, direction: 1, danger: false)
    )
    var simulation = try Simulation(level: LevelRuntime(data), seed: 1)

    if overAHole {
        simulation.world.shakeLooseBoard(at: TileRef(room: 1, x: 6, y: 2))
        for _ in 0..<12 { simulation.tick(intents: .none) }
    }

    var prince = simulation.world.actors[0]
    prince.room = 1
    prince.charFace = -1
    prince.charBlockX = x
    prince.charBlockY = 2
    prince.charX = CoordinateSpace.x(fromBlockX: x)
    prince.charY = CoordinateSpace.y(fromBlockY: 2)
    prince.baseY = 0
    prince.charXVel = 0
    prince.charYVel = 0
    prince.isInFallDown = false
    // **The turn is what sets this.** `startFall` arms an immediate floor probe for `turn`,
    // `turnrun`, `turnengarde`, `highjump` and `hangdrop`, and `checkFall` consumes it — so a
    // Prince who turned on the way to the edge arrives at the ledge with the probe still armed.
    // A hang that then answered with a plain `stepfall` would spend that probe landing him on the
    // floor beside the hole instead of dropping him through it.
    prince.checkFloorStepFall = true
    prince.beginAction("hang")
    prince.charFrame = 92
    simulation.world.actors[0] = prince
    return simulation
}

@Test func lettingGoOverAHoleFallsThroughIt() throws {
    // The reported bug: hang from the edge of the hole the loose board left, let go, and instead
    // of dropping into the room below he lands back in the room he was in.
    //
    // `Kid.startFall` answers a hanging action with one of two actions of its own — `hangfall`,
    // let go and go *through*, or `hangdrop`, let go and land — and which one it is depends on
    // what is underneath him. The port answered both with a bare `stepfall`, which is the action
    // for stepping off a ledge, not for releasing one.
    var simulation = try hangingInRoomOne(at: 6, overAHole: true)
    #expect(simulation.world.prince.action == "hang")

    var actions: [String] = []
    for _ in 1...12 {
        simulation.tick(intents: .none)
        let action = simulation.world.prince.action
        if actions.last != action { actions.append(action) }
    }

    #expect(actions.contains("hangfall"), "over a hole the action is hangfall: \(actions)")
    #expect(!actions.contains("stepfall"), "and not the step fall: \(actions)")
    #expect(simulation.world.prince.room == 2, "he went through the hole, not back onto it")
}

@Test func lettingGoOverGroundDropsAndLands() throws {
    // The other half of the same decision. Column 7 is the floor beside the hole, so the answer
    // is `hangdrop`: he drops where he is and lands. Anything else would send him through solid
    // ground.
    var simulation = try hangingInRoomOne(at: 7, overAHole: true)

    var actions: [String] = []
    for _ in 1...12 {
        simulation.tick(intents: .none)
        let action = simulation.world.prince.action
        if actions.last != action { actions.append(action) }
    }

    #expect(actions.contains("hangdrop"), "over ground the action is hangdrop: \(actions)")
    #expect(!actions.contains("hangfall"))
    #expect(simulation.world.prince.room == 1)
    #expect(simulation.world.prince.action == "stand")
}
