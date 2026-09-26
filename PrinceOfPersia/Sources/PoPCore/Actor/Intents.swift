/// Player input for one tick, as a value.
///
/// ARCHITECTURE.md Law 6: the simulation never reads the keyboard. `PoPHost` samples the
/// keys into this and hands it over, which is what makes replay, demo playback and
/// scripted tests the same code path.
///
/// Port source: `Kid.js#keyL`/`keyR`/`keyU`/`keyD`/`keyS`, each of which ORs together a
/// cursor key, a touch pointer and a gamepad button. Only the digital key part is
/// modelled here; pointers and gamepads are host concerns.
public struct Intents: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let left = Intents(rawValue: 1 << 0)
    public static let right = Intents(rawValue: 1 << 1)
    public static let up = Intents(rawValue: 1 << 2)
    public static let down = Intents(rawValue: 1 << 3)

    /// The action key — Shift in the original. Drink potion, grab a ledge, strike.
    public static let action = Intents(rawValue: 1 << 4)

    public static let none: Intents = []
}
