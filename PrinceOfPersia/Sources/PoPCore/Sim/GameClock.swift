/// The hourglass.
///
/// Port source: `reference/PrinceJS/src/Utils.js#getRemainingMinutes` / `#getRemainingSeconds`,
/// and `Interface.js#showRegularRemainingTime`.
///
/// ```js
/// getRemainingMinutes: function () {
///   let deltaTime = PrinceJS.Utils.getDeltaTime();
///   return Math.min(60, Math.max(0, 60 - deltaTime.minutes));
/// },
/// getRemainingSeconds: function () {
///   let deltaTime = PrinceJS.Utils.getDeltaTime();
///   return Math.min(60, Math.max(0, 60 - deltaTime.seconds));
/// },
/// ```
///
/// **The reference reads the wall clock.** This counts simulated ticks instead, which is
/// identical under a fixed timestep but does not drift when frames are dropped — and it keeps the
/// simulation reproducible from a seed, which a clock read cannot.
///
/// Note the two accessors are not the same quantity. Minutes counts *whole minutes elapsed*, while
/// seconds clamps to 60, so it only ever counts down the **final minute**. That is why the HUD
/// switches from "N MINUTES LEFT" to "N SECONDS LEFT" and never shows anything in between.
public struct GameClock: Sendable, Equatable {
    /// `PrinceJS.minutes = 60` at the start of a run.
    public static let startingMinutes = 60

    /// The tick length, so elapsed time is derived rather than accumulated in floating point.
    public let tickDuration: Double

    public private(set) var elapsedTicks: Int = 0
    public private(set) var isRunning = true

    /// Set once the countdown reaches zero; the host ends the run.
    public private(set) var hasExpired = false

    public init(tickDuration: Double = Ticker.normalTickDuration) {
        self.tickDuration = tickDuration
    }

    public var totalSeconds: Int { Self.startingMinutes * 60 }

    public var elapsedSeconds: Int {
        Int((Double(elapsedTicks) * tickDuration).rounded(.down))
    }

    /// `getRemainingMinutes` — 60 down to 0, counting whole minutes.
    public var remainingMinutes: Int {
        min(Self.startingMinutes, max(0, Self.startingMinutes - elapsedSeconds / 60))
    }

    /// `getRemainingSeconds`.
    ///
    /// Note `getDeltaTime` returns the seconds **field**, not total elapsed seconds:
    ///
    /// ```js
    /// let seconds = Math.floor(diff / 1000) % 60;
    /// ```
    ///
    /// So this counts down *within the current minute* and resets to 60 each time one rolls over.
    /// It is what the bar shows during the final minute.
    public var remainingSeconds: Int {
        min(Self.startingMinutes, max(0, Self.startingMinutes - elapsedSeconds % 60))
    }

    /// `Interface.showRegularRemainingTime`'s three cases.
    ///
    /// The reference shows minutes when the remainder is a multiple of five *and* the seconds have
    /// just rolled over, switches to a seconds readout in the final minute, and raises `timeUp`
    /// at zero.
    public enum Readout: Sendable, Equatable {
        case none
        case minutes(Int)
        case seconds(Int)
        /// Zero minutes: the reference shows the seconds *and* raises `timeUp`.
        case timeUp(Int)
    }

    public var readout: Readout {
        if remainingMinutes == 0 { return .timeUp(remainingSeconds) }
        if remainingMinutes == 1 { return .seconds(remainingSeconds) }
        if remainingMinutes < Self.startingMinutes,
           remainingMinutes % 5 == 0,
           elapsedSeconds % 60 == 0 {
            return .minutes(remainingMinutes)
        }
        return .none
    }

    public mutating func advance() {
        guard isRunning, !hasExpired else { return }
        elapsedTicks += 1
        if remainingMinutes == 0 {
            hasExpired = true
            isRunning = false
        }
    }

    public mutating func stop() { isRunning = false }
    public mutating func reset() {
        elapsedTicks = 0
        isRunning = true
        hasExpired = false
    }
}
