import Testing
@testable import PoPCore

// M2: the sequence VM.
//
// Every expected value below was produced by a faithful re-implementation of
// Actor.processCommand driving the real assets/anims/kid.json, not by hand. If the
// Swift interpreter diverges from the reference, these fail.

private struct Tick: Equatable, CustomStringConvertible {
    var action: String
    var pointer: Int
    var frame: Int
    var x: Int
    var y: Int
    var face: Int
    var code: Int
    var blockX: Int
    var blockY: Int

    init(_ state: ActorState) {
        action = state.action
        pointer = state.sequencePointer
        frame = state.charFrame
        x = state.charX
        y = state.charY
        face = state.charFace
        code = state.actionCode
        blockX = state.charBlockX
        blockY = state.charBlockY
    }

    init(action: String, pointer: Int, frame: Int, x: Int, y: Int,
         face: Int, code: Int, blockX: Int, blockY: Int) {
        self.action = action; self.pointer = pointer; self.frame = frame
        self.x = x; self.y = y; self.face = face
        self.code = code; self.blockX = blockX; self.blockY = blockY
    }

    var description: String {
        "(\(action) ptr=\(pointer) frame=\(frame) x=\(x) y=\(y) face=\(face) code=\(code) bx=\(blockX) by=\(blockY))"
    }
}

private func at(_ action: String, ptr: Int, frame: Int, x: Int, y: Int,
                face: Int = 1, code: Int, bx: Int, by: Int) -> Tick {
    Tick(action: action, pointer: ptr, frame: frame, x: x, y: y,
         face: face, code: code, blockX: bx, blockY: by)
}

/// Location 11 -> blockX 1, blockY 1 -> charX 21, charY 116.
private func run(
    _ action: String,
    ticks: Int,
    table name: String = "kid",
    as actorClass: ActorClass = .kid,
    location: Int = 11
) throws -> [Tick] {
    let interpreter = SequenceInterpreter(
        table: try GameData.animationTable(named: name), actorClass: actorClass
    )
    var state = ActorState(location: location, room: 1, face: 1, action: action)
    var effects: [ActorEffect] = []
    var result: [Tick] = []
    for _ in 0..<ticks {
        try interpreter.step(&state, effects: &effects)
        result.append(Tick(state))
    }
    return result
}

// MARK: - Reference traces

@Test func standReachesItsFixedPointOnTheFirstTick() throws {
    // stand = [ACT 0, FRAME 15, GOTO "stand" 1]
    // Tick 1 consumes ACT and FRAME. From then on every tick runs GOTO -> FRAME and
    // lands back on the same cursor, so the state is identical forever after.
    let expected = at("stand", ptr: 2, frame: 15, x: 21, y: 116, code: 0, bx: 0, by: 1)
    let ticks = try run("stand", ticks: 4)
    #expect(ticks == [expected, expected, expected, expected])
}

@Test func startrunMatchesTheReferenceTrace() throws {
    let ticks = try run("startrun", ticks: 6)
    #expect(ticks == [
        at("startrun", ptr: 2, frame: 1, x: 21, y: 116, code: 1, bx: 0, by: 1),
        at("startrun", ptr: 3, frame: 2, x: 21, y: 116, code: 1, bx: 0, by: 1),
        at("startrun", ptr: 4, frame: 3, x: 21, y: 116, code: 1, bx: 0, by: 1),
        at("startrun", ptr: 5, frame: 4, x: 21, y: 116, code: 1, bx: 0, by: 1),
        // CHX 8 fires before FRAME 5, so x advances and the block follows.
        at("startrun", ptr: 7, frame: 5, x: 29, y: 116, code: 1, bx: 1, by: 1),
        // CHX 3.
        at("startrun", ptr: 9, frame: 6, x: 32, y: 116, code: 1, bx: 1, by: 1),
    ])
}

@Test func runningAdvancesXByTheSumOfItsChangeXInstructions() throws {
    let ticks = try run("running", ticks: 5)
    #expect(ticks == [
        at("running", ptr: 2, frame: 7, x: 21, y: 116, code: 1, bx: 0, by: 1),
        at("running", ptr: 4, frame: 8, x: 26, y: 116, code: 1, bx: 1, by: 1),   // +5
        at("running", ptr: 7, frame: 9, x: 27, y: 116, code: 1, bx: 1, by: 1),   // +1
        at("running", ptr: 9, frame: 10, x: 29, y: 116, code: 1, bx: 1, by: 1),  // +2
        at("running", ptr: 11, frame: 11, x: 33, y: 116, code: 1, bx: 1, by: 1), // +4
    ])
}

