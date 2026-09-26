import Testing
@testable import PoPCore

// M3b: the control layer.
//
// Expected values come from a faithful re-implementation of Kid.updateBehaviour in Node,
// driving the real kid.json and maps/level1.json. The actor starts at location 11 in
// level 1 room 1 — grid (1,1), so charX 21 and charY 116.
//
// Note the Node tracer initially disagreed with the reference because it stored the
// action in a plain property. In JavaScript `this.action = x` goes through a prototype
// SETTER that resets `_seqpointer` to 0, while `CMD_GOTO` assigns `_action` directly and
// bypasses it. That distinction is `ActorState.beginAction` versus plain assignment, and
// getting it wrong makes every verb resume mid-sequence.

private struct Tick: Equatable, CustomStringConvertible {
    var action: String
    var pointer: Int
    var frame: Int
    var x: Int
    var y: Int
    var face: Int
    var blockX: Int

    init(_ state: ActorState) {
        action = state.action
        pointer = state.sequencePointer
        frame = state.charFrame
        x = state.charX
        y = state.charY
        face = state.charFace
        blockX = state.charBlockX
    }

    init(_ action: String, _ pointer: Int, _ frame: Int, _ x: Int, _ y: Int,
         _ face: Int, _ blockX: Int) {
        self.action = action; self.pointer = pointer; self.frame = frame
        self.x = x; self.y = y; self.face = face; self.blockX = blockX
    }

    var description: String {
        "(\(action) ptr=\(pointer) frame=\(frame) x=\(x) y=\(y) face=\(face) bx=\(blockX))"
    }
}

private func t(_ a: String, _ p: Int, _ f: Int, _ x: Int, _ y: Int, _ face: Int, _ bx: Int) -> Tick {
    Tick(a, p, f, x, y, face, bx)
}

private let none = Intents.none
private let right: Intents = [.right]
private let left: Intents = [.left]
private let rightUp: Intents = [.right, .up]

/// Runs a scripted input program: behaviour first, then the sequence, exactly as
/// `Kid.updateActor` orders them.
private func run(_ script: [Intents], level: LevelRuntime, interpreter: SequenceInterpreter) throws -> [Tick] {
    var state = ActorState(location: 11, room: 1, face: 1, action: "stand")
    var effects: [ActorEffect] = []
    var result: [Tick] = []
    for intents in script {
        Behaviour.update(&state, intents: intents, world: level)
        try interpreter.step(&state, world: level, effects: &effects)
        result.append(Tick(state))
    }
    return result
}

private func harness() throws -> (LevelRuntime, SequenceInterpreter) {
    let level = try LevelRuntime(try GameData.level(1))
    let interpreter = SequenceInterpreter(
        table: try GameData.animationTable(named: "kid"), actorClass: .kid
    )
    return (level, interpreter)
}

// MARK: - Reference traces

@Test func walkingMatchesTheReferenceTrace() throws {
    let (level, interpreter) = try harness()
    let ticks = try run([none, none] + Array(repeating: right, count: 10),
                        level: level, interpreter: interpreter)
    #expect(ticks == [
        t("stand", 2, 15, 21, 116, 1, 0),
        t("stand", 2, 15, 21, 116, 1, 0),
        // Pressing the way he already faces starts a run, not a turn.
        t("startrun", 2, 1, 21, 116, 1, 0),
        t("startrun", 3, 2, 21, 116, 1, 0),
        t("startrun", 4, 3, 21, 116, 1, 0),
        t("startrun", 5, 4, 21, 116, 1, 0),
        t("startrun", 7, 5, 29, 116, 1, 1),
        t("startrun", 9, 6, 32, 116, 1, 1),
        // startrun hands over to running.
        t("running", 2, 7, 35, 116, 1, 1),
        t("running", 4, 8, 40, 116, 1, 2),
        t("running", 7, 9, 41, 116, 1, 2),
        t("running", 9, 10, 43, 116, 1, 2),
    ])
}

@Test func turningRoundMatchesTheReferenceTrace() throws {
    let (level, interpreter) = try harness()
    let ticks = try run([none, none] + Array(repeating: left, count: 8),
                        level: level, interpreter: interpreter)
    #expect(ticks == [
        t("stand", 2, 15, 21, 116, 1, 0),
        t("stand", 2, 15, 21, 116, 1, 0),
        // Pressing away from the facing turns on the spot: ABOUTFACE then CHX 6, which
        // now moves in the NEW direction, so x goes DOWN by 6.
        t("turn", 4, 45, 15, 116, -1, 0),
        t("turn", 6, 46, 14, 116, -1, 0),
        t("turn", 8, 47, 12, 116, -1, 0),
        t("turn", 10, 48, 13, 116, -1, 0),
        // Turn completes on frame 48, the key is held, and he would break into a run —
        // but he is now at column 0 facing a wall, so startrun routes to step() instead.
        // That is the nearBarrier path, and the action name encodes the distance.
        t("step10", 2, 121, 15, 116, -1, 0),
        t("step10", 4, 122, 14, 116, -1, 0),
        t("step10", 6, 123, 13, 116, -1, 0),
        t("step10", 8, 124, 10, 116, -1, 0),
    ])
}

