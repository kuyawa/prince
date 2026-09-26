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

    /// `Loose.shake(true)` — disturb a board without standing on it.
    public mutating func shakeLooseBoard(at ref: TileRef) {
        state.shakeLooseBoard(at: ref)
    }

    public func gate(at ref: TileRef) -> Gate? { state.gate(at: ref) }
    public func looseBoard(at ref: TileRef) -> LooseBoard? { state.trob(at: ref)?.looseBoard }
    public func exitDoor(at ref: TileRef) -> ExitDoor? { state.trob(at: ref)?.exitDoor }

    /// Apply the effects a behaviour produced against the world.
    public mutating func apply(_ effects: [ActorEffect]) {
        for effect in effects {
            switch effect {
            case let .shookLooseBoard(ref): state.shakeLooseBoard(at: ref)
            case let .maskedExitDoor(ref): state.maskExitDoor(at: ref)
            default: break
            }
        }
    }
    public var isExitDoorOpen: Bool { state.isExitDoorOpen }
    public var gateCount: Int { state.gates.count }
    public var buttonCount: Int { state.buttons.count }
}

extension World: TileWorld {
    public func tile(x: Int, y: Int, room: Int) -> Tile {
        // A board that has fallen is a hole in the floor from now on.
        if let ref = level.resolve(x: x, y: y, room: room),
           let replacement = state.override(at: ref) {
            return replacement
        }
        return level.tile(x: x, y: y, room: room)
    }

    public func resolve(x: Int, y: Int, room: Int) -> TileRef? {
        level.resolve(x: x, y: y, room: room)
    }

    public func roomLinks(_ room: Int) -> RoomLinks? {
        level.roomLinks(room)
    }

    public func gateBlocks(x: Int, y: Int, room: Int) -> Bool {
        state.gateBlocks(x: x, y: y, room: room)
    }

    public func trob(x: Int, y: Int, room: Int) -> Trob? {
        guard let ref = level.resolve(x: x, y: y, room: room) else { return nil }
        return state.trob(at: ref)
    }
}
