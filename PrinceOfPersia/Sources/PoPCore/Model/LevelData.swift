import Foundation

/// A level: a grid of rooms plus the entities that inhabit them.
///
/// Port source: `reference/PrinceJS/assets/maps/level*.json`, cross-checked against
/// `reference/PrinceJS/src/Level.js`, `LevelBuilder.js` and `Game.js`.
public struct LevelData: Sendable, Decodable {
    public let number: Int
    public let name: String
    public let size: RoomGridSize
    public let type: LevelType
    public let rooms: [RoomData]
    public let guards: [GuardSpawn]

    /// Events are **index-addressed and positionally significant**.
    ///
    /// `LevelBuilder.js` assigns the array straight through (`this.level.events = json.events`)
    /// and `Level.js#fireEvent` looks events up by index, guarding holes with
    /// `if (!this.events[event]) return;`. Seven of the fourteen shipped levels contain
    /// `null` entries. **Compacting this array would silently renumber every subsequent
    /// event and break the game.** The optionals are load-bearing.
    public let events: [EventTrigger?]

    public let prince: PrinceSpawn

    private enum CodingKeys: String, CodingKey {
        case number, name, size, type, guards, events, prince
        case rooms = "room"
    }

    /// The event with a given `number`, ignoring array position.
    public func event(number: Int) -> EventTrigger? {
        events.compactMap { $0 }.first { $0.number == number }
    }

    /// Index-addressed lookup, preserving holes. Equivalent to `events[index]`.
    public func event(at index: Int) -> EventTrigger? {
        guard events.indices.contains(index) else { return nil }
        return events[index]
    }

    /// Structural invariants the reference data always satisfies.
    ///
    /// Checked on load so that a malformed or hand-edited level fails loudly at the
    /// door rather than as a mysterious collision bug three milestones later.
    public func validate() throws {
        guard rooms.count == size.roomCount else {
            throw LevelValidationError.roomCountMismatch(
                level: number, expected: size.roomCount, actual: rooms.count
            )
        }
        for room in rooms where room.exists {
            guard room.tiles.count == Geometry.tilesPerRoom else {
                throw LevelValidationError.wrongTileCount(
                    level: number, room: room.id, actual: room.tiles.count
                )
            }
        }
    }
}

public enum LevelValidationError: Error, CustomStringConvertible, Equatable {
    case roomCountMismatch(level: Int, expected: Int, actual: Int)
    case wrongTileCount(level: Int, room: Int, actual: Int)

    public var description: String {
        switch self {
        case let .roomCountMismatch(level, expected, actual):
            return "Level \(level): expected \(expected) rooms, found \(actual)"
        case let .wrongTileCount(level, room, actual):
            return "Level \(level) room \(room): expected \(Geometry.tilesPerRoom) tiles, found \(actual)"
        }
    }
}

/// The room grid the level occupies, measured in rooms.
public struct RoomGridSize: Sendable, Decodable, Equatable {
    public let width: Int
    public let height: Int

    public var roomCount: Int { width * height }
}

public enum LevelType: Int, Sendable, Codable, Equatable {
    case dungeon = 0
    case palace = 1
}

/// One room: 30 tiles, row-major.
public struct RoomData: Sendable, Decodable, Equatable {
    /// The room's number in the level's room graph, or `-1` for a gap.
    public let id: Int

    /// Empty for the `id == -1` holes, which carry no `tile` key at all — 200 of the
    /// 476 room slots across the fourteen levels are gaps.
    public let tiles: [Tile]

    private enum CodingKeys: String, CodingKey {
        case id
        case tiles = "tile"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.tiles = try container.decodeIfPresent([Tile].self, forKey: .tiles) ?? []
    }

    /// `false` for the `id == -1` holes that pad the level grid.
    public var exists: Bool { id != -1 }

    /// 0-based row-major access. `tileNumber = y * 10 + x`, with **y = 0 at the top
    /// of the room** — confirmed by `LevelBuilder.js#buildTile`
    /// (`let tileNumber = y * 10 + x`) and `Level.js#addTile`, which places row 0 at
    /// the smallest screen offset.
    public subscript(tileNumber: Int) -> Tile {
        tiles[tileNumber]
    }

