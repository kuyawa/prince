import Testing
@testable import PoPCore

// M2: the coordinate conversions from Utils.js.
//
// The horizontal and vertical axes use different units. charX is in x-units
// (140 per room, 14 per tile column); charY is in pixels (189 per room, 63 per tile).

@Test func horizontalAndVerticalUnitsDiffer() {
    #expect(CoordinateSpace.xUnitsPerTileColumn == 14)
    #expect(CoordinateSpace.xUnitsPerRoom == 140)
    #expect(Geometry.blockHeight == 63)
    #expect(Geometry.roomHeight == 189)
    // A room is 140 units wide but 189 tall. They are not the same unit.
    #expect(CoordinateSpace.xUnitsPerRoom != Geometry.roomHeight)
}

@Test func blockXRoundTripsThroughItsCentre() {
    for column in 0..<10 {
        let centre = CoordinateSpace.x(fromBlockX: column)
        #expect(CoordinateSpace.blockX(fromX: centre) == column)
    }
}

@Test func blockYRoundTripsThroughItsStandingHeight() {
    // y(fromBlockY:) yields 53, 116, 179 — the reference's (block + 1) * 63 - 10.
    #expect(CoordinateSpace.y(fromBlockY: 0) == 53)
    #expect(CoordinateSpace.y(fromBlockY: 1) == 116)
    #expect(CoordinateSpace.y(fromBlockY: 2) == 179)
    for row in 0..<3 {
        #expect(CoordinateSpace.blockY(fromY: CoordinateSpace.y(fromBlockY: row)) == row)
    }
}

@Test func floorDivisionMatchesJavaScriptForNegativeNumerators() {
    // Swift's / truncates toward zero; JavaScript's Math.floor rounds down. They
    // disagree whenever an actor walks off the left edge of a room.
    #expect(CoordinateSpace.floorDivide(-1, by: 14) == -1)   // Swift's / would say 0
    #expect(CoordinateSpace.floorDivide(-14, by: 14) == -1)
    #expect(CoordinateSpace.floorDivide(-15, by: 14) == -2)
    #expect(CoordinateSpace.floorDivide(13, by: 14) == 0)
    #expect(CoordinateSpace.floorDivide(14, by: 14) == 1)
}

@Test func blockXGoesNegativeOffTheLeftEdge() {
    // Foot at x = 0 is left of the first column's centre (7), so it is column -1 —
    // which is what drives the room transition in Fighter.updateBlockXY.
    #expect(CoordinateSpace.blockX(fromX: 0) == -1)
    #expect(CoordinateSpace.blockX(fromX: 6) == -1)
    #expect(CoordinateSpace.blockX(fromX: 7) == 0)
}

@Test func screenXScalesTheRoomOntoTheScreen() {
    // Utils.convertX: floor(x * 320 / 140)
    #expect(CoordinateSpace.screenX(fromX: 0) == 0)
    #expect(CoordinateSpace.screenX(fromX: 140) == 320)
    #expect(CoordinateSpace.screenX(fromX: 7) == 16)      // one column centre
    #expect(CoordinateSpace.screenX(fromX: 21) == 48)
    // The half-unit parity correction from fcheck bit 7 survives rounding.
    #expect(CoordinateSpace.screenX(fromX: 21.5) == 49)
}
