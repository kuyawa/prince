import Testing
@testable import PoPCore

// M0: proves the headless test loop works over PoPCore.
// These lock in the geometry contract from reference/PrinceJS/src/Boot.js.

@Test func tilesAreNotSquare() {
    // The defining quirk of the Prince of Persia playfield.
    #expect(Geometry.blockWidth == 32)
    #expect(Geometry.blockHeight == 63)
    #expect(Geometry.blockWidth != Geometry.blockHeight)
}

@Test func roomIsTenByThreeTiles() {
    #expect(Geometry.roomColumns == 10)
    #expect(Geometry.roomRows == 3)
    #expect(Geometry.tilesPerRoom == 30)
}

@Test func roomGeometryMatchesTheReference() {
    #expect(Geometry.roomWidth == 320)
    #expect(Geometry.roomHeight == 189)
    #expect(Geometry.roomHeight == Geometry.blockHeight * Geometry.roomRows)
}

@Test func roomSpansTheScreenWidthButNotItsHeight() {
    #expect(Geometry.roomWidth == Geometry.screenWidth)
    // The 11 px gap is ARCHITECTURE.md open question 4. If this ever fails,
    // someone has "tidied" the geometry and broken fidelity.
    #expect(Geometry.roomHeight < Geometry.screenHeight)
    #expect(Geometry.screenHeight - Geometry.roomHeight == 11)
}
