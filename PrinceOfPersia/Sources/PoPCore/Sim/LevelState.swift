import Foundation

/// A tile's identity: which room, and which of its thirty cells.
public struct TileRef: Hashable, Sendable {
    public let room: Int
    /// `y * 10 + x`, row 0 at the top.
    public let index: Int

    public init(room: Int, index: Int) {
        self.room = room
        self.index = index
    }

    public init(room: Int, x: Int, y: Int) {
        self.init(room: room, index: y * Geometry.roomColumns + x)
    }

    public var x: Int { index % Geometry.roomColumns }
    public var y: Int { index / Geometry.roomColumns }
}

/// The mutable half of a level: the state of every interactive tile.
///
/// `LevelRuntime` is the immutable decoded level; this is what changes as the game runs. Split
/// apart so the level data stays cheap to share, and so a test can reset the world without
/// reloading anything.
///
/// Port source: `reference/PrinceJS/src/tiles/Gate.js`, `Button.js`, and `Level.js#fireEvent`.
public struct LevelState: Sendable {
    /// Everything a button or event can act on: gates, exit doors, loose boards.
    /// Only positions that actually hold one appear here.
    public private(set) var trobs: [TileRef: Trob] = [:]

    /// Buttons, keyed by position. These are triggers rather than targets, so they are separate.
    public private(set) var buttons: [TileRef: Button] = [:]

    /// Gates only, for convenience.
    public var gates: [TileRef: Gate] {
        trobs.compactMapValues(\.gate)
    }

    public func trob(at ref: TileRef) -> Trob? { trobs[ref] }

    /// Tiles that have changed since the level loaded.
    ///
    /// `Level.floorStartFall` replaces a collapsing board with `TILE_SPACE` outright:
    ///
    /// ```js
    /// floorStartFall: function (tile) {
    ///   let space = new PrinceJS.Tile.Base(this.game, TILE_SPACE, 0, tile.type);
    ///   this.addTile(tile.roomX, tile.roomY, tile.room, space);
    ///   ...
    /// }
    /// ```
    ///
    /// The hole *is* the mechanism — nothing tells the Prince to fall. On the next tick
    /// `checkFloor` finds space under him and starts him falling, exactly as it would over any
    /// other gap.
    public private(set) var overrides: [TileRef: Tile] = [:]

    /// `Level.exitDoorOpen` — set when a raise-button targets an exit door.
    public private(set) var isExitDoorOpen = false

    public func override(at ref: TileRef) -> Tile? { overrides[ref] }

    /// `Level.floorStartFall`.
    public mutating func openHole(at ref: TileRef) {
        overrides[ref] = Tile(kind: .space, modifier: 0)
    }

    /// `ExitDoor.mask`.
    public mutating func maskExitDoor(at ref: TileRef) {
        guard var door = trobs[ref]?.exitDoor else { return }
        door.mask()
        trobs[ref] = .exitDoor(door)
    }

    /// `Loose.shake(true)` — a board was disturbed.
    public mutating func shakeLooseBoard(at ref: TileRef) {
        guard var board = trobs[ref]?.looseBoard else { return }
        board.shake(fall: true)
        trobs[ref] = .looseBoard(board)
    }

    /// The height a gate must clear before an actor fits underneath.
    ///
    /// The reference asks the live Phaser sprite (`this.height`), which varies by a pixel or two
    /// between frames — 38 to 42 across the Prince's locomotion frames. The DOS original used
    /// fixed-size cels, so a constant is arguably *closer* to the original than the varying
    /// value. The only observable difference is whether a gate becomes passable a tick or two
    /// earlier during its 47-tick raise.
    public static let actorPassageHeight = 40

    private let level: LevelRuntime

    public init(_ level: LevelRuntime) {
        self.level = level
        let isPalace = level.data.type == .palace

        for room in level.roomNumbers {
            for index in 0..<Geometry.tilesPerRoom {
                let tile = level.tile(atIndex: index, room: room)
                let ref = TileRef(room: room, index: index)
                switch tile.kind {
                case .gate:
                    trobs[ref] = .gate(Gate(modifier: tile.modifier))

                case .exitRight:
                    // LevelBuilder: `open = id === startId && Math.abs(tileNumber - startLocation) <= 1`.
                    // Note it compares a 0-based `tileNumber` against the raw `prince.location`,
                    // mixing the two conventions — reproduced as written.
                    let startsOpen = room == level.data.prince.room
                        && abs(index - level.data.prince.location) <= 1
                    trobs[ref] = .exitDoor(ExitDoor(
                        modifier: tile.modifier, isPalace: isPalace, startsOpen: startsOpen
                    ))

                case .looseBoard:
                    trobs[ref] = .looseBoard(LooseBoard())

                case .raiseButton, .dropButton, .stuckButton:
                    var button = Button(kind: tile.kind)
                    // A button's modifier is the EVENT INDEX it fires — not a label.
                    button.eventNumber = tile.modifier
                    buttons[ref] = button

                default:
                    break
                }
            }
        }
    }

