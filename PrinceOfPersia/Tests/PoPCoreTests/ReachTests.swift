import Testing
@testable import PoPCore

// The path walk behind `canReachOpponent`, and the `walk` clause of `canCrossGate`.
//
// `canReachOpponent` was the last *simplification* in the port: it kept a distance test where the
// reference walks the columns between the two fighters. That walk measures from `centerX`, so it
// was blocked on the same screen geometry `checkBarrier` was — and `SpriteMetrics` closed both.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

private func hero(_ x: Int, _ y: Int, room: Int, face: Int = 1) -> ActorState {
    var state = ActorState(location: 0, room: room, face: face, action: "stand", charName: "kid")
    state.charBlockX = x
    state.charBlockY = y
    state.charX = CoordinateSpace.x(fromBlockX: x)
    state.charY = CoordinateSpace.y(fromBlockY: y)
    state.action = "running"
    state.charFrame = 8
    state.charFdx = 0
    state.charFfoot = 0
    return state
}

private func foe(_ x: Int, _ y: Int, room: Int, face: Int = -1) -> ActorState {
    var state = ActorState(location: 0, room: room, face: face, action: "stand", charName: "guard-2")
    state.charBlockX = x
    state.charBlockY = y
    state.charX = CoordinateSpace.x(fromBlockX: x)
    state.charY = CoordinateSpace.y(fromBlockY: y)
    state.action = "stand"
    state.charFrame = 16
    state.charFdx = 0
    state.charFfoot = 0
    return state
}

// MARK: - The walk

@Test func aClearCorridorIsSeenAllTheWayAlong() throws {
    // Level 1 room 17 row 2: `W W P Po P F F W W W`. Columns 5 and 6 are floor, so a fighter on
    // one can reach the other.
    let world = World(try levelOne())
    let me = hero(5, 2, room: 17)
    let you = foe(6, 2, room: 17)

    var visited: [Int] = []
    let clear = Combat.checkPathToOpponent(
        me, you, world: world, from: 5, blockY: 2, room: 17
    ) { x, _, _ in
        visited.append(x)
        return (world.tile(x: x, y: 2, room: 17).kind.isSafeWalkable, false)
    }
    #expect(clear)
    #expect(visited == [5, 6], "every column between them, inclusive")
}

@Test func oneBadColumnStopsTheWalk() throws {
    // Column 7 of that row is a wall. Walking from 5 to 8 must come back false, and must stop
    // *at* the wall rather than carrying on.
    let world = World(try levelOne())
    let me = hero(5, 2, room: 17)
    let you = foe(8, 2, room: 17)

    var visited: [Int] = []
    let clear = Combat.checkPathToOpponent(
        me, you, world: world, from: 5, blockY: 2, room: 17
    ) { x, _, _ in
        visited.append(x)
        return (world.tile(x: x, y: 2, room: 17).kind.isSafeWalkable, false)
    }
    #expect(!clear)
    #expect(visited == [5, 6, 7], "and it does not look past the wall")
}

@Test func walkingLeftVisitsTheOtherWayRound() throws {
    // The direction is chosen from `centerX`, not from the facing.
    let world = World(try levelOne())
    let me = hero(8, 2, room: 17, face: -1)
    let you = foe(5, 2, room: 17, face: 1)

    var visited: [Int] = []
    _ = Combat.checkPathToOpponent(me, you, world: world, from: 8, blockY: 2, room: 17) { x, _, _ in
        visited.append(x)
        return (true, false)
    }
    #expect(visited == [8, 7, 6, 5])
}

@Test func aStopEndsTheWalkEarly() throws {
    let world = World(try levelOne())
    let me = hero(5, 2, room: 17)
    let you = foe(8, 2, room: 17)

    var visited: [Int] = []
    let result = Combat.checkPathToOpponent(
        me, you, world: world, from: 5, blockY: 2, room: 17
    ) { x, _, _ in
        visited.append(x)
        return (true, x == 6)
    }
    #expect(result, "a stop returns the value it stopped on")
    #expect(visited == [5, 6])
}

// MARK: - Reaching

@Test func twoFightersOnClearGroundCanReachEachOther() throws {
    let world = World(try levelOne())
    let me = hero(5, 2, room: 17)
    let you = foe(6, 2, room: 17)
    #expect(Combat.canReachOpponent(me, you, world: world))
    #expect(Combat.canReachOpponent(you, me, world: world))
}

@Test func aWallBetweenThemStopsTheGuardReaching() throws {
    // Columns 5 and 6 are floor, 7 is a wall, 8 is floor. The distance test this replaced would
    // have said yes.
    let world = World(try levelOne())
    let me = hero(5, 2, room: 17)
    let you = foe(8, 2, room: 17)
    #expect(!Combat.canReachOpponent(me, you, world: world))
}

@Test func canWalkOnTileKnowsWhereHeIsStanding() throws {
    // `standsOnTile` compares tile *identity*, which over a grid means the same position. So the
    // tile under his feet is walkable whatever it is made of — including space, which is how a
    // fighter mid-fall is not told he cannot stand where he already is.
    let world = World(try levelOne())
    let me = hero(5, 2, room: 17)
    #expect(Combat.canWalkOnTile(me, me, world: world, x: 5, y: 2, room: 17))
    #expect(Combat.standsOnTile(me, x: 5, y: 2, room: 17))
    #expect(!Combat.standsOnTile(me, x: 6, y: 2, room: 17))
    #expect(!Combat.standsOnTile(me, x: 5, y: 2, room: 16), "a different room is a different tile")
}
