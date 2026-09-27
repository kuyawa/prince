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
