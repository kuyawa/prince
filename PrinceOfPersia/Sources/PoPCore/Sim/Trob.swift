/// Something a button or an event can act on.
///
/// Port source: the `raise`/`drop`/ `update` triple that `Gate`, `ExitDoor`, `Spikes` and
/// `Loose` each implement. `Level.fireEvent` dispatches on exactly that shape:
///
/// ```js
/// if (type === TILE_RAISE_BUTTON) {
///   if (tile.raise) { tile.raise(stuck); }
/// } else if (tile.drop) {
///   tile.drop(stuck);
/// }
/// ```
///
/// So a raise button calls `raise` and a drop button calls `drop`, whatever the tile is.
public enum Trob: Sendable, Equatable {
    case gate(Gate)
    case exitDoor(ExitDoor)
    case looseBoard(LooseBoard)

    public mutating func raise(stuck: Bool) {
        switch self {
        case var .gate(value): value.raise(stuck: stuck); self = .gate(value)
        case var .exitDoor(value): value.raise(); self = .exitDoor(value)
        case var .looseBoard(value): value.shake(fall: true); self = .looseBoard(value)
        }
    }

    public mutating func drop() {
        switch self {
        case var .gate(value): value.drop(); self = .gate(value)
        case var .exitDoor(value): value.drop(); self = .exitDoor(value)
        case .looseBoard: break
        }
    }

    /// Advances the tile and reports any sound it made this tick.
    public mutating func update() -> SoundEffect? {
        switch self {
        case var .gate(value):
            let sound = value.update()
            self = .gate(value)
            return sound
        case var .exitDoor(value):
            let sound = value.update()
            self = .exitDoor(value)
            return sound
        case var .looseBoard(value):
            let sound = value.update()
            self = .looseBoard(value)
            return sound
        }
    }

    public var gate: Gate? {
        if case let .gate(value) = self { return value }
        return nil
    }

    public var exitDoor: ExitDoor? {
        if case let .exitDoor(value) = self { return value }
        return nil
    }

    public var looseBoard: LooseBoard? {
        if case let .looseBoard(value) = self { return value }
        return nil
    }
}

/// `PrinceJS.Tile.ExitDoor`.
///
/// The door is two pixels of state and a sliding graphic. Following `Gate`, the opening height
/// comes from the level type: `8 + type`, so 8 pixels in a dungeon and 9 in a palace.
///
/// **The port tracks `visibleHeight` directly rather than reproducing the reference's
/// bookkeeping.** The reference terminates its raise with `door.height === this.heightOpen`, which
/// relies on Phaser's `crop()` rewriting the sprite's `height` from the crop rectangle; the
/// intent — slide the door up until `heightOpen` pixels remain, then call it open — is
/// unambiguous and is what is modelled here.
public struct ExitDoor: Sendable, Equatable {
    /// `ExitDoor.STATE_*`. Note the order: open is 0, closed is 3.
    public enum Phase: Int, Sendable {
        case open = 0
        case raising = 1
        case dropping = 2
        case closed = 3
    }

    public var phase: Phase
    public var visibleHeight: Int

    /// `tileChildFront.visible` — set by `mask()` when the Prince starts climbing the stairs.
    public var isMasked: Bool = false

    /// How much of the door remains showing when it is fully open.
    public let openHeight: Int

    /// The door graphic's full height — 51 px for both dungeon and palace.
    public let closedHeight: Int

    /// A dropping door moves fifteen pixels a tick, against one when raising.
    public static let dropStep = 15

    public init(modifier: Int, isPalace: Bool, startsOpen: Bool) {
        openHeight = 8 + (isPalace ? 1 : 0)
        closedHeight = 51
        phase = startsOpen ? .open : .closed
        visibleHeight = startsOpen ? openHeight : closedHeight
    }

    public var isOpen: Bool { phase == .open }

    /// How many pixels are cut from the top of the door graphic.
    public var clipTop: Int { closedHeight - visibleHeight }

    /// `ExitDoor.mask`.
    public mutating func mask() { isMasked = true }

    public mutating func raise() {
        if phase == .closed { phase = .raising }
    }

    public mutating func drop() {
        if phase != .closed { phase = .dropping }
    }

    @discardableResult
    public mutating func update() -> SoundEffect? {
        switch phase {
        case .open, .closed:
            return nil

        case .raising:
            if visibleHeight <= openHeight {
                visibleHeight = openHeight
                phase = .open
            } else {
                visibleHeight -= 1
            }
            return nil

        case .dropping:
            if visibleHeight >= closedHeight {
                visibleHeight = closedHeight
                phase = .closed
            } else {
                visibleHeight = min(closedHeight, visibleHeight + Self.dropStep)
            }
            return nil
        }
    }
}

/// `PrinceJS.Tile.Loose` — the collapsing floor boards.
///
/// A board that is stepped on shakes for eight frames and then gives way; if it was only nudged
/// without being stood on, it settles back at frame 3 instead. That distinction is the whole
/// reason `shake(fall:)` takes a flag.
public struct LooseBoard: Sendable, Equatable {
    public enum Phase: Int, Sendable {
        case inactive = 0
        case shaking = 1
        case falling = 2
    }

    public var phase: Phase
    public var step: Int
    /// Whether this shake will actually collapse the board.
    public var willFall: Bool

    /// `generateFrameNames("_loose_", 1, 8)` — eight shake frames.
    public static let shakeFrames = 8
    /// The frame at which a board that is not going to fall settles back.
    public static let settleFrame = 3
    /// The falling board accelerates: `FALL_VELOCITY * step`.
    public static let fallVelocity = 3

    public init() {
        phase = .inactive
        step = 0
        willFall = false
    }

    /// `Loose.shake(fall)`.
    public mutating func shake(fall: Bool) {
        if phase == .inactive {
            phase = .shaking
            step = 0
        }
        willFall = fall
    }

    /// `Loose.fallStarted` — the board is at the last shake frame and about to drop.
    public var fallStarted: Bool {
        phase == .shaking && step == Self.shakeFrames
    }

    /// `Loose.update`. Returns the sound it made.
    ///
    /// The reference plays a shake on frames 0, 3 and 7, choosing among **three** variants with
    /// `Utils.random(3)` — a non-deterministic call in the port source. All three are the same
    /// shake with different trims, so this always plays the first rather than threading a
    /// generator through a tile update for a cosmetic choice.
    @discardableResult
    public mutating func update() -> SoundEffect? {
        switch phase {
        case .inactive:
            return nil

        case .shaking:
            if step == Self.shakeFrames {
                // `Loose.fallStarted` -> `sweep`, which plays `Sounds[0]` — a shake, not a landing.
                phase = .falling
                step = 0
                return .looseFloorShakes1
            }
            if step == Self.settleFrame, !willFall {
                // Never stood on hard enough to break: it settles.
                phase = .inactive
                return nil
            }
            step += 1
            if step == 0 || step == Self.settleFrame || step == Self.shakeFrames - 1 {
                return .looseFloorShakes1
            }
            return nil

        case .falling:
            step += 1
            // The reference accumulates displacement against a target height. The board is gone
            // once it has fallen clear of its cell, which is one tile's worth of travel.
            if Self.fallVelocity * step * (step + 1) / 2 > Geometry.blockHeight {
                phase = .inactive
            }
            return nil
        }
    }
}
