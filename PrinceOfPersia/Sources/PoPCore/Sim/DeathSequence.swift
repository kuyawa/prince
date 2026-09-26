/// What happens after the Prince dies.
///
/// Port source: `reference/PrinceJS/src/Game.js#handleDead` (666), `#checkTimers` (554) and
/// `#buttonPressed` (690), plus `Interface.js#showPressButtonToContinue` (263) and the flashing in
/// `Interface.js#update` (181).
///
/// ## The reference has three beats, and they are all here
///
/// ```js
/// handleDead:  this.continueTimer = 10;
///
/// checkTimers: if (this.continueTimer > -1) {
///                this.continueTimer--;
///                if (this.continueTimer === 0) {
///                  this.ui.showPressButtonToContinue();   // shows the text after 4 s
///                  this.pressButtonToContinueTimer = 260; // then restarts on its own
///                }
///              }
///
/// buttonPressed: if (this.pressButtonToContinueTimer > -1) { this.reset(true); }
/// ```
///
/// So: **a beat** so the death animation is not cut off, then **four seconds** before the message,
/// then a countdown that restarts the game by itself. Any key skips the rest of the wait.
///
/// ## One thing that is not reproduced
///
/// The reference keeps *two* timers, one on `Game` and one on `Interface`, both decremented every
/// frame: `Game`’s counts 260 down to the restart, and `Interface`’s counts 200 down and exists only
/// to flash the text once it drops below 70. Neither is visible to the player, so this is one
/// counter and one flash rule.
public struct DeathSequence: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case none
        /// The beat before anything is shown.
        case settling
        /// The countdown to an automatic restart. The message appears part-way through it.
        case waiting
    }

    /// `continueTimer = 10`.
    public static let settleTicks = 10

    /// The whole wait, from the end of the beat. `Game`’s 260 covers the 4 seconds before the
    /// message as well as the wait after it, so the full delay is 260 ticks — about 21 seconds.
    public static let waitTicks = 260

    /// `Utils.delayed(..., 4000)` — when the message appears, 4 s into the wait — and therefore
    /// how long it is up before the automatic restart.
    public static let messageDelayTicks = 48

    /// `Interface.update`: below 70 the text flashes, once every 7 ticks.
    public static let flashBelowTicks = 70
    public static let flashInterval = 7

    public private(set) var phase: Phase = .none
    /// Ticks left in the current phase.
    public private(set) var ticksRemaining = 0
    /// Ticks since the wait began. The message appears at `messageDelayTicks`.
    public private(set) var elapsed = 0
    /// Whether the message is drawn *this* tick — which is not the same as whether it is up,
    /// because it flashes near the end.
    public private(set) var isMessageVisible = false
    /// True on the tick the flash turns the text back on. The reference beeps there.
    public private(set) var shouldBeep = false

    public init() {}

    public var isRunning: Bool { phase != .none }

    /// Whether the message is up at all, flashing or not.
    public var showsMessage: Bool { phase == .waiting && elapsed >= Self.messageDelayTicks }

    /// `Game.buttonPressed` — a key press ends the wait, from the moment the countdown starts.
    ///
    /// Note it accepts the press *before* the message has been drawn: the reference’s timer is
    /// already running during the four seconds of silence.
    public var acceptsButtonPress: Bool { phase == .waiting }

    /// `Game.handleDead`.
    public mutating func start() {
        phase = .settling
        ticksRemaining = Self.settleTicks
        elapsed = 0
        isMessageVisible = false
        shouldBeep = false
    }

    /// One tick. Returns `true` on the tick the game should restart itself.
    @discardableResult
    public mutating func advance() -> Bool {
        shouldBeep = false

        switch phase {
        case .none:
            return false

        case .settling:
            ticksRemaining -= 1
            if ticksRemaining == 0 {
                phase = .waiting
                ticksRemaining = Self.waitTicks
                elapsed = 0
            }
            return false

        case .waiting:
            ticksRemaining -= 1
            elapsed += 1

            // Once, on the tick it appears. Assigning it every tick would force the text back on
            // immediately after each flash and the toggle could never turn it off — which is a
            // message that never flashes and a beep that never sounds.
            if elapsed == Self.messageDelayTicks { isMessageVisible = true }

            // The flash only starts near the end, so the message is steady while it is still the
            // only thing telling the player what to do.
            // `ticksRemaining > 0` is deliberate: the last tick restarts the game, so flashing
            // the text there would be a beep nobody hears over a loading screen.
            if ticksRemaining > 0, ticksRemaining < Self.flashBelowTicks,
               ticksRemaining % Self.flashInterval == 0 {
                isMessageVisible.toggle()
                shouldBeep = isMessageVisible
            }

            // The wait ends itself. Reporting completion while leaving the phase alone would
            // make `isRunning` stay true for ever, and any caller looping on it — a test, or the
            // simulation — would spin.
            if ticksRemaining == 0 {
                phase = .none
                isMessageVisible = false
                return true
            }
            return false
        }
    }

    /// `Game.reset` — the wait is abandoned, not paused.
    public mutating func stop() {
        phase = .none
        ticksRemaining = 0
        elapsed = 0
        isMessageVisible = false
        shouldBeep = false
    }

    /// The text the interface shows, in the reference’s own words and its own mixed case.
    public static let message = "Press Button to Continue"
}