@Test func stoppingMatchesTheReferenceTrace() throws {
    let (level, interpreter) = try harness()
    let ticks = try run([none, none] + Array(repeating: right, count: 4) + Array(repeating: none, count: 8),
                        level: level, interpreter: interpreter)
    #expect(ticks == [
        t("stand", 2, 15, 21, 116, 1, 0),
        t("stand", 2, 15, 21, 116, 1, 0),
        t("startrun", 2, 1, 21, 116, 1, 0),
        t("startrun", 3, 2, 21, 116, 1, 0),
        t("startrun", 4, 3, 21, 116, 1, 0),
        t("startrun", 5, 4, 21, 116, 1, 0),
        t("startrun", 7, 5, 29, 116, 1, 1),
        t("startrun", 9, 6, 32, 116, 1, 1),
        t("running", 2, 7, 35, 116, 1, 1),
        // Releasing the key only stops if the run cycle is on frame 7 or 11.
        t("runstop", 2, 53, 35, 116, 1, 1),
        t("runstop", 5, 54, 37, 116, 1, 2),
        t("runstop", 7, 55, 44, 116, 1, 2),
        t("runstop", 9, 56, 44, 116, 1, 2),
        t("runstop", 11, 49, 46, 116, 1, 2),
    ])
}

@Test func jumpFromARunMatchesTheReferenceTrace() throws {
    let (level, interpreter) = try harness()
    let ticks = try run([none, none] + Array(repeating: right, count: 6) + [rightUp],
                        level: level, interpreter: interpreter)
    #expect(ticks.count == 9)
    #expect(ticks.last == t("runjump", 3, 34, 32, 116, 1, 1))
    // Up does nothing while standing still here — jump() is deferred, see Behaviour.
    #expect(ticks[0] == t("stand", 2, 15, 21, 116, 1, 0))
}

// MARK: - Verb-level behaviour

@Test func runstopIsGatedOnTwoFramesOfTheRunCycle() throws {
    let (level, interpreter) = try harness()
    // Release early: frame 1 is not one of the allowed frames, so nothing happens.
    let ticks = try run([none, none, right, none, none], level: level, interpreter: interpreter)
    #expect(ticks[2].action == "startrun")
    #expect(ticks[3].action == "startrun", "release on frame 1 must not stop the run")
    #expect(ticks[4].action == "startrun")
}

@Test func startrunRoutesToStepWhenFacingAWall() throws {
    let level = try LevelRuntime(try GameData.level(1))
    // Level 1 room 1, rows as stored (row 0 is the TOP of the room):
    //   row 0: SPACE SPACE SPACE FLOOR FLOOR FLOOR FLOOR FLOOR WALL WALL
    //   row 1: TORCH TORCH FLOOR PILLAR SPACE WALL WALL WALL WALL WALL
    // Walking right, row 0 is clear up to column 6 and blocked from column 7 (wall at 8);
    // row 1 is clear to column 3 and blocked from column 4.
    var state = ActorState(location: 11, room: 1, face: 1, action: "stand")
    #expect(state.charBlockY == 1)

    state.charBlockX = 3
    #expect(!Behaviour.nearBarrier(state, world: level),
            "row 1 column 4 is space, so nothing blocks from column 3")

    state.charBlockX = 4
    #expect(Behaviour.nearBarrier(state, world: level), "row 1 column 5 is wall, straight ahead")

    // Same columns one row up are clear, because row 0 has floor out to column 7.
    state.charBlockY = 0
    state.charBlockX = 4
    #expect(!Behaviour.nearBarrier(state, world: level),
            "row 0 column 5 is floor, so the same column is clear a row higher")

    state.charBlockX = 7
    #expect(Behaviour.nearBarrier(state, world: level), "row 0 column 8 is wall")
}

@Test func nearBarrierTreatsTheEdgeOfTheLevelAsAWall() throws {
    let level = try LevelRuntime(try GameData.level(1))
    // Column 0 facing left looks at column -1, which the world reports as off-map.
    var state = ActorState(location: 0, room: 1, face: -1, action: "stand")
    state.charBlockX = 0
    #expect(Behaviour.nearBarrier(state, world: level))
}

@Test func stepUsesTheDistanceAsItsSequenceName() throws {
    // "step" + min(px, 14) is why the animation table carries step1...step14 as separate
    // sequences — the Prince's final resting place at a ledge depends on which one runs.
    var names = Set<String>()
    let table = try GameData.animationTable(named: "kid")
    for index in 1...14 {
        let name = "step\(index)"
        #expect(table.sequence(name) != nil, "\(name) missing from the animation table")
        names.insert(name)
    }
    #expect(names.count == 14)
}

@Test func releasingAKeyReArmsTheLatchedGuards() throws {
    let level = try LevelRuntime(try GameData.level(1))

    // Facing right and holding right: neither re-arm condition fires, because the first
    // needs left released *and* a left-facing actor, and the second needs right released.
    var held = ActorState(location: 11, room: 1, face: 1, action: "stand")
    held.allowCrawl = false
    held.allowAdvance = false
    Behaviour.update(&held, intents: [.right], world: level)
    #expect(held.allowCrawl == false, "holding the facing key must not re-arm the guard")
    #expect(held.allowAdvance == false)

    // Releasing it does re-arm, because `!keyR && faceR` now holds.
    Behaviour.update(&held, intents: .none, world: level)
    #expect(held.allowCrawl)
    #expect(held.allowAdvance)

    // The reference ORs two conditions, so a released key re-arms even while the opposite
    // one is held: left down with a right-facing actor still settles `allowCrawl`.
    var crossed = ActorState(location: 11, room: 1, face: 1, action: "stand")
    crossed.allowCrawl = false
    Behaviour.update(&crossed, intents: [.left], world: level)
    #expect(crossed.allowCrawl, "!keyR && faceR fires even though left is held")
}
