import Testing
@testable import PoPCore

// M5: the level graph and room traversal.
//
// Expected values come from a faithful Node re-implementation carrying the full level graph —
// getRoomX/getRoomY, updateBlockXY's room wrapping, and the real kid.json and level1.json.
//
// Level 1's room 21 sits at grid (4,0) with room 5 immediately to its right at (5,0).
// Room 21 row 0 is [PILLAR, FLOOR, FLOOR, TORCH, FLOOR, TORCH, FLOOR, FLOOR, FLOOR, PILLAR],
// so its right-hand column is walkable and the Prince can cross.
//
// (Room 5 also has a neighbour to its right, but its row 0 contains gates at columns 5 and 9,
// and gates begin closed — a worse trace subject.)

private struct RoomTick: Equatable, CustomStringConvertible {
    var action: String
    var pointer: Int
    var frame: Int
    var x: Int
    var room: Int
    var blockX: Int
    var baseX: Int

    init(_ state: ActorState) {
        action = state.action
        pointer = state.sequencePointer
        frame = state.charFrame
        x = state.charX
        room = state.room
        blockX = state.charBlockX
        baseX = state.baseX
    }

    init(_ action: String, _ pointer: Int, _ frame: Int, _ x: Int,
         _ room: Int, _ blockX: Int, _ baseX: Int) {
        self.action = action; self.pointer = pointer; self.frame = frame
        self.x = x; self.room = room; self.blockX = blockX; self.baseX = baseX
    }

    var description: String {
        "(\(action) ptr=\(pointer) frame=\(frame) x=\(x) room=\(room) bx=\(blockX) baseX=\(baseX))"
    }
}

private func t(_ a: String, _ p: Int, _ f: Int, _ x: Int,
               _ room: Int, _ bx: Int, _ baseX: Int) -> RoomTick {
    RoomTick(a, p, f, x, room, bx, baseX)
}

/// `ActorState(location:)` splits `location` as `% 10` / `/ 10`, so a block round-trips.
private func actor(room: Int, blockX: Int, blockY: Int) -> ActorState {
    ActorState(location: blockY * Geometry.roomColumns + blockX, room: room, face: 1)
}

private func run(_ state: ActorState, script: [Intents]) throws -> [RoomTick] {
    let level = try LevelRuntime(try GameData.level(1))
    let interpreter = SequenceInterpreter(
        table: try GameData.animationTable(named: "kid"), actorClass: .kid
    )
    var state = state
    var effects: [ActorEffect] = []
    var result: [RoomTick] = []
    for intents in script {
        driveBehaviour(&state, intents: intents, world: level)
        try interpreter.step(&state, world: level, effects: &effects)
        result.append(RoomTick(state))
    }
    return result
}

private let right: Intents = [.right]
private let none = Intents.none

// MARK: - Cross-room tile lookup (open question 10, now resolved)

@Test func tilesResolveAcrossTheRightEdge() throws {
    let level = try LevelRuntime(try GameData.level(1))

    // A chain eastward through level 1's top row: room 21 -> 5 -> 1, then it stops.
    // Level 1's grid row 0 is [22, 16, 23, 17, 21, 5, 1, -1, -1].
    #expect(level.roomLinks(21)?.right == 5)
    #expect(level.roomLinks(5)?.right == 1)
    #expect(level.roomLinks(1)?.right == -1, "a gap in the layout")

    // Column 10 of room 21 is column 0 of room 5, a PILLAR.
    #expect(level.tile(x: 10, y: 0, room: 21).kind == .pillar)
    // Column 10 of room 5 is column 0 of room 1, which is SPACE.
    #expect(level.tile(x: 10, y: 0, room: 5).kind == .space)
    // And room 1 has nowhere further to go.
    #expect(level.tile(x: 10, y: 0, room: 1).kind == .wall)
    // Two columns out from room 21 stops at room 5's own edge resolution — only one room
    // is crossed per lookup.
    #expect(level.tile(x: 20, y: 0, room: 21).kind == .wall)
}

@Test func tilesResolveAcrossTheLeftEdge() throws {
    let level = try LevelRuntime(try GameData.level(1))
    #expect(level.roomLinks(5)?.left == 21)
    // Column -1 of room 5 is column 9 of room 21, a PILLAR.
    #expect(level.tile(x: -1, y: 0, room: 5).kind == .pillar)
    // Only ONE room is crossed; two columns out is off the map again.
    #expect(level.tile(x: -21, y: 0, room: 5).kind == .wall)
}

@Test func tilesResolveVertically() throws {
    let level = try LevelRuntime(try GameData.level(1))
    #expect(level.roomLinks(1)?.down == 2)
    // Row 3 of room 1 is row 0 of room 2.
    #expect(level.tile(x: 0, y: 3, room: 1).kind == level.tile(x: 0, y: 0, room: 2).kind)
    #expect(level.tile(x: 0, y: 3, room: 1).kind == .space)
}

@Test func gapsInTheGridStillReadAsWall() throws {
    let level = try LevelRuntime(try GameData.level(1))
    #expect(level.roomLinks(1)?.right == -1, "a gap in the layout")
    #expect(level.tile(x: 10, y: 0, room: 1).kind == .wall)
    #expect(level.tile(x: 0, y: 0, room: 999).kind == .wall)
}

// MARK: - The transition itself

@Test func theTransitionConstantsAreTheEngineOnes() {
    // updateBlockXY shifts charX by a whole room in x-units and baseX by a whole room in
    // screen pixels. Different numbers, because the axes use different units.
    #expect(CoordinateSpace.xUnitsPerRoom == 140)
    #expect(Geometry.screenWidth == 320)
}

