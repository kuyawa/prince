import Testing
@testable import PoPCore

// The vertical room change: dropping out of the bottom of a room.
//
// `Kid.checkRoomChange` is the whole of it, and it is three lines plus a list of frames that
// skip those three lines. Both halves are load-bearing, and the list was left out for a while on
// the stated grounds that it could not affect the `charY` test — it is the first statement in the
// function, so it could not do anything *but* affect it.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

@Test func theFramesThatFlipTheSpriteDoNotCrossARoom() throws {
    let level = try levelOne()

    for frame in FallCycle.frozenFrames {
        var state = ActorState(location: 0, room: 1, face: 1)
        state.charFrame = frame
        state.charY = Geometry.roomHeight + 5
        state.baseY = 0

        FallCycle.checkRoomChange(&state, world: level)

        #expect(state.room == 1, "frame \(frame) must not cross")
        #expect(state.charY == Geometry.roomHeight + 5)
    }
}

@Test func anyOtherFrameCrosses() throws {
    let level = try levelOne()
    let crossing = (0...200).filter { !FallCycle.frozenFrames.contains($0) }
    #expect(crossing.count == 181, "twenty frames are frozen out of two hundred and one")

    var state = ActorState(location: 0, room: 1, face: 1)
    state.charFrame = 15
    state.charY = Geometry.roomHeight + 5
    state.baseY = 0

    FallCycle.checkRoomChange(&state, world: level)

    // Room 1 sits above room 2, and the room-relative y is carried down.
    #expect(state.room == 2)
    #expect(state.charY == 5)
    #expect(state.baseY == Geometry.roomHeight)
}

@Test func theGuardsHaveNoSuchGuard() throws {
    // `Fighter.checkRoomChange` is the same test with 192 for 189 and no frame list at all.
    let level = try levelOne()
    var state = ActorState(location: 0, room: 1, face: 1)
    state.charFrame = 157
    state.charY = 193

    FallCycle.fighterCheckRoomChange(&state, world: level)
    #expect(state.room == 2, "a guard crosses on a frame the Prince will not")
}

@Test func fallingThroughAFloorHoleLandsInTheRoomBelow() throws {
    // Level 1's room 8 has a hole through the floor at (4,2) and room 11 beneath it. Walking
    // off the ledge at (3,1) drops him through both, and he is in room 11 before he lands.
    var data = try GameData.level(1)
    data = data.replacingPrince(PrinceSpawn(location: 13, room: 8, direction: 1, danger: false))
    var simulation = try Simulation(level: LevelRuntime(data), seed: 1)

    var rooms: [Int] = []
    for _ in 1...20 {
        simulation.tick(intents: [.right])
        let room = simulation.world.prince.room
        if rooms.last != room { rooms.append(room) }
    }

    #expect(rooms.contains(11), "he left room 8 downwards, not sideways: \(rooms)")
    #expect(rooms.first == 8)
}

@Test func climbingDownThroughAHoleEndsInTheRoomBelow() throws {
    // The reported bug, tick for tick. In level 1's first room the loose board at (6,2) leaves a
    // hole; stand on the floor beside it at (7,2) facing it and climb down, and the Prince arrives
    // at row 0 of the room he was already in — `by` 2 to 0 and `charY` 179 to 53, with `room`
    // unchanged. The screen never changes, so letting go of the ledge he catches there drops him
    // back onto the floor he started from.
    //
    // `charY` 179 to 53 is the tell: 179 + 63 is 242, and 242 - 189 is 53. The room height came
    // off, so *something* ran — `Kid.CMD_DOWN`, which the port had been finishing without
    // calling `changeRoomDown`.
    var data = try GameData.level(1)
    let original = data.prince
    data = data.replacingPrince(PrinceSpawn(
        location: 27, room: 1, direction: 1,
        offset: original.offset, turn: original.turn,
        cameraRoom: original.cameraRoom, bias: original.bias,
        reverse: original.reverse, sword: original.sword,
        danger: false, specialEvents: original.specialEvents
    ))
    var simulation = try Simulation(level: LevelRuntime(data), seed: 1)

    // Knock the board out, and put him on the floor beside the hole facing it.
    simulation.world.shakeLooseBoard(at: TileRef(room: 1, x: 6, y: 2))
    for _ in 0..<12 { simulation.tick(intents: .none) }
    #expect(simulation.world.tile(x: 6, y: 2, room: 1).kind == .space, "the hole is there")

    var prince = simulation.world.actors[0]
    prince.room = 1
    prince.charFace = 1
    prince.charBlockX = 7
    prince.charBlockY = 2
    prince.charX = 112
    prince.charY = CoordinateSpace.y(fromBlockY: 2)
    prince.baseY = 0
    prince.charXVel = 0
    prince.charYVel = 0
    prince.isInFallDown = false
    prince.beginAction("climbdown")
    simulation.world.actors[0] = prince

    var reachedRoomTwo: Int? = nil
    for tick in 1...12 {
        simulation.tick(intents: .none)
        let him = simulation.world.prince
        // The reference's positions for this manoeuvre: x 107, row 0, charY 53.
        if him.charBlockY == 0, him.charY == 53 { reachedRoomTwo = him.room }
        if tick == 12 { reachedRoomTwo = him.room }
    }

    #expect(reachedRoomTwo == 2, "the climb went through the hole into room 2, not round it")
    #expect(simulation.world.prince.room == 2)
}
