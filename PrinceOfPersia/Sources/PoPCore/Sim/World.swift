/// A level plus its mutable state, presented to the simulation as one world.
///
/// `LevelRuntime` is the decoded level and never changes. `LevelState` is everything that does —
/// gate positions, button presses, whether the exit opened. Together they satisfy `TileWorld`,
/// which is what the movement code and the VM ask for.
public struct World: Sendable {
    public let level: LevelRuntime
    public private(set) var state: LevelState

    public init(_ level: LevelRuntime) {
        self.level = level
        self.state = LevelState(level)
    }

    /// One tick of the interactive tiles. Call once per simulation tick, after the actor has
    /// been stepped.
    public mutating func update() {
        state.update()
    }

    @discardableResult
    public mutating func pressButton(at ref: TileRef) -> Bool {
        state.pressButton(at: ref)
    }

    /// Fire a level event by index. `Level.fireEvent`, exposed for tests and for the mechanisms
    /// that will call it directly (potion pickups, loose boards).
    public mutating func fire(_ event: Int, kind: TileKind, stuck: Bool = false) {
        state.fire(event, kind: kind, stuck: stuck)
    }

    public func gate(at ref: TileRef) -> Gate? { state.gate(at: ref) }
    public var isExitDoorOpen: Bool { state.isExitDoorOpen }
    public var gateCount: Int { state.gates.count }
    public var buttonCount: Int { state.buttons.count }
}

extension World: TileWorld {
    public func tile(x: Int, y: Int, room: Int) -> Tile {
        level.tile(x: x, y: y, room: room)
    }

    public func roomLinks(_ room: Int) -> RoomLinks? {
        level.roomLinks(room)
    }

    public func gateBlocks(x: Int, y: Int, room: Int) -> Bool {
        state.gateBlocks(x: x, y: y, room: room)
    }
}