@Test func turnFlipsFacingAndNegatesSubsequentChangeX() throws {
    let ticks = try run("turn", ticks: 4)
    #expect(ticks == [
        // ACT 7, ABOUTFACE, then CHX 6 with face now -1.
        at("turn", ptr: 4, frame: 45, x: 15, y: 116, face: -1, code: 7, bx: 0, by: 1),
        at("turn", ptr: 6, frame: 46, x: 14, y: 116, face: -1, code: 7, bx: 0, by: 1),
        at("turn", ptr: 8, frame: 47, x: 12, y: 116, face: -1, code: 7, bx: 0, by: 1),
        // CHX -1 with face -1 moves RIGHT.
        at("turn", ptr: 10, frame: 48, x: 13, y: 116, face: -1, code: 7, bx: 0, by: 1),
    ])
}

@Test func gotoHandsControlToAnotherSequenceWithinTheSameTick() throws {
    // softland ends with GOTO "stoop" 5. The tick that reaches it keeps looping and
    // executes into the target sequence — it does not simply stop there.
    let ticks = try run("softland", ticks: 4)
    #expect(ticks == [
        at("softland", ptr: 5, frame: 107, x: 22, y: 116, code: 5, bx: 0, by: 1),
        at("softland", ptr: 7, frame: 108, x: 24, y: 116, code: 5, bx: 0, by: 1),
        at("softland", ptr: 10, frame: 109, x: 24, y: 116, code: 1, bx: 0, by: 1),
        // Now inside "stoop": the action changed but the frame did not.
        at("stoop", ptr: 6, frame: 109, x: 24, y: 116, code: 1, bx: 0, by: 1),
    ])
}

@Test func stepfallCarriesItsVerticalOffsets() throws {
    // Exercises CHY (250), which moves charY in pixels while charX stays in x-units.
    let ticks = try run("stepfall", ticks: 3)
    #expect(ticks == [
        at("stepfall", ptr: 5, frame: 102, x: 22, y: 119, code: 3, bx: 0, by: 1),
        at("stepfall", ptr: 8, frame: 103, x: 24, y: 125, code: 3, bx: 0, by: 1),
        at("stepfall", ptr: 11, frame: 104, x: 23, y: 134, code: 3, bx: 0, by: 2),
    ])
}

// MARK: - The loop's shape

@Test func oneTickConsumesEveryInstructionUpToAndIncludingOneFrame() throws {
    // startrun's first two instructions are ACT then FRAME: one tick, cursor at 2.
    let interpreter = SequenceInterpreter(
        table: try GameData.animationTable(named: "kid"), actorClass: .kid
    )
    var state = ActorState(location: 11, room: 1, face: 1, action: "startrun")
    var effects: [ActorEffect] = []
    try interpreter.step(&state, effects: &effects)
    #expect(state.sequencePointer == 2)
    #expect(state.charFrame == 1)
    #expect(state.isProcessing == false)
}

@Test func anUnknownSequenceFailsLoudly() throws {
    let interpreter = SequenceInterpreter(
        table: try GameData.animationTable(named: "kid"), actorClass: .kid
    )
    var state = ActorState(location: 11, room: 1, face: 1, action: "no-such-action")
    var effects: [ActorEffect] = []
    #expect(throws: SequenceInterpreter.Failure.unknownSequence("no-such-action")) {
        try interpreter.step(&state, effects: &effects)
    }
}

// MARK: - The per-class opcode gate
//
// The tables cross actor classes. A byte that is a real opcode but is not registered
// for the actor executing it is a silent no-op, and modelling the tables as one flat
// union would give guards and shadows behaviour they have never had.

@Test func jardIsANoOpForAFighterButShakesForTheKid() throws {
    // shadow.json's softland = [ACT, JARD, CHX, TAP, FRAME, ...]. JARD (244) is
    // registered by Kid alone; the shadow is an Enemy, a Fighter subclass.
    let table = try GameData.animationTable(named: "shadow")

    var fighterState = ActorState(location: 11, room: 1, face: 1, action: "softland")
    var fighterEffects: [ActorEffect] = []
    try SequenceInterpreter(table: table, actorClass: .fighter)
        .step(&fighterState, effects: &fighterEffects)
    #expect(!fighterEffects.contains { if case .shakeFloor = $0 { true } else { false } })

    var kidState = ActorState(location: 11, room: 1, face: 1, action: "softland")
    var kidEffects: [ActorEffect] = []
    try SequenceInterpreter(table: table, actorClass: .kid)
        .step(&kidState, effects: &kidEffects)
    #expect(kidEffects.contains { if case .shakeFloor = $0 { true } else { false } })

    // Same data, same tick, different actor class — and the frame lands identically.
    #expect(fighterState.charFrame == kidState.charFrame)
}

