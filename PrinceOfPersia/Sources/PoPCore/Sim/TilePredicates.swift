/// Tile classification.
///
/// Port source: `reference/PrinceJS/src/tiles/Base.js`. Every predicate there is a
/// negated or positive membership test against a fixed set of elements, so they are
/// reproduced literally rather than tidied into something more symmetric — the sets
/// are not complements of one another and the exceptions are deliberate.
public extension TileKind {
    /// Whether an actor can stand on this tile.
    ///
    /// Note this is `element !== WALL && element !== SPACE && ...` — a **negated**
    /// membership test, so it is true for most tiles, including ones that are not
    /// floors at all (potions, exits, torches). That is the reference's behaviour.
    var isWalkable: Bool {
        switch self {
        case .wall, .space, .topBigPillar, .tapestryTop,
             .latticeSupport, .smallLattice, .latticeLeft, .latticeRight:
            false
        default:
            true
        }
    }

    /// Empty air an actor can occupy.
    var isSpace: Bool {
        switch self {
        case .space, .topBigPillar, .tapestryTop,
             .latticeSupport, .smallLattice, .latticeLeft, .latticeRight:
            true
        default:
            false
        }
    }

    /// Blocks movement horizontally.
    var isBarrier: Bool {
        switch self {
        case .wall, .gate, .mirror, .tapestry, .tapestryTop: true
        default: false
        }
    }

    /// Blocks a *falling* actor — barriers except the decorative hangings.
    var isFreeFallBarrier: Bool {
        isBarrier && self != .tapestry && self != .tapestryTop
    }

    var isBarrierWalk: Bool { isBarrier || isDangerousWalkable }

    /// Which side a barrier pushes a falling actor toward.
    var isBarrierLeft: Bool { self == .wall || self == .mirror }
    var isBarrierRight: Bool { self == .gate || self == .tapestry || self == .tapestryTop }

    /// Walkable but hazardous.
    var isDangerousWalkable: Bool { self == .looseBoard || self == .chopper }

    var isSafeWalkable: Bool { isWalkable && !isDangerousWalkable }

    var isExitDoor: Bool { self == .exitLeft || self == .exitRight }

    /// Usable as jump clearance. Tapestry tops are space but not jump space.
    var isJumpSpace: Bool { isSpace && self != .tapestryTop }
}
