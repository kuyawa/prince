import Testing
@testable import PoPCore

// M1: animation tables. Counts verified against the shipped JSON.

@Test(arguments: [
    ("kid", 75, 241),
    ("fighter", 23, 36),
    ("shadow", 51, 241),
    ("princess", 10, 48),
    ("vizier", 5, 39),
    ("mouse", 5, 4),
])
func animationTablesDecodeWithTheExpectedShape(name: String, sequences: Int, frameDefs: Int) throws {
    let table = try GameData.animationTable(named: name)
    #expect(table.sequences.count == sequences)
    #expect(table.frameDefs.count == frameDefs)
}

@Test func kidStartrunMatchesTheReferenceProgram() throws {
    // The exact program from assets/anims/kid.json.
    let kid = try GameData.animationTable(named: "kid")
    let startrun = try #require(kid.sequence("startrun"))

    #expect(startrun.count == 11)
    #expect(startrun[0].command == 249)          // CMD_ACT
    #expect(startrun[0].p1?.intValue == 1)
    #expect(startrun[1].command == 0)            // CMD_FRAME
    #expect(startrun[1].p1?.intValue == 1)
    #expect(startrun[5].command == 251)          // CMD_CHX
    #expect(startrun[5].p1?.intValue == 8)

    let exit = try #require(startrun.last)
    #expect(exit.command == 255)                 // CMD_GOTO
    #expect(exit.p1?.nameValue == "running")     // p1 is a sequence NAME, not a number
    #expect(exit.p2 == 1)
}

/// Opcodes whose `p1` is a sequence name rather than a number.
///
/// `CMD_GOTO` (255) jumps unconditionally. `CMD_IFWTLESS` (247) branches
/// conditionally — both name a target sequence.
private let nameBearingOpcodes: Set<UInt8> = [255, 247]

@Test func nameBearingOpcodesAlwaysCarryASequenceName() throws {
    // p1 is polymorphic in the data. If the decoder ever coerced one of these to a
    // number, the branch would silently go nowhere.
    for name in GameData.actorAnimationNames {
        let table = try GameData.animationTable(named: name)
        for (sequence, instructions) in table.sequences {
            for instruction in instructions where nameBearingOpcodes.contains(instruction.command) {
                #expect(instruction.p1?.nameValue != nil,
                        "\(name)/\(sequence): opcode \(instruction.command) has no sequence name")
            }
        }
    }
}

@Test func everyUnconditionalGoToTargetResolves() throws {
    for name in GameData.actorAnimationNames {
        let table = try GameData.animationTable(named: name)
        for (sequence, instructions) in table.sequences {
            for instruction in instructions where instruction.command == 255 {
                let target = try #require(instruction.p1?.nameValue)
                #expect(table.sequence(target) != nil,
                        "\(name)/\(sequence): CMD_GOTO -> \(target) does not exist")
            }
        }
    }
}

@Test func theOnlyDanglingSequenceReferenceIsShadowStepfloat() throws {
    // A real quirk in the source data, pinned rather than papered over.
    //
    // shadow.json's `stepfall` branches to `stepfloat` via CMD_IFWTLESS (247), but
    // shadow.json defines no `stepfloat` sequence. kid.json has the identical branch
    // and DOES define it. In JavaScript the shadow's branch is never taken, so the
    // reference is dead — but it is genuinely in the data, and M2 must not assume
    // that every named target resolves before consulting the table.
    var dangling: [String] = []
    for name in GameData.actorAnimationNames {
        let table = try GameData.animationTable(named: name)
        for (sequence, instructions) in table.sequences {
            for instruction in instructions where nameBearingOpcodes.contains(instruction.command) {
                guard let target = instruction.p1?.nameValue else { continue }
                if table.sequence(target) == nil {
                    dangling.append("\(name)/\(sequence)->\(target)")
                }
            }
        }
    }
    #expect(dangling == ["shadow/stepfall->stepfloat"])

    // And the sibling branch in kid.json is intact.
    let kid = try GameData.animationTable(named: "kid")
    #expect(kid.sequence("stepfloat") != nil)
}

@Test func frameIndicesStayInsideTheFrameTable() throws {
    // CMD_FRAME (0) selects a frame by index; every index must be addressable.
    for name in GameData.actorAnimationNames {
        let table = try GameData.animationTable(named: name)
        for instructions in table.sequences.values {
            for instruction in instructions where instruction.command == 0 {
                let index = try #require(instruction.p1?.intValue)
                #expect(table.frameDefs.indices.contains(index))
            }
        }
    }
}

@Test func referencedFramesAreComplete() throws {
    // The tables contain comment-only entries carrying no fdx/fdy/fcheck at all —
    // 19 in kid.json, 13 in shadow.json, 1 in fighter.json. In JavaScript those read
    // as `undefined`. That is only safe because no sequence ever targets one.
    // This proves the claim instead of assuming it, which is what licenses M2 to
    // treat a referenced frame's fields as present.
    for name in GameData.actorAnimationNames {
        let table = try GameData.animationTable(named: name)
        var referenced = Set<Int>()
        for instructions in table.sequences.values {
            for instruction in instructions where instruction.command == 0 {
                if let index = instruction.p1?.intValue { referenced.insert(index) }
            }
        }
        #expect(!referenced.isEmpty, "\(name) references no frames at all")
        for index in referenced.sorted() {
            let frame = try #require(table.frameDefs[index])
            #expect(frame.isComplete,
                    "\(name): a sequence targets frameDef \(index), which has no animation data")
        }
    }
}

@Test func swordOffsetsUseTheirOwnSchema() throws {
    // sword.json is not an AnimationTable; it has a single `swordtab` key.
    let sword = try GameData.swordOffsetTable()
    #expect(sword.count == 50)
    let first = try #require(sword.offset(at: 0))
    #expect(first.id == 1)
    #expect(first.dx == 0)
    #expect(first.dy == -9)
    // Ids are not contiguous, so array position and id are genuinely different.
    #expect(sword.offset(id: 6)?.dx == -9)
}