    // MARK: - Ticking

    /// One tick of the interactive tiles. Call once per simulation tick.
    ///
    /// The reference drives this from `Game.updateWorld` on an 80 ms timer; a simulation tick is
    /// 1/12 s ≈ 83 ms, near enough that one call per tick is the faithful reading.
    public mutating func update() {
        var pending: [(event: Int, kind: TileKind, stuck: Bool)] = []

        for (ref, var button) in buttons {
            if let push = button.update() {
                pending.append((button.eventNumber, push.kind, push.stuck))
            }
            buttons[ref] = button
        }
        // A board that just gave way takes the floor out with it, for good.
        for (ref, var trob) in trobs {
            guard var board = trob.looseBoard else {
                trob.update()
                trobs[ref] = trob
                continue
            }
            let wasFalling = board.phase == .falling
            board.update()
            if board.phase == .falling, !wasFalling {
                // `onStartFalling` -> `Level.floorStartFall`.
                overrides[ref] = Tile(kind: .space, modifier: 0)
            }
            trobs[ref] = .looseBoard(board)
        }

        for event in pending {
            fire(event.event, kind: event.kind, stuck: event.stuck)
        }
    }

    /// The actor stepped onto a button. Returns `true` if a button was actually pressed.
    @discardableResult
    public mutating func pressButton(at ref: TileRef) -> Bool {
        guard var button = buttons[ref] else { return false }
        button.push()
        buttons[ref] = button
        if button.isStuckFired { return true }
        fire(button.eventNumber, kind: button.kind, stuck: false)
        return true
    }

    /// The gate at a position, if there is one.
    public func gate(at ref: TileRef) -> Gate? { trobs[ref]?.gate }

    /// Whether a gate blocks passage, resolving the tile the same way `Level.getTileAt` does.
    public func gateBlocks(x: Int, y: Int, room: Int) -> Bool {
        guard let ref = level.resolve(x: x, y: y, room: room),
              let gate = trobs[ref]?.gate
        else { return true }
        return !gate.canCross(height: Self.actorPassageHeight)
    }

    /// Whether an exit door at a position is open, for `Kid.jump`'s climb-the-stairs branch.
    public func exitDoorIsOpen(x: Int, y: Int, room: Int) -> Bool {
        guard let ref = level.resolve(x: x, y: y, room: room),
              let door = trobs[ref]?.exitDoor
        else { return false }
        return door.isOpen
    }

    // MARK: - Events

    /// `Level.fireEvent`.
    ///
    /// **The event number is an array index, not the `number` field.** A button's `modifier` is
    /// looked up directly as `events[modifier]`; the `number` on each entry is a separate label.
    /// The level data confirms it: level 1's three buttons in room 5 carry modifiers 8, 9 and 11,
    /// and events at those indices all sit in room 5 — which is where the gates they raise are.
    ///
    /// Holes are tolerated: M1 established that the events array has `null` entries at
    /// load-bearing positions, and the reference guards with `if (!this.events[event]) return`.
    public mutating func fire(_ event: Int, kind: TileKind, stuck: Bool) {
        guard let trigger = level.data.event(at: event) else { return }

        let x = (trigger.location - 1) % Geometry.roomColumns
        let y = (trigger.location - 1) / Geometry.roomColumns

        // A door is two tiles wide; the left half redirects to its right half.
        let targetX = level.tile(x: x, y: y, room: trigger.room).kind == .exitLeft ? x + 1 : x
        let target = level.tile(x: targetX, y: y, room: trigger.room)
        let ref = TileRef(room: trigger.room, x: targetX, y: y)

        // A raise button calls `raise` and a drop button calls `drop` — on whatever the tile is.
        if var trob = trobs[ref] {
            if kind == .raiseButton {
                trob.raise(stuck: stuck)
                if target.kind == .exitLeft || target.kind == .exitRight {
                    isExitDoorOpen = true
                }
            } else {
                trob.drop()
            }
            trobs[ref] = trob
        }

        // Chaining. The reference drops `stuck` in the recursive call.
        if trigger.next != 0 {
            fire(event + 1, kind: kind, stuck: false)
        }
    }
}

