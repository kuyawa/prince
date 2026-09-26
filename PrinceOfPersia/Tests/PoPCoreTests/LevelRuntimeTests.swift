import Testing
@testable import PoPCore

// M3: the level grid, room links and tile lookup.
//
// Anchors below were generated from maps/level1.json by walking the grid the way
// LevelBuilder.js does, so they are reference-derived.

private func levelOne() throws -> LevelRuntime {
    try LevelRuntime(try GameData.level(1))
}

@Test func theRoomGridIsRebuiltInRowMajorOrder() throws {
    let level = try levelOne()
    #expect(level.layout.count == 3)
    #expect(level.layout.allSatisfy { $0.count == 9 })
    #expect(level.layout[0] == [22, 16, 23, 17, 21, 5, 1, -1, -1])
    #expect(level.layout[1] == [15, 12, 20, 7, 8, 6, 2, 3, 9])
    #expect(level.layout[2] == [10, 19, 4, 14, 11, -1, -1, -1, -1])
}

@Test func gapsInTheGridAreRecordedAsMinusOne() throws {
    let level = try levelOne()
    // Level 1 has 2 gaps on row 0 and 4 on row 2: 21 of its 27 slots are rooms.
    let gaps = level.layout.flatMap { $0 }.filter { $0 == -1 }.count
    #expect(gaps == 6)
    #expect(level.placements.count == 21)
}

@Test func roomLinksAreDerivedFromTheGrid() throws {
    let level = try levelOne()

    // Room 1 sits at grid (6, 0) in level 1.
    let room1 = try #require(level.placement(of: 1))
    #expect(room1.column == 6)
    #expect(room1.row == 0)
    // LevelBuilder.getRoomId returns -1 — both off the grid and for a gap. The
    // reference guards with `<= 0`, so -1 means "no room" just as 0 would.
    #expect(room1.links.up == -1)     // off the top of the grid
    #expect(room1.links.down == 2)
    #expect(room1.links.left == 5)
    #expect(room1.links.right == -1)  // a gap to the right

    let room22 = try #require(level.placement(of: 22))
    #expect(room22.links.down == 15)
    #expect(room22.links.right == 16)
    #expect(room22.links.up == -1)
    #expect(room22.links.left == -1)

    let room11 = try #require(level.placement(of: 11))
    #expect(room11.links.up == 8)
    #expect(room11.links.down == -1)
    #expect(room11.links.left == 14)
}

@Test(arguments: GameData.levelNumbers)
func everyLevelBuildsAGridConsistentWithItsData(number: Int) throws {
    let level = try LevelRuntime(try GameData.level(number))
    let placed = level.layout.flatMap { $0 }.filter { $0 > 0 }
    #expect(placed.count == level.placements.count)
    #expect(level.layout.count == level.data.size.height)
    #expect(level.layout.allSatisfy { $0.count == level.data.size.width })
}

@Test func tilesAreAddressedRowMajorWithRowZeroAtTheTop() throws {
    let level = try levelOne()
    // Level 1 room 1: [0,0,0,1,1,1,1,1,20,20] on row 0.
    #expect(level.tile(x: 0, y: 0, room: 1).kind == .space)
    #expect(level.tile(x: 3, y: 0, room: 1).kind == .floor)
    #expect(level.tile(x: 8, y: 0, room: 1).kind == .wall)
    #expect(level.tile(x: 0, y: 1, room: 1).kind == .torch)
}

@Test func offMapLookupsReturnTheReferenceDummyWall() throws {
    let level = try levelOne()
    // Level.js#getTileAt hands back its dummyWall for anything off the map, which is
    // why an actor walking into a gap meets stone rather than falling out of the world.
    #expect(level.tile(x: -1, y: 0, room: 1).kind == .wall)
    #expect(level.tile(x: 10, y: 0, room: 1).kind == .wall)
    #expect(level.tile(x: 0, y: -1, room: 1).kind == .wall)
    #expect(level.tile(x: 0, y: 3, room: 1).kind == .wall)
    #expect(level.tile(x: 0, y: 0, room: 999).kind == .wall)
    #expect(LevelRuntime.offMapTile.kind == .wall)
}

@Test func roomLinksAreVisibleThroughTheWorldQuery() throws {
    let level = try levelOne()
    #expect(level.roomLinks(1)?.down == 2)
    #expect(level.roomLinks(999) == nil)
}
