/// The engine's pseudo-random generator — the MSVC `rand()` linear congruential
/// generator, the same one the DOS C runtime used.
///
/// Port source: `reference/PrinceJS/src/LevelBuilder.js`, used to generate wall
/// patterns:
///
/// ```js
/// this.seed = room;
/// this.seed = ((this.seed * 214013 + 2531011) & 0xffffffff) >>> 0;
/// return (this.seed >>> 16) % (max + 1);
/// ```
///
/// **Bit-exactness matters.** ARCHITECTURE.md Law 3 forbids `GKRandomSource` and any
/// other generator here: replay determinism depends on reproducing this sequence
/// exactly, and the constants are not the usual Numerical Recipes ones.
///
/// The reference seeds from the room number, so wall patterns are stable per room
/// across every playthrough.
public struct LCG: Sendable, Equatable {
    /// The multiplier and increment are the MSVC `rand()` constants and are not
    /// negotiable.
    private static let multiplier: UInt32 = 214_013
    private static let increment: UInt32 = 2_531_011

    public private(set) var state: UInt32

    /// Seeds the generator. The reference passes the room number.
    public init(seed: Int) {
        state = UInt32(truncatingIfNeeded: seed)
    }

    public init(state: UInt32) {
        self.state = state
    }

    /// Advances the generator and returns a value in `0...upperBound`.
    ///
    /// `&`-prefixed operators are wrapping, which is exactly the `& 0xffffffff` in
    /// the reference — Swift traps on overflow otherwise.
    public mutating func next(upperBound: Int) -> Int {
        state = state &* Self.multiplier &+ Self.increment
        return Int(state >> 16) % (upperBound + 1)
    }
}