    public func tile(x: Int, y: Int) -> Tile {
        tiles[y * Geometry.roomColumns + x]
    }

    /// Resolves an **event** `location` to its tile.
    ///
    /// `Level.js:246` — `x = (location - 1) % 10`, `y = floor((location - 1) / 10)`.
    /// Event locations are 1-based, 1...30.
    ///
    /// Note this differs from the convention used for *actor* spawn locations, which
    /// `Fighter` computes as `location % 10` / `location / 10`. See
    /// `SpawnLocation` and ARCHITECTURE.md open question 8.
    public func tile(eventLocation: Int) -> Tile {
        tiles[eventLocation - 1]
    }
}

/// One 32 x 63 tile.
public struct Tile: Sendable, Decodable, Equatable {
    public let kind: TileKind

    /// The variant byte. Values 0...18 and 20 appear in the shipped levels; 19 does
    /// not. Kept as a raw `Int` because the valid set depends on `kind`.
    public let modifier: Int

    private enum CodingKeys: String, CodingKey {
        case kind = "element"
        case modifier
    }
}

/// A guard placed in the level.
///
/// Optional fields mirror the union of keys across the shipped levels plus the ones
/// `Game.js` reads (`bias`, `sneak`).
public struct GuardSpawn: Sendable, Decodable, Equatable {
    public let room: Int
    public let location: Int
    public let skill: Int
    public let colors: Int
    public let type: GuardType
    public let direction: Int

    public let active: Bool?
    public let visible: Bool?

    /// **A number, not a flag.** The shipped levels store `-1`; `Game.js` computes
    /// `data.direction * (data.reverse || 1)`, so `-1` reverses the guard. Absent
    /// means unchanged. Modelling this as `Bool` would decode cleanly and silently
    /// drop every reversal.
    public let reverse: Int?

    public let bias: Int?
    public let sneak: Bool?

    /// `Game.js`: `data.direction * (data.reverse || 1)`.
    public var effectiveDirection: Int { direction * (reverse ?? 1) }
}

public enum GuardType: String, Sendable, Decodable, Equatable, CaseIterable {
    // `guard` is a Swift keyword; the raw value is still "guard".
    case `guard`
    case skeleton
    case shadow
    case fatguard
    case jaffar
}

/// A level event: the thing a button, potion or loose board triggers.
public struct EventTrigger: Sendable, Decodable, Equatable {
    public let number: Int
    public let room: Int
    /// 1-based, 1...30. See `RoomData.tile(eventLocation:)`.
    public let location: Int
    /// The next event in the chain, or `0` for none.
    public let next: Int
    public let state: Int?
}

/// Where the Prince starts.
public struct PrinceSpawn: Sendable, Decodable, Equatable {
    /// 1-based, 1...30. See `RoomData.tile(eventLocation:)` and ARCHITECTURE.md
    /// open question 8 — actor locations do **not** use the event convention.
    public let location: Int
    public let room: Int
    public let direction: Int

    /// Present on only levels 1, 7 and 13.
    public let offset: Int?

    /// Present on only levels 1, 7 and 13.
    public let turn: Bool?
    public let cameraRoom: Int?
    public let bias: Int?

    /// Numeric multiplier, as for `GuardSpawn.reverse`. Absent from the shipped
    /// levels but read by `Game.js`.
    public let reverse: Int?

    public let sword: Bool?
    public let danger: Bool?
    public let specialEvents: Bool?

    /// `Game.js`: `let turn = json.prince.turn !== false;` — absent means true.
    public var shouldTurn: Bool { turn ?? true }

    /// `Game.js`:
    /// ```js
    /// let direction = json.prince.direction * (json.prince.reverse || 1);
    /// if (turn) { direction = -direction; }
    /// ```
    public var effectiveDirection: Int {
        let base = direction * (reverse ?? 1)
        return shouldTurn ? -base : base
    }
}
