/// The three hazard and pickup tiles that are not mechanisms.
///
/// Port source: `reference/PrinceJS/src/tiles/Spikes.js`, `Potion.js`, `Sword.js`.
///
/// All three are *trobs* — tiles the level ticks once per frame — but unlike `Gate` and
/// `ExitDoor` they are not driven by buttons. Spikes are raised by an actor walking over or under
/// them; potions and swords sit there and wait to be picked up.
///
/// ## What the level data actually uses
///
/// Across all fourteen levels:
///
/// | Tile | Modifiers seen |
/// |---|---|
/// | spikes | only `0` (100 tiles) |
/// | chopper | only `0` (36 tiles) |
/// | loose board | only `0` (148 tiles) |
/// | sword | only `0` (2 tiles) |
/// | potion | `1`-`5` (47 tiles) |
///
/// Two consequences worth stating plainly. First, `Spikes`’ modifier remapping (which turns
/// modifiers 1-9 into sprite frames 1, 2, 5, 4 and `9 - m`) is **dead code in practice** — every
/// shipped spike field is a plain modifier-0 one, and the `modifier === 0` guard in `LevelBuilder`
/// that decides what becomes a trob therefore never excludes anything. It is ported anyway,
/// because the engine defines it and a custom map could use it.
///
/// Second, `POTION_SPECIAL` is 6 and **no level contains one**, so the reference’s special-potion
/// path — read a modifier out of room 8 tile 0, then fire an event a second after drinking — is
/// unreachable. `Potion.isSpecial` is modelled so the data is faithful; the event plumbing is not
/// built, because there is nothing to test it against.

// MARK: - Spikes

/// `PrinceJS.Tile.Spikes`.
///
/// A field of spikes that shoots up when someone walks past and retracts on its own. The state
/// machine is five frames up and five down, with a sixteen-frame dwell at the top.
public struct Spikes: Sendable, Equatable {
    public enum Phase: Int, Sendable {
        case inactive = 0
        case raising = 1
        case fullOut = 2
        case dropping = 3
    }

    public var phase: Phase
    public var step: Int

    /// `modifier < 5` — the reference sets it and then never reads it. Kept so the data is
    /// complete; the engine appears to have dropped the check.
    public let mortal: Bool

    /// The sprite frame the modifier selects.
    public let frame: Int

    /// Ticks the spikes stay fully out before dropping.
    public static let dwellTicks = 15
    /// The frame at which a raise finishes.
    public static let raisedFrame = 5

    public init(modifier: Int) {
        phase = .inactive
        step = 0
        mortal = modifier < 5

        // The reference rewrites the modifier for the sprite only, after storing `mortal`.
        var m = modifier
        if m > 2, m < 6 { m = 5 }
        if m == 6 { m = 4 }
        if m > 6 { m = 9 - m }
        frame = m
    }

    /// The frame to draw.
    public var frameIndex: Int {
        switch phase {
        case .inactive: frame
        case .raising, .dropping: step
        case .fullOut: Self.raisedFrame
        }
    }

    /// Whether the spikes are out far enough to be lethal.
    public var isLethal: Bool { phase != .inactive }

    /// `Spikes.raise`. Returns the sound, which plays only on a field that was fully retracted.
    @discardableResult
    public mutating func raise() -> SoundEffect? {
        if phase == .inactive {
            phase = .raising
            step = 0
            return .impaledBySpikes
        }
        // Already out: restart the dwell timer rather than the animation.
        if phase == .fullOut { step = 0 }
        return nil
    }

    /// `Spikes.drop`.
    public mutating func drop() {
        phase = .dropping
        step = Self.raisedFrame
    }

    /// `Spikes.update`. Never makes a sound — the noise belongs to `raise`.
    public mutating func update() {
        switch phase {
        case .inactive:
            break

        case .raising:
            step += 1
            if step == Self.raisedFrame {
                phase = .fullOut
                step = 0
            }

        case .fullOut:
            step += 1
            if step > Self.dwellTicks { drop() }

        case .dropping:
            step -= 1
            // The reference skips frame 3 on the way down, so the retraction is one tick
            // shorter than the raise. Reproduced as written.
            if step == 3 { step -= 1 }
            if step == 0 { phase = .inactive }
        }
    }
}

// MARK: - Chopper

/// `PrinceJS.Tile.Chopper` — the slicer blades that drop out of a ceiling.
///
/// The blades are *always* running; what an actor triggers is one cut. `chop` starts a fifteen-step
/// cycle, and only steps 1 to 3 can take a head off — step 3 is the frame the blades meet, which is
/// also the only one that makes a noise and the only one that asks the level to start the next
/// chopper along.
public struct Chopper: Sendable, Equatable {
    public var isActive: Bool
    public var step: Int

    /// `handleChop` passes `tile.room === currentCameraRoom`, so a chopper in a room the camera
    /// is not on cuts silently. Without it, a row of blades across three rooms would roar.
    public var isAudible: Bool

    /// `Chopper.showBlood` — the stain is drawn from the `general` atlas.
    public var showsBlood: Bool

    /// The cycle resets after this step.
    public static let lastStep = 14
    /// The only step that can cut.
    public static let cutStep = 3
    /// Frames run 0 to 5; the cycle keeps counting to 14 without drawing anything new.
    public static let lastFrame = 5

