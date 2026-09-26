/// The sixteen opcodes the engine actually registers.
///
/// Port source: the `registerCommand` calls in `reference/PrinceJS/src/Actor.js`,
/// `Fighter.js` and `Kid.js`.
///
/// `Actor`'s constructor first registers **all 256** byte values to `CMD_NOOP`, then
/// overrides the few it implements. Subclasses add theirs. Everything unnamed is
/// therefore a silent no-op rather than an error.
public enum Opcode: UInt8, Sendable, CaseIterable, Equatable {
    case frame = 0x00
    case nextLevel = 0xF1
    case tap = 0xF2
    case effect = 0xF3
    case jard = 0xF4
    case jaru = 0xF5
    case die = 0xF6
    case ifWithLess = 0xF7
    case setFall = 0xF8
    case act = 0xF9
    case changeY = 0xFA
    case changeX = 0xFB
    case down = 0xFC
    case up = 0xFD
    case aboutFace = 0xFE
    case goTo = 0xFF

    /// The name used in the reference sources, for comments and diagnostics.
    public var referenceName: String {
        switch self {
        case .frame: "FRAME"
        case .nextLevel: "NEXTLEVEL"
        case .tap: "TAP"
        case .effect: "EFFECT"
        case .jard: "JARD"
        case .jaru: "JARU"
        case .die: "DIE"
        case .ifWithLess: "IFWTLESS"
        case .setFall: "SETFALL"
        case .act: "ACT"
        case .changeY: "CHY"
        case .changeX: "CHX"
        case .down: "DOWN"
        case .up: "UP"
        case .aboutFace: "ABOUTFACE"
        case .goTo: "GOTO"
        }
    }
}

/// Which opcodes an actor has registered.
///
/// **The opcode table is per actor class.** JavaScript builds it by prototype chain:
/// `Actor` registers six, `Fighter` adds three, `Kid` adds seven, and `Enemy` and
/// `Mouse` add none. A byte that is a real opcode but is not registered for the
/// actor executing it is a **silent no-op**.
///
/// This is not a technicality. The shipped data crosses the classes:
///
/// - `fighter.json` contains `JARD` (244), which only `Kid` registers → no-op for a guard
/// - `shadow.json` contains `EFFECT` (243), `JARD` (244) and `IFWTLESS` (247) → all no-ops for the shadow
/// - `mouse.json` contains `ACT` (249), which `Mouse` does not register → no-op
///
/// Treating the tables as one flat union would give guards and shadows behaviour they
/// have never had in any version of this game.
public enum ActorClass: Sendable, CaseIterable, Equatable {
    /// `Actor` — the mouse, and the cutscene-only princess and vizier.
    case actor

    /// `Fighter` — guards, skeleton, shadow, Jaffar.
    case fighter

    /// `Kid` — the Prince.
    case kid

    /// Registered by `Actor`'s constructor (after the 256-entry NOOP fill).
    private static let actorOpcodes: Set<Opcode> = [
        .frame, .tap, .changeY, .changeX, .aboutFace, .goTo,
    ]

    /// Registered by `Fighter`'s constructor.
    private static let fighterOpcodes: Set<Opcode> = [
        .die, .setFall, .act,
    ]

    /// Registered by `Kid`'s constructor.
    private static let kidOpcodes: Set<Opcode> = [
        .nextLevel, .effect, .jard, .jaru, .ifWithLess, .down, .up,
    ]

    public var registeredOpcodes: Set<Opcode> {
        switch self {
        case .actor: Self.actorOpcodes
        case .fighter: Self.actorOpcodes.union(Self.fighterOpcodes)
        case .kid: Self.actorOpcodes.union(Self.fighterOpcodes).union(Self.kidOpcodes)
        }
    }

    public func registers(_ opcode: Opcode) -> Bool {
        registeredOpcodes.contains(opcode)
    }
}
