import Testing
@testable import PoPCore

// M1: the level data layer. Every expectation here was read out of the shipped
// data in reference/PrinceJS/assets/maps/, not invented.

@Test(arguments: GameData.levelNumbers)
func everyLevelDecodesAndSatisfiesItsInvariants(number: Int) throws {
    let level = try GameData.level(number)
    #expect(level.number == number)
    #expect(level.rooms.count == level.size.roomCount)
    #expect(!level.name.isEmpty)
}

@Test(arguments: GameData.levelNumbers)
func everyExistingRoomHasExactlyThirtyTiles(number: Int) throws {
    let level = try GameData.level(number)
    for room in level.rooms where room.exists {
        #expect(room.tiles.count == Geometry.tilesPerRoom)
    }
}

@Test func levelOneMatchesTheReference() throws {
    let level = try GameData.level(1)
    #expect(level.number == 1)
    #expect(level.name == "Cell")
    #expect(level.size.width == 9)
    #expect(level.size.height == 3)
    #expect(level.size.roomCount == 27)
    #expect(level.type == .dungeon)
    #expect(level.rooms.count == 27)
    #expect(level.guards.count == 2)
    #expect(level.events.count == 12)
}

@Test func levelOnePrinceSpawnMatchesTheReference() throws {
    let prince = try GameData.level(1).prince
    #expect(prince.location == 1)
    #expect(prince.offset == -7)
    #expect(prince.room == 1)
    #expect(prince.direction == 1)
    #expect(prince.turn == false)
    #expect(prince.shouldTurn == false)
}

@Test func levelOneFirstGuardMatchesTheReference() throws {
    let guardSpawn = try #require(try GameData.level(1).guards.first)
    #expect(guardSpawn.room == 21)
    #expect(guardSpawn.location == 7)
    #expect(guardSpawn.skill == 0)
    #expect(guardSpawn.colors == 2)
    #expect(guardSpawn.type == .guard)
    #expect(guardSpawn.direction == -1)
    #expect(guardSpawn.active == nil)
    #expect(guardSpawn.reverse == nil)
    #expect(guardSpawn.effectiveDirection == -1)
}

// MARK: - Event holes
//
// The single most dangerous thing in the level format. `LevelBuilder.js` assigns the
// events array straight through and `Level.js#fireEvent` addresses it by index,
// guarding holes with `if (!this.events[event]) return;`. Compacting this array
// renumbers every subsequent event and breaks the game silently.

@Test func nullEventSlotsArePreservedInPlace() throws {
    let level = try GameData.level(6)
    #expect(level.events.count == 12)

    let holes = level.events.indices.filter { level.events[$0] == nil }
    #expect(holes == [1, 3, 4, 5, 7, 8])
    #expect(level.events.compactMap { $0 }.count == 6)

    // Holes sit in the middle of the array, not at the end.
    #expect(level.event(at: 0) != nil)
    #expect(level.event(at: 11) != nil)
    #expect(level.event(at: 1) == nil)
}

@Test func levelEightHasExactlyOneEventHole() throws {
    let level = try GameData.level(8)
    #expect(level.events.count == 14)
    #expect(level.events.indices.filter { level.events[$0] == nil } == [5])
}

@Test(arguments: GameData.levelNumbers)
func eventLookupByNumberIsIndependentOfPosition(number: Int) throws {
    let level = try GameData.level(number)
    var seen = 0
    for slot in level.events {
        // Levels 6 and 8 legitimately contain holes.
        guard let event = slot else { continue }
        seen += 1
        #expect(level.event(number: event.number) == event)
    }
    #expect(seen == level.events.compactMap { $0 }.count)
}

// MARK: - Tile conventions

@Test func tileNumberIsRowMajorWithRowZeroAtTheTop() throws {
    // LevelBuilder.js#buildTile: `let tileNumber = y * 10 + x`
    let room = try #require(try GameData.level(1).rooms.first { $0.id == 1 })
    #expect(room.tile(x: 0, y: 0).kind == .space)
    #expect(room.tile(x: 3, y: 0).kind == .floor)
    #expect(room[0] == room.tile(x: 0, y: 0))
}

@Test func eventLocationsAreOneBased() throws {
    // Level.js:246 — `x = (location - 1) % 10`
    let level = try GameData.level(1)
    let event = try #require(level.events[0])
    #expect(event.location == 10)

    let room = try #require(level.rooms.first { $0.id == event.room })
    // location 10 -> tileNumber 9 -> x 9, y 0
    #expect(room.tile(eventLocation: event.location) == room.tile(x: 9, y: 0))
}

@Test func theOriginalLevelsUseEveryTileKindExceptTheModernAdditions() throws {
    var used = Set<TileKind>()
    for number in GameData.levelNumbers {
        for room in try GameData.level(number).rooms where room.exists {
            for tile in room.tiles { used.insert(tile.kind) }
        }
    }
    #expect(used.contains(.space))
    #expect(used.contains(.wall))
    #expect(used.contains(.latticeRight))     // 29 — the highest kind actually used
    #expect(!used.contains(.stuckButton))     // 5, an SDLPoP-era addition
    #expect(!used.contains(.torchWithDebris)) // 30
    #expect(!used.contains(.debrisOnly))      // 31
    #expect(!used.contains(.null))            // 32
}