    public init() {
        isActive = false
        step = 0
        isAudible = false
        showsBlood = false
    }

    /// `Chopper.chop`.
    public mutating func chop(audible: Bool) {
        isActive = true
        isAudible = audible
    }

    /// `Chopper.showBlood`.
    public mutating func showBlood() { showsBlood = true }

    /// The frame to draw.
    ///
    /// There is **no frame 0**. `Chopper.update` increments `step` *before* it names a frame, so
    /// the first frame drawn is 1; the constructor starts the child sprites on frame 5, and steps
    /// past 5 leave them there. Hence 5 is both the resting pose and the last frame of the cut.
    public var frameIndex: Int {
        step >= 1 && step <= Self.lastFrame ? step : Self.lastFrame
    }

    /// `Chopper.update`.
    public mutating func update() -> Trob.Outcome {
        guard isActive else { return Trob.Outcome() }

        step += 1
        if step > Self.lastStep {
            step = 0
            isActive = false
            return Trob.Outcome()
        }
        // Past frame 5 the cycle still runs but draws nothing, so there is nothing to report.
        guard step <= Self.lastFrame else { return Trob.Outcome() }
        guard step == Self.cutStep else { return Trob.Outcome() }

        return Trob.Outcome(sound: isAudible ? .slicerBladesClash : nil, chopped: true)
    }
}

// MARK: - Potion

/// What drinking a potion does, `POTION_*` in `Level.js`.
public enum PotionEffect: Int, Sendable, CaseIterable {
    case recover = 1
    case add = 2
    case buffer = 3
    case flip = 4
    case damage = 5

    /// The music the reference plays, if any. `buffer` and `flip` are visual only.
    public var music: MusicTrack? {
        switch self {
        case .recover: .potion1
        case .add: .potion2
        default: nil
        }
    }

    /// The one-shot the reference plays alongside, if any.
    public var sound: SoundEffect? {
        switch self {
        case .damage: .stabbedByOpponent
        default: nil
        }
    }
}

/// A potion drunk but not yet taken effect.
///
/// `Kid.drinkPotion` wraps the whole switch in `PrinceJS.Utils.delayed(..., 1000)`, a wall-clock
/// timeout. The port counts twelve ticks instead — 1000 ms at the fixed 1/12 s step — which is
/// the same second without reading a clock.
public struct PendingPotion: Sendable, Equatable {
    public var effect: PotionEffect
    public var ticksRemaining: Int

    /// 1000 ms at 1/12 s per tick.
    public static let delayTicks = 12

    public init(effect: PotionEffect, ticksRemaining: Int = PendingPotion.delayTicks) {
        self.effect = effect
        self.ticksRemaining = ticksRemaining
    }
}

/// `PrinceJS.Tile.Potion`.
///
/// The bottle is static; the bubbles above it cycle through seven frames. The reference seeds
/// that cycle from Phaser’s RNG, which is a *different* generator from the one the rest of the
/// port uses and is not replayable. Scattering the phase by tile index keeps the bottles out of
/// step with each other without perturbing the simulation’s own stream.
public struct Potion: Sendable, Equatable {
    /// The raw modifier, before clamping. `>= 6` means special.
    public let specialModifier: Int
    /// The sprite variant, `clamp(modifier, 1, 5)`.
    public let modifier: Int
    public let isSpecial: Bool

    /// Which of the seven bubble frames is showing.
    public var step: Int

    /// `bubbleColors[modifier - 1]`.
    public let color: String

    public static let bubbleFrames = 7
    public static let bubbleColors = ["red", "red", "green", "green", "blue"]

    public init(modifier raw: Int, scatter: Int = 0) {
        specialModifier = raw
        isSpecial = raw >= 6
        modifier = max(1, min(5, raw))
        step = ((scatter % Self.bubbleFrames) + Self.bubbleFrames) % Self.bubbleFrames
        color = Self.bubbleColors[modifier - 1]
    }

    /// What this potion does when drunk. `nil` for a special potion, which the port does not
    /// implement — no shipped level contains one.
    public var effect: PotionEffect? { PotionEffect(rawValue: modifier) }

    /// `Potion.update` — the bubbles only.
    public mutating func update() {
        step = (step + 1) % Self.bubbleFrames
    }
}

// MARK: - Sword

/// `PrinceJS.Tile.Sword` — the sword lying on the floor, which glints at intervals.
///
/// The reference picks the interval with `game.rnd.between(40, 167)`. As with the potion bubbles,
/// that generator is Phaser’s and is not the one this port replays, so the interval is derived
/// from the tile index instead: deterministic, and varied between two swords.
public struct Sword: Sendable, Equatable {
    /// `step === -1` is the reference’s "just flashed, pick a new interval" marker.
    public var isBright: Bool
    public var step: Int
    public var tick: Int

    public static let minTick = 40
    public static let maxTick = 167

    public init(scatter: Int = 0) {
        isBright = false
        step = 0
        let span = Self.maxTick - Self.minTick
        tick = Self.minTick + ((scatter % span) + span) % span
    }

    /// `Sword.update`.
    public mutating func update() {
        if step == -1 {
            isBright = false
            // The reference draws a new random interval here; the port walks the range instead.
            tick = Self.minTick + (tick - Self.minTick + 53) % (Self.maxTick - Self.minTick)
        }
        step += 1
        if step == tick {
            isBright = true
            step = -1
        }
    }
}
