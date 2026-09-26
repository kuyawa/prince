/// The fixed-timestep clock.
///
/// ARCHITECTURE.md Law 4: the simulation is never driven by vsync. A 120 Hz ProMotion
/// display would otherwise run the entire game ten times too fast.
///
/// The tick duration comes from `reference/SDLPoP/doc/internals_sequence-table.txt`,
/// which defines one *frame* as "1/12 seconds (1/10 s when fighting)". Both rates are
/// global: the whole simulation changes pace when a fight starts, rather than any
/// per-actor clock. (ARCHITECTURE.md open question 1 asked whether it was global or
/// per-actor; the doc's phrasing — a single definition of the frame unit — settles it
/// in favour of global. Worth a second look in M6 against `seg000.c` when combat lands.)
public struct Ticker: Sendable {
    /// 12 frames per second outside combat.
    public static let normalTickDuration = 1.0 / 12.0

    /// 10 frames per second while fighting.
    public static let combatTickDuration = 1.0 / 10.0

    /// A single rendered frame may never run more than this many simulation ticks.
    ///
    /// Without a cap, a hitch (a debugger pause, a window drag, a slow first frame)
    /// produces a burst of catch-up ticks, which costs more time, which produces more
    /// catch-up — the classic spiral of death. Dropping simulated time is the correct
    /// trade: the game falls behind reality for one frame instead of locking up.
    public static let maximumCatchUpTicks = 5

    private var accumulator: Double = 0

    /// Set by the combat system in M6.
    public var isFighting: Bool = false

    public init() {}

    public var tickDuration: Double {
        isFighting ? Self.combatTickDuration : Self.normalTickDuration
    }

    /// Adds elapsed wall-clock time and reports how many ticks to run now.
    ///
    /// Any time beyond the catch-up cap is discarded rather than banked, so the
    /// accumulator can never grow without bound.
    public mutating func ticks(forElapsed seconds: Double) -> Int {
        // Guard against a negative or absurd delta from a clock change or a
        // backgrounded window.
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let clamped = min(seconds, tickDuration * Double(Self.maximumCatchUpTicks))
        accumulator += clamped

        // The epsilon absorbs binary floating-point drift: 120 frames of 1/60 sum to
        // slightly under 2.0, which would otherwise report 19 ticks at 10 Hz instead of
        // 20. The drift is an artefact of representing 1/60 in binary, not of simulated
        // time, and the residual carries forward either way so no time is truly lost.
        let count = Int((accumulator / tickDuration + 1e-9).rounded(.down))
        let run = min(count, Self.maximumCatchUpTicks)
        accumulator -= Double(run) * tickDuration

        // Discard anything that would have exceeded the cap.
        if count > run {
            accumulator = 0
        }
        return run
    }

    /// Fractional progress toward the next tick, for interpolating rendering.
    ///
    /// Unused until M4, but it is the reason the accumulator is kept rather than
    /// consumed to zero.
    public var interpolation: Double {
        min(max(accumulator / tickDuration, 0), 1)
    }

    public mutating func reset() {
        accumulator = 0
    }
}