@Test func walkingOffTheRightEdgeEntersTheNeighbouringRoom() throws {
    let ticks = try run(actor(room: 21, blockX: 8, blockY: 0),
                        script: [none, none] + Array(repeating: right, count: 22))
    #expect(ticks == [
        t("stand", 2, 15, 119, 21, 7, 0),
        t("stand", 2, 15, 119, 21, 7, 0),
        t("startrun", 2, 1, 119, 21, 7, 0),
        t("startrun", 3, 2, 119, 21, 7, 0),
        t("startrun", 4, 3, 119, 21, 7, 0),
        t("startrun", 5, 4, 119, 21, 7, 0),
        t("startrun", 7, 5, 127, 21, 8, 0),
        t("startrun", 9, 6, 130, 21, 8, 0),
        t("running", 2, 7, 133, 21, 8, 0),
        t("running", 4, 8, 138, 21, 9, 0),
        t("running", 7, 9, 139, 21, 9, 0),
        t("running", 9, 10, 141, 21, 9, 0),
        t("running", 11, 11, 145, 21, 9, 0),
        // The boundary is crossed here: charX drops by a whole room, the room number changes,
        // and baseX picks up the 320-pixel world offset.
        t("running", 13, 12, 10, 5, 0, 320),
        t("running", 16, 13, 12, 5, 0, 320),
        t("running", 18, 14, 15, 5, 0, 320),
        t("running", 2, 7, 19, 5, 0, 320),
        t("running", 4, 8, 24, 5, 0, 320),
        t("running", 7, 9, 25, 5, 1, 320),
        t("running", 9, 10, 27, 5, 0, 320),
        t("running", 11, 11, 31, 5, 0, 320),
        t("running", 13, 12, 36, 5, 1, 320),
        t("running", 16, 13, 38, 5, 2, 320),
        t("running", 18, 14, 41, 5, 1, 320),
    ])
}

@Test func crossingFromTheVeryEdgeTakesOneFewerTick() throws {
    let ticks = try run(actor(room: 21, blockX: 9, blockY: 0),
                        script: [none, none] + Array(repeating: right, count: 10))
    #expect(ticks == [
        t("stand", 2, 15, 133, 21, 8, 0),
        t("stand", 2, 15, 133, 21, 8, 0),
        t("startrun", 2, 1, 133, 21, 8, 0),
        t("startrun", 3, 2, 133, 21, 8, 0),
        t("startrun", 4, 3, 133, 21, 8, 0),
        t("startrun", 5, 4, 133, 21, 8, 0),
        t("startrun", 7, 5, 141, 21, 9, 0),
        t("startrun", 9, 6, 144, 21, 9, 0),
        t("running", 2, 7, 147, 21, 9, 0),
        t("running", 4, 8, 12, 5, 0, 320),
        t("running", 7, 9, 13, 5, 0, 320),
        t("running", 9, 10, 15, 5, 0, 320),
    ])
}

@Test func aRoomWithoutANeighbourDoesNotSwallowTheActor() throws {
    // Room 1 has no right neighbour, so the actor must stay put rather than wrap into nowhere.
    var state = actor(room: 1, blockX: 9, blockY: 0)
    state.charX = 150
    state.charFdx = 0
    state.charFfoot = 0
    state.updateBlockPosition(world: try LevelRuntime(try GameData.level(1)))
    #expect(state.room == 1)
    #expect(state.baseX == 0)
}

@Test func theActorKeepsItsRoomLocalHorizontalPosition() throws {
    // charX never becomes a world coordinate: crossing shifts it by exactly one room.
    let level = try LevelRuntime(try GameData.level(1))
    // blockX is floor((footX - 7) / 14), so column 10 begins at footX 147.
    var state = actor(room: 21, blockX: 9, blockY: 0)
    state.charX = 150
    state.charFdx = 0
    state.charFfoot = 0
    state.updateBlockPosition(world: level)
    #expect(state.room == 5)
    #expect(state.charX == 10, "150 - 140")
    #expect(state.charBlockX == 0)
    #expect(state.baseX == 320)
}

@Test func theLeftTransitionMirrorsTheRight() throws {
    let level = try LevelRuntime(try GameData.level(1))
    var state = actor(room: 5, blockX: 0, blockY: 0)
    state.charX = -1
    state.charFdx = 0
    state.charFfoot = 0
    state.updateBlockPosition(world: level)
    #expect(state.room == 21)
    #expect(state.charX == 139, "-1 + 140")
    #expect(state.charBlockX == 9)
    #expect(state.baseX == -320)
}

// MARK: - Falling out of the bottom

@Test func theKidUsesOneHundredAndEightyNineNotOneNinetyTwo() throws {
    // Kid.checkRoomChange fires at charY > 189; Fighter's fires at 192. The Prince uses the
    // former, guards the latter.
    let level = try LevelRuntime(try GameData.level(1))
    var state = actor(room: 1, blockX: 0, blockY: 2)
    state.charY = 190
    FallCycle.checkRoomChange(&state, world: level)
    #expect(state.charY == 1, "190 - 189")
    #expect(state.baseY == Geometry.roomHeight)
}

@Test func changeRoomDownPrefersTheRoomDirectlyBelow() throws {
    let level = try LevelRuntime(try GameData.level(1))
    #expect(level.roomLinks(1)?.down == 2)
    var state = actor(room: 1, blockX: 0, blockY: 2)
    state.charY = 190
    FallCycle.checkRoomChange(&state, world: level)
    #expect(state.room == 2)
    #expect(state.baseX == 0, "no horizontal shift when dropping straight down")
}
