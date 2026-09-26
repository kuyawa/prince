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
    /// Gates, keyed by position. Only rooms containing one appear here.
    public private(set) var gates: [TileRef: Gate] = [:]

    /// Buttons, keyed by position.
    public private(set) var buttons: [TileRef: Button] = [:]

    /// `Level.exitDoorOpen` — set when a raise-button targets an exit door.
    public private(set) var isExitDoorOpen = false

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
        for room in level.roomNumbers {
            for index in 0..<Geometry.tilesPerRoom {
                let tile = level.tile(atIndex: index, room: room)
                let ref = TileRef(room: room, index: index)
                switch tile.kind {
                case .gate:
                    gates[ref] = Gate(modifier: tile.modifier)
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
        for (ref, var gate) in gates {
            gate.update()
            gates[ref] = gate
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
    public func gate(at ref: TileRef) -> Gate? { gates[ref] }

    /// Whether a gate blocks passage, resolving the tile the same way `Level.getTileAt` does.
    public func gateBlocks(x: Int, y: Int, room: Int) -> Bool {
        guard let ref = level.resolve(x: x, y: y, room: room),
              let gate = gates[ref]
        else { return true }
        return !gate.canCross(height: Self.actorPassageHeight)
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

        if kind == .raiseButton {
            if var gate = gates[ref] {
                gate.raise(stuck: stuck)
                gates[ref] = gate
            }
            if target.kind == .exitLeft || target.kind == .exitRight {
                isExitDoorOpen = true
            }
        } else if var gate = gates[ref] {
            gate.drop()
            gates[ref] = gate
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
