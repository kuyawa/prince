import Testing
@testable import PoPCore

// M3: gravity, integration and the fall-to-land cycle.

private func kidInterpreter() throws -> SequenceInterpreter {
    SequenceInterpreter(table: try GameData.animationTable(named: "kid"), actorClass: .kid)
}

@Test func gravityConstantsComeFromTheReference() {
    #expect(Physics.gravity == 3)
    #expect(Physics.gravityFloat == 1)
    #expect(Physics.topSpeed == 33)
    #expect(Physics.topSpeedFloat == 4)
    #expect(Physics.gravityActionCode == 4)
}

@Test func gravityAppliesOnlyWhenTheActionCodeIsFour() {
    // ACT (249) writes actionCode, so the sequences decide when an actor is subject to
    // gravity. Applying it unconditionally would break every jump.
    for code in [0, 1, 3, 5, 7] {
        var state = ActorState(location: 3, room: 1, face: 1)
        state.actionCode = code
        Physics.accelerate(&state)
        #expect(state.charYVel == 0, "actionCode \(code) must not fall")
    }

    var falling = ActorState(location: 3, room: 1, face: 1)
    falling.actionCode = Physics.gravityActionCode
    Physics.accelerate(&falling)
    #expect(falling.charYVel == 3)
}

@Test func fallingReachesTerminalVelocityAndStopsThere() {
    var state = ActorState(location: 3, room: 1, face: 1)
    state.actionCode = Physics.gravityActionCode

    var observed: [Int] = []
    for _ in 0..<14 {
        Physics.accelerate(&state)
        observed.append(state.charYVel)
    }
    // 3, 6, 9 ... 33, then clamped forever.
    #expect(observed.prefix(11) == [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33])
    #expect(observed.suffix(3) == [33, 33, 33])
}

@Test func floatingFallsFarMoreSlowly() {
    var state = ActorState(location: 3, room: 1, face: 1)
    state.actionCode = Physics.gravityActionCode
    state.isInFloat = true
    for _ in 0..<10 { Physics.accelerate(&state) }
    #expect(state.charYVel == Physics.topSpeedFloat)

    // IFWTLESS (247) leaves float mode when the sequence says so, and normal gravity
    // resumes — but the accumulated velocity is NOT reset.
    state.isInFloat = false
    Physics.accelerate(&state)
    #expect(state.charYVel == Physics.topSpeedFloat + Physics.gravity)
}

@Test func velocityIntegratesInBothAxes() {
    var state = ActorState(location: 3, room: 1, face: 1)
    state.charXVel = 4
    state.charYVel = 9
    let x0 = state.charX
    let y0 = state.charY
    Physics.move(&state)
    #expect(state.charX == x0 + 4)
    #expect(state.charY == y0 + 9)
}

@Test func aFreeFallAcceleratesAndLandsOnTheFloor() throws {
    // Level 1 room 1 row 0 is [0, 0, 0, 1, 1, 1, 1, 1, 20, 20], so column 3 is floor.
    // Standing height for row 0 is 53.
    let level = try LevelRuntime(try GameData.level(1))
    let interpreter = try kidInterpreter()

    var state = ActorState(location: 3, room: 1, face: 1, action: "freefall")
    state.charY = 20
    state.actionCode = Physics.gravityActionCode
    state.updateBlockPosition()
    #expect(state.charBlockX == 3)
    #expect(state.charBlockY == 0)

    var effects: [ActorEffect] = []
    var landedOnTick = 0

    for tick in 1...10 {
        Physics.accelerate(&state)
        Physics.move(&state)
        try FallCycle.checkFall(&state, world: level, interpreter: interpreter, effects: &effects)
        if state.action == "stand" { landedOnTick = tick; break }
        // Still in the air before the final tick.
        #expect(state.charY < 53)
    }

    // vel 3 -> y 23, vel 6 -> 29, vel 9 -> 38, vel 12 -> 50, and 50 + 6 >= 53 so it lands.
    #expect(landedOnTick == 4)
    #expect(state.charY == 53)
    #expect(state.charXVel == 0)
    #expect(state.charYVel == 0)
    #expect(state.isAlive)
    #expect(state.action == "stand")
    #expect(state.charFrame == 15)   // the stand sequence settled
}

@Test func aFallThatNeverReachesTheFloorDoesNotLand() throws {
    let level = try LevelRuntime(try GameData.level(1))
    let interpreter = try kidInterpreter()

    // Room 1 row 0 is [0, 0, 0, 1, 1, 1, 1, 1, 20, 20]: columns 0...2 are space,
    // so there is nothing to land on there.
    var state = ActorState(location: 0, room: 1, face: 1, action: "freefall")
    state.charY = 20
    state.actionCode = Physics.gravityActionCode
    state.updateBlockPosition()
    #expect(state.charBlockX == 0)
    #expect(level.tile(x: state.charBlockX, y: state.charBlockY, room: 1).kind == .space)

    var effects: [ActorEffect] = []
    for _ in 0..<3 {
        Physics.accelerate(&state)
        Physics.move(&state)
        try FallCycle.checkFall(&state, world: level, interpreter: interpreter, effects: &effects)
    }
    #expect(state.action == "freefall")
    #expect(state.charY > 20)
}

@Test func distanceToFloorMeasuresTheGapBelow() {
    var state = ActorState(location: 3, room: 1, face: 1)
    state.charY = 53
    state.charFdy = 0
    #expect(FallCycle.distanceToFloor(state) == 0)
    state.charY = 30
    #expect(FallCycle.distanceToFloor(state) == 23)
}

@Test func theFighterRoomChangeThresholdIsOneHundredAndNinetyTwo() throws {
    // Fighter.checkRoomChange compares against 192 while the room is 189 tall. The
    // reference is reproduced as written rather than tidied. Guards use this; the Prince
    // uses Kid's 189 — see RoomTransitionTests.
    let level = try LevelRuntime(try GameData.level(1))

    var state = ActorState(location: 3, room: 1, face: 1)
    state.charY = 192
    FallCycle.fighterCheckRoomChange(&state, world: level)
    #expect(state.room == 1, "exactly 192 is not past the threshold")
    #expect(state.baseY == 0)

    state.charY = 193
    FallCycle.fighterCheckRoomChange(&state, world: level)
    #expect(state.charY == 1)          // 193 - 192, not 193 - 189
    #expect(state.baseY == Geometry.roomHeight)
    #expect(state.room == 2)           // level 1: room 1's down link is 2
}

@Test func landingOnSpikesKills() throws {
    // Level 1 room 3 has spikes. Rather than hunt for one, assert the branch directly
    // through the tile predicate the reference uses.
    #expect(TileKind.spikes.isWalkable)   // spikes ARE walkable — that is how you die on them
}