@Test func theShadowDanglingBranchIsUnreachableBecauseIfWithLessIsAKidOpcode() throws {
    // A satisfying closure on the dangling reference M1 found.
    //
    // shadow.json's stepfall branches to "stepfloat" via IFWTLESS (247), and shadow.json
    // defines no such sequence. The reference is inert because IFWTLESS is registered by
    // Kid alone, so for the shadow it is a no-op. Feed the same data to a Kid and it
    // explodes — which is the proof.
    let table = try GameData.animationTable(named: "shadow")

    var shadowState = ActorState(location: 11, room: 1, face: 1, action: "stepfall")
    shadowState.isInFloat = true
    var shadowEffects: [ActorEffect] = []
    try SequenceInterpreter(table: table, actorClass: .fighter)
        .step(&shadowState, effects: &shadowEffects)
    #expect(shadowState.action == "stepfall")   // untouched

    var kidState = ActorState(location: 11, room: 1, face: 1, action: "stepfall")
    kidState.isInFloat = true
    var kidEffects: [ActorEffect] = []
    #expect(throws: SequenceInterpreter.Failure.unknownSequence("stepfloat")) {
        try SequenceInterpreter(table: table, actorClass: .kid)
            .step(&kidState, effects: &kidEffects)
    }
}

@Test func theMouseClassHasNoActOpcode() throws {
    // Mouse extends Actor, not Fighter, so it never registers ACT (249) — yet
    // mouse.json uses it. For the mouse it is a no-op.
    let table = try GameData.animationTable(named: "mouse")
    // "scurry" = [ACT, FRAME, CHX, FRAME, CHX, FRAME, CHX, GOTO]. Both "scurry" and
    // "leave" use ACT; name one so the test does not depend on dictionary order.
    let withAct = try #require(table.sequence("scurry"))

    for actorClass in [ActorClass.actor, .kid] {
        var state = ActorState(location: 11, room: 1, face: 1, action: "scurry")
        state.actionCode = -1
        var effects: [ActorEffect] = []
        try SequenceInterpreter(table: table, actorClass: actorClass)
            .step(&state, effects: &effects)
        #expect(!withAct.isEmpty)
        if actorClass == .actor {
            #expect(state.actionCode == -1, "ACT must be inert for the mouse")
        } else {
            #expect(state.actionCode != -1, "ACT is registered for Kid")
        }
    }
}

@Test func actorClassRegistrationMatchesTheReferenceChains() {
    #expect(ActorClass.actor.registeredOpcodes.count == 6)    // Actor
    #expect(ActorClass.fighter.registeredOpcodes.count == 9)  // + Fighter
    #expect(ActorClass.kid.registeredOpcodes.count == 16)     // + Kid

    #expect(!ActorClass.actor.registers(.act))
    #expect(ActorClass.fighter.registers(.act))
    #expect(!ActorClass.fighter.registers(.jard))
    #expect(ActorClass.kid.registers(.jard))
    #expect(!ActorClass.fighter.registers(.up))
    #expect(ActorClass.kid.registers(.up))
}

// MARK: - Effects

@Test func nextLevelEmitsAnEffectRatherThanActing() throws {
    // climbstairs = [..., NEXTLEVEL (241), ...] for the Kid.
    let table = try GameData.animationTable(named: "kid")
    let sequence = try #require(table.sequences.first { $0.value.contains { $0.command == 241 } })

    let interpreter = SequenceInterpreter(table: table, actorClass: .kid)
    var state = ActorState(location: 11, room: 1, face: 1, action: sequence.key)
    var effects: [ActorEffect] = []
    // Step until NEXTLEVEL is consumed or the sequence settles.
    for _ in 0..<40 where !effects.contains(.advanceToNextLevel) {
        try interpreter.step(&state, effects: &effects)
    }
    #expect(effects.contains(.advanceToNextLevel))
}

@Test func tapEmitsTheSoundCueIndex() throws {
    let table = try GameData.animationTable(named: "kid")
    var state = ActorState(location: 11, room: 1, face: 1, action: "running")
    var effects: [ActorEffect] = []
    let interpreter = SequenceInterpreter(table: table, actorClass: .kid)
    for _ in 0..<3 { try interpreter.step(&state, effects: &effects) }
    // running uses TAP with p1 = 1 (footsteps).
    #expect(effects.contains(.tap(1)))
}