/// `PrinceJS.Tile.Gate`.
///
/// `position` is the reference's `posY`: `0` when shut, `-47` when fully raised. `modifier`
/// seeds both position and phase, which is how a level can start with a gate already open —
/// level 1's room 5 has one gate of each.
public struct Gate: Sendable, Equatable {
    /// `Gate.STATE_*`. The raw values match the reference, and `modifier` selects one directly:
    /// 0 is closed, 1 is open.
    public enum Phase: Int, Sendable {
        case closed = 0
        case open = 1
        case raising = 2
        case dropping = 3
        case fastDropping = 4
        case waiting = 5
    }

    public var position: Int
    public var phase: Phase
    public var step: Int
    public var closedFast: Bool

    /// How far a fully raised gate travels.
    public static let travel = 47
    /// How far one modifier step pre-raises it.
    public static let modifierStep = 46
    /// Ticks a raised gate waits at the top before closing.
    public static let waitTicks = 50
    /// A slowly closing gate drops one pixel every fourth tick.
    public static let dropInterval = 4
    /// A fast-dropping gate falls this many pixels per tick.
    public static let fastDropStep = 10

    public init(modifier: Int) {
        position = -modifier * Self.modifierStep
        phase = Phase(rawValue: modifier) ?? .closed
        step = 0
        closedFast = false
    }

    /// `Gate.canCross(height)`.
    public func canCross(height: Int) -> Bool {
        abs(position) > height
    }

    public mutating func raise(stuck: Bool) {
        // A gate that slammed shut cannot be re-raised by a button that is merely still held.
        if closedFast && stuck { return }
        step = 0
        if phase != .waiting && phase != .fastDropping && phase != .raising {
            phase = .raising
            closedFast = false
        }
    }

    public mutating func drop() {
        if phase != .fastDropping {
            phase = .fastDropping
            closedFast = true
        }
    }

    /// `Gate.update`.
    public mutating func update() {
        switch phase {
        case .closed, .open:
            break

        case .raising:
            // Reaches the top, then holds there. The reference tests `posY === -47` exactly.
            if position == -Self.travel {
                phase = .waiting
                step = 0
            } else {
                position -= 1
            }

        case .waiting:
            step += 1
            if step == Self.waitTicks {
                phase = .dropping
                step = 0
            }

        case .dropping:
            if step == 0 {
                position += 1
                if position >= 0 {
                    position = 0
                    phase = .closed
                }
            }
            step = (step + 1) % Self.dropInterval

        case .fastDropping:
            position += Self.fastDropStep
            if position >= 0 {
                position = 0
                phase = .closed
            }
        }
    }
}

/// `PrinceJS.Tile.Button`.
public struct Button: Sendable, Equatable {
    public struct Push: Sendable, Equatable {
        public let kind: TileKind
        public let stuck: Bool
    }

    public var kind: TileKind
    public var isActive = false
    public var step = 0

    /// The button's `modifier` — the **event index** it fires.
    public var eventNumber = 0

    /// Set once a stuck button has fired; it never fires again.
    public var isStuckFired = false

    /// `RAISE_BUTTON` releases after 3 ticks, `DROP_BUTTON` after 5.
    public var stepMax: Int { kind == .raiseButton ? 3 : 5 }

    public init(kind: TileKind) {
        self.kind = kind
    }

    /// `Button.push` — the actor stepped on it.
    public mutating func push() {
        if !isActive {
            isActive = true
        }
        step = 0
    }

    /// `Button.update`. Returns a push to fire, if this tick produced one.
    public mutating func update() -> Push? {
        var push: Push?

        if isStuckFired {
            // A stuck button stays down; it fires exactly once, on its first update.
            return nil
        }

        // A raise button re-fires with "stuck" while it is still held down, which is how a gate
        // that slammed shut stays shut.
        if isActive, kind == .raiseButton, step == 0 {
            push = Push(kind: kind, stuck: true)
        }

        if isActive {
            if step == stepMax { isActive = false }
            step += 1
        } else if kind == .stuckButton, !isStuckFired {
            // `debris` buttons fire once and then remain pressed for good.
            isStuckFired = true
            isActive = true
            push = Push(kind: kind, stuck: true)
        }

        return push
    }
}
