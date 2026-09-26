import Testing
@testable import PoPCore

// M1: the fcheck bitfield.
//
// Actor.js#updateCharFrame:
//   foot  = fcheck & 0x1f
//   thin  = fcheck & 0x20
//   check = fcheck & 0x40
//   half  = fcheck & 0x80
//
// Losing a bit here changes where the Prince can stand, so each bit is asserted
// independently rather than via a round trip.

@Test func zeroIsTheAbsenceOfEverything() throws {
    let check = try FrameCheck(hexString: "0x00")
    #expect(check.rawValue == 0)
    #expect(check.foot == 0)
    #expect(check.isThin == false)
    #expect(check.isCheckActive == false)
    #expect(check.isHalfPixelOffset == false)
}

@Test func checkActiveBitIsBitSix() throws {
    let check = try FrameCheck(hexString: "0x44")
    #expect(check.rawValue == 0x44)
    #expect(check.foot == 4)
    #expect(check.isThin == false)
    #expect(check.isCheckActive == true)
    #expect(check.isHalfPixelOffset == false)
}

@Test func halfPixelBitIsBitSeven() throws {
    let check = try FrameCheck(hexString: "0x80")
    #expect(check.foot == 0)
    #expect(check.isThin == false)
    #expect(check.isCheckActive == false)
    #expect(check.isHalfPixelOffset == true)
}

@Test func allFourFlagsTogetherParseIndependently() throws {
    // 0xC4 is a real value from kid.json's frame table.
    let check = try FrameCheck(hexString: "0xC4")
    #expect(check.foot == 4)
    #expect(check.isThin == false)
    #expect(check.isCheckActive == true)
    #expect(check.isHalfPixelOffset == true)

    // 0xEF sets every bit: foot 15, and thin, check and half all on.
    let all = try FrameCheck(hexString: "0xEF")
    #expect(all.foot == 15)
    #expect(all.isThin == true)
    #expect(all.isCheckActive == true)
    #expect(all.isHalfPixelOffset == true)
}

@Test func theDecoderAcceptsTheOnDiskSpelling() throws {
    // The data uses a lowercase 0x with uppercase hex digits.
    #expect(try FrameCheck(hexString: "0xC4").rawValue == 0xC4)
    #expect(try FrameCheck(hexString: "0xc4").rawValue == 0xC4)
    #expect(try FrameCheck(hexString: "C4").rawValue == 0xC4)
}

@Test func nonHexInputIsRejected() {
    #expect(throws: (any Error).self) { try FrameCheck(hexString: "0xZZ") }
    #expect(throws: (any Error).self) { try FrameCheck(hexString: "") }
    #expect(throws: (any Error).self) { try FrameCheck(hexString: "0x1FF") }
}

@Test func everyFrameCheckInEveryAnimationTableParses() throws {
    var seen = Set<UInt8>()
    for name in GameData.actorAnimationNames {
        let table = try GameData.animationTable(named: name)
        for frame in table.frameDefs {
            // Comment-only entries carry no fcheck; they are skipped, and
            // `referencedFramesAreComplete` proves no sequence targets one.
            if let check = frame.check { seen.insert(check.rawValue) }
        }
    }
    // 50 distinct values across the shipped tables.
    #expect(seen.count == 50)
    #expect(seen.contains(0xC4))
    #expect(seen.contains(0xEF))
}
