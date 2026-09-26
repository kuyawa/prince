/// Something an opcode asks the world to do.
///
/// The interpreter never mutates the world directly. It emits these, and the caller
/// decides what they mean — which is what keeps the VM headlessly testable and what
/// will let M7 wire mechanisms in without touching a single opcode.
public enum ActorEffect: Sendable, Equatable {
    /// `TAP` (242). `Actor`'s base implementation is empty; `Kid` and `Enemy` override
    /// it to play footsteps or a wall bump, keyed on `p1`:
    /// 1 = footsteps, 2 = bump into wall soft, 3 = bump into wall hard.
    case tap(Int)

    /// `DIE` (246). The actor is now dead.
    case died

    /// `NEXTLEVEL` (241). The caller drives the level transition and its music.
    case advanceToNextLevel

    /// The Prince reached the open exit and is climbing the stairs out.
    case leavingLevel

    /// `ExitDoor.mask` — the door's front graphic is revealed as the Prince climbs it.
    case maskedExitDoor(TileRef)

    /// `UP` (253) found a room above and moved into it.
    case enteredRoom(Int)

    /// `DOWN` (252) dropped into the room below. The reference calls
    /// `changeRoomDown()`, which lives on `Kid`; M5 implements it.
    case exitedRoomDown

    /// `JARD` (244) — shake the floor on this row.
    case shakeFloor(room: Int, row: Int)

    /// A loose board was disturbed, by a door being climbed past or a hang. `Loose.shake(true)`.
    case shookLooseBoard(TileRef)

    /// `JARU` (245) — shake the row above, at the actor's column and the one to its right.
    ///
    /// The reference also inspects both tiles and shakes them if they are loose boards;
    /// that lookup needs the tile map, so M7 completes it. The intent is captured here
    /// so the opcode itself does not change later.
    case shakeFloorAbove(room: Int, column: Int, row: Int)
}

/// The little the VM needs to ask of the world.
///
/// Deliberately minimal for M2. `CMD_UP` is the only opcode that both mutates the
/// actor *and* consults the level, and the reference guards that lookup with
/// `if (this.level.rooms[this.room])` — so a `nil` world is a faithful stand-in and
/// makes the opcode a no-op exactly as it is for an actor standing in a gap.
/// A value type, not a class: the world is immutable during a tick, so the simulation
/// can hold it cheaply and stay `Sendable`.
public protocol ActorWorldQuery: Sendable {
    /// `level.rooms[room]?.links`, or `nil` when the room does not exist.
    func roomLinks(_ room: Int) -> RoomLinks?
}

public struct RoomLinks: Sendable, Equatable {
    public var up: Int
    public var down: Int
    public var left: Int
    public var right: Int

    public init(up: Int, down: Int, left: Int, right: Int) {
        self.up = up
        self.down = down
        self.left = left
        self.right = right
    }
}
