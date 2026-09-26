import Testing
@testable import PoPCore

// M2: ActorState — the reference's char* field set.

@Test func spawnLocationUsesTheFighterConvention() {
    // Fighter's constructor: charBlockX = location % 10, charBlockY = floor(location / 10).
    // ARCHITECTURE.md open question 8 — this is NOT the 1-based event convention.
    let state = ActorState(location: 11, room: 1, face: 1)
    #expect(state.charBlockX == 1)
    #expect(state.charBlockY == 1)
    #expect(state.charX == 21)     // 1 * 14 + 7
    #expect(state.charY == 116)    // (1 + 1) * 63 - 10
    #expect(state.room == 1)
    #expect(state.actionCode == 1)
    #expect(state.isAlive)
    #expect(!state.swordDrawn)
}

@Test func beginActionResetsTheCursor() {
    // The JavaScript action SETTER does this. CMD_GOTO deliberately does not use it.
    var state = ActorState(location: 11, room: 1, face: 1, action: "running")
    state.sequencePointer = 7
    state.beginAction("stand")
    #expect(state.action == "stand")
    #expect(state.sequencePointer == 0)
}

@Test func applyFrameDefinitionUnpacksTheCheckBitfield() throws {
    // 0xC4 = foot 4, not thin, check-active, half-pixel parity.
    var state = ActorState(location: 11, room: 1, face: 1)
    let definition = FrameDef(
        dx: 3, dy: 1, check: try FrameCheck(hexString: "0xC4"), swordFrame: 9, comment: nil
    )
    state.applyFrameDefinition(definition)
    #expect(state.charFdx == 3)
    #expect(state.charFdy == 1)
    #expect(state.charFfoot == 4)
    #expect(state.charFthin == false)
    #expect(state.charFcheck == true)
    #expect(state.charFood == true)
    #expect(state.hasSwordFrame)
}

@Test func aFrameWithoutASwordReportsNone() throws {
    var state = ActorState(location: 11, room: 1, face: 1)
    state.applyFrameDefinition(
        FrameDef(dx: 1, dy: 0, check: try FrameCheck(hexString: "0x00"), swordFrame: nil, comment: nil)
    )
    #expect(!state.hasSwordFrame)
}

@Test func aCommentOnlyFrameDefinitionZeroesRatherThanCrashing() {
    // 33 such entries exist across the shipped tables. Referenced frames are always
    // complete (proved in AnimationTableTests), so this path is unreachable in the real
    // game — but the state must not trap on it.
    //
    // The reference reads `undefined` here, which would poison every later arithmetic
    // with NaN. Mapping the absent fields to zero is the sane reading for an Int model,
    // and it is unreachable either way.
    var state = ActorState(location: 11, room: 1, face: 1)
    state.charFdx = 99
    state.applyFrameDefinition(FrameDef(dx: nil, dy: nil, check: nil, swordFrame: nil, comment: "note"))
    #expect(state.charFdx == 0)
    #expect(state.charFdy == 0)
    #expect(state.charFfoot == 0)
    #expect(!state.hasSwordFrame)
}

@Test func footPositionDrivesTheBlockColumn() {
    // updateBlockXY subtracts the foot offset before converting, which is how a
    // 14-unit-wide footprint lands in the right column.
    var state = ActorState(location: 11, room: 1, face: 1)
    state.charX = 21
    state.charY = 116
    state.charFdx = 0
    state.charFdy = 0
    state.charFfoot = 0
    state.updateBlockPosition()
    #expect(state.charBlockX == 1)
    #expect(state.charBlockY == 1)

    // Facing left the foot offset is subtracted the other way:
    // footX = 21 + 0 - 10 * (-1) = 31, and floor((31 - 7) / 14) = 1.
    state.charFace = -1
    state.charFfoot = 10
    state.updateBlockPosition()
    #expect(state.charBlockX == 1)

    // Push the foot far enough left and the column goes negative — which is what
    // triggers a room transition in Fighter.updateBlockXY (M5).
    state.charFace = 1
    state.charFfoot = 20
    state.updateBlockPosition()
    #expect(state.charBlockX == -1)
}
