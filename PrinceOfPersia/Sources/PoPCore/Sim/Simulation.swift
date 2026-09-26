/// The simulation tick.
///
/// This is where `Kid.updateActor` / `Enemy.updateActor` live, and it belongs in `PoPCore`
/// rather than in the scene: it is game logic, and keeping it here means a duel can be driven
/// headlessly with no window at all.
///
/// ## Actor order
///
/// The reference creates the guards **before** the Prince (`Game.js` builds every `Enemy`, then
/// `this.kid`), and updates them in that order. The port keeps the Prince at index 0 for lookup
/// but still ticks the guards first, because the order decides which of two simultaneous events
/// lands first and it costs nothing to match.
public struct Simulation: Sendable {
    /// Readable everywhere, mutable inside the module — which is what lets a test place an actor
    /// before running ticks.
    public internal(set) var world: World

    /// Effects produced by the tick just run. Drained every tick; the host reads them after.
    public private(set) var effects: [ActorEffect] = []

    /// The hourglass. Counts simulated ticks rather than reading a wall clock, so a run is
    /// reproducible and does not drift when frames are dropped.
    public private(set) var clock = GameClock()

    /// Ticks since this level loaded — what the status bar uses to decide whether to show the
    /// level's name or the clock.
    public private(set) var ticksInLevel = 0

    /// One interpreter per animation table — `kid`, `fighter`, `shadow`, and so on. They are
    /// stateless apart from the table, so they are shared rather than per-actor.
    private var interpreters: [String: SequenceInterpreter] = [:]

    public enum Failure: Error, CustomStringConvertible {
        case missingAnimationTable(String)

        public var description: String {
            switch self {
            case let .missingAnimationTable(name): "No animation table named \(name)"
            }
        }
    }

    /// - Parameters:
    ///   - princeHealth: carried across a level change. `CMD_NEXTLEVEL` does
    ///     `PrinceJS.maxHealth = this.maxHealth` and passes the current health to the next level.
    public init(
        level: LevelRuntime,
        seed: Int = 0,
        strength: Int = 100,
        princeHealth: Int? = nil,
        princeMaxHealth: Int? = nil
    ) throws {
        self.world = World(level, seed: seed, strength: strength)

        if let princeHealth { world.actors[0].health = princeHealth }
        if let princeMaxHealth {
            world.actors[0].maxHealth = princeMaxHealth
            world.actors[0].health = min(world.actors[0].health, princeMaxHealth)
        }

        for actor in world.actors {
            let tableName = ActorKind.animationTable(for: actor.charName)
            if interpreters[tableName] == nil {
                // Only a Fighter can hold a sword, so the Kid's and the guards' tables get one.
                let offsets = ActorKind.actorClass(for: actor.charName) == .actor
                    ? nil : try? GameData.swordOffsetTable()
                interpreters[tableName] = SequenceInterpreter(
                    table: try GameData.animationTable(named: tableName),
                    actorClass: ActorKind.actorClass(for: actor.charName),
                    swordOffsets: offsets
                )
            }
        }
    }

    /// How many of `effects` the world has already been told about this tick.
    private var appliedEffectCount = 0

    /// Hands the world the effects it has not seen yet.
    ///
    /// `effects` accumulates for the whole tick — the reference emits into a shared channel too —
    /// and `step(actorAt:)` applies after each stage. Passing the whole array every time meant an
    /// effect was applied once per *later* stage of the same tick, which is invisible for an
    /// idempotent one (shaking a board, masking a door) and wrong for a counting one: a potion
    /// drank once was queued three times and its theme played three times over itself.
    private mutating func applyNewEffects() {
        guard appliedEffectCount < effects.count else { return }
        world.apply(Array(effects[appliedEffectCount...]))
        appliedEffectCount = effects.count
    }

    /// `Kid.drinkPotion`'s delayed switch, and the two life-changing events that come with it.
    ///
    /// Only the Prince can drink, so this reads actor 0. The reference dispatches the effect from
    /// the drinking actor's own closure, which for a guard would do the same thing — no guard
    /// drinks, so one slot is the honest model.
    private mutating func applyDuePotions() {
        for effect in world.advanceDelayedEffects() {
            var prince = world.actors[0]

            switch effect {
            case .recover:
                // `recoverLife`: heals one, never past the maximum.
                if prince.health < prince.maxHealth { prince.health += 1 }

            case .add:
                // `addLife`: raises the ceiling to ten and fills to it.
                if prince.maxHealth < 10 { prince.maxHealth += 1 }
                prince.health = prince.maxHealth

            case .buffer:
                // `floatFall`: eighteen seconds of gentle gravity and survivable falls.
                prince.isInFloat = true
                prince.floatTicksRemaining = World.floatTicks

            case .flip:
                // `flipScreen` toggles a global the renderer reads. Nothing in the simulation
                // depends on it, so it goes out as an effect and stops there.
                effects.append(.flipScreen)

            case .damage:
                // `flashRedDamage` plus the generic stab sound, then a point of health.
                effects.append(.sound(.stabbedByOpponent))
                Combat.damageLife(&prince, effects: &effects)
            }

            if let track = effect.music { effects.append(.music(track)) }
            world.actors[0] = prince
        }
    }

    /// One simulation tick.
    public mutating func tick(intents: Intents) {
        effects.removeAll(keepingCapacity: true)
        appliedEffectCount = 0

        // Guards first, matching the reference's creation order.
        for index in world.actors.indices.dropFirst() {
            step(actorAt: index, intents: .none)
        }
        step(actorAt: 0, intents: intents)

        // Gates and buttons advance once per tick, after the actors have moved.
        world.update(effects: &effects)

        // The one-second drink animation, and the float potion's eighteen-second clock.
        applyDuePotions()
        world.advanceFloatTimers()

        clock.advance()
        ticksInLevel += 1
    }

    /// The status bar's contents for this tick.
    public func hud(font: BitmapFont) -> HudDescription {
        HudRenderer.describe(
            world: world, clock: clock, ticksInLevel: ticksInLevel, font: font
        )
    }

    /// Runs `count` ticks with the same input, for headless tests and screenshots.
    public mutating func run(_ count: Int, intents: Intents = .none) {
        for _ in 0..<count { tick(intents: intents) }
    }

    // MARK: - One actor's tick

    /// One actor, in `Kid.updateActor`'s order.
    ///
    /// The actor is copied out of the array, worked on as a local, and written back between
    /// steps. Assigning through `world.actors[index]` while also handing `world` to a function
    /// is an exclusivity violation in Swift, and the copy is the honest fix rather than an
    /// escape hatch.
    private mutating func step(actorAt index: Int, intents: Intents) {
        // `Kid.updateTimer` — the bump sound's rate limit.
        if world.actors[index].bumpTimer > 0 { world.actors[index].bumpTimer -= 1 }

        let charName = world.actors[index].charName
        guard let interpreter = interpreters[ActorKind.animationTable(for: charName)] else { return }

        var actor = world.actors[index]

        // `updateBehaviour` — input for the Prince, the guard brain for everyone else.
        if index == 0 {
            let prince = actor
            try? Behaviour.update(
                &actor, intents: intents, world: world,
                interpreter: interpreter, effects: &effects
            )
            _ = prince
        } else {
            var rng = world.rng
            GuardBrain.update(
                &actor, opponent: world.actors[0], world: world,
                strength: world.strength, rng: &rng, effects: &effects
            )
            world.rng = rng
        }
        world.actors[index] = actor
        applyNewEffects()

        // `processCommand`.
        actor = world.actors[index]
        try? interpreter.step(&actor, world: world, effects: &effects)
        world.actors[index] = actor
        applyNewEffects()

        // `updateAcceleration` then `updateVelocity`.
        actor = world.actors[index]
        Physics.accelerate(&actor)
        Physics.move(&actor)
        world.actors[index] = actor

        // `checkFight` — both fighters, because the reference has each reach into the other.
        if let opponent = opponentIndex(for: index) {
            var mine = world.actors[index]
            var other = world.actors[opponent]
            Combat.checkFight(&mine, &other, world: world, effects: &effects)
            world.actors[index] = mine
            world.actors[opponent] = other
        }

        // `checkSpikes` — raise every spike field in this column, and in the next one along when
        // he is near the edge of his tile. Runs *before* the floor probe below, which is what
        // makes a field he disturbed himself still be rising when he steps onto it.
        actor = world.actors[index]
        TileChecks.checkSpikes(&actor, world: &world, effects: &effects)
        world.actors[index] = actor

        // `checkChoppers` — the kid wakes the blades in his row, and any chopper at his feet may
        // take him in half. Runs before the spike checks, matching `updateActor`'s order.
        actor = world.actors[index]
        TileChecks.checkChoppers(&actor, world: &world, effects: &effects)
        world.actors[index] = actor

        // `checkBarrier` — the screen-space collision that stops the Prince at a wall, a gate, a
        // tapestry or a mirror, and turns the contact into a bump.
        actor = world.actors[index]
        try? Barrier.checkBarrier(
            &actor, world: world, interpreter: interpreter, effects: &effects
        )
        world.actors[index] = actor

        // `checkButton`.
        actor = world.actors[index]
        if let pressed = TileChecks.checkButton(&actor, world: &world),
           let sound = world.floorButtonSound(at: pressed) {
            effects.append(.sound(sound))
        }
        world.actors[index] = actor

        // The `TILE_SPIKES` case of `checkFloor`'s standing branch. Separate from the call below
        // because it needs a mutable world; the branches are mutually exclusive.
        actor = world.actors[index]
        TileChecks.checkSpikeFloor(&actor, world: &world, effects: &effects)
        world.actors[index] = actor

        // `checkFloor` — the standing branch can start a fall, the falling branch can end one.
        actor = world.actors[index]
        try? FallCycle.checkFloorStanding(
            &actor, world: world, interpreter: interpreter, effects: &effects
        )
        if actor.actionCode == 3 || actor.actionCode == 4 {
            try? FallCycle.checkFall(
                &actor, world: world, interpreter: interpreter, effects: &effects
            )
        }
        world.actors[index] = actor
        applyNewEffects()

        // `checkRoomChange`. The Prince uses Kid's threshold, guards use Fighter's.
        actor = world.actors[index]
        if index == 0 {
            FallCycle.checkRoomChange(&actor, world: world)
        } else {
            FallCycle.fighterCheckRoomChange(&actor, world: world)
        }
        world.actors[index] = actor
    }

    /// Who an actor is fighting.
    ///
    /// **Simplified.** The reference sets `this.opponent` when a fight begins and the two
    /// reference each other. Here a guard always faces the Prince, and the Prince faces the
    /// nearest living guard in his room — which is the same pairing in every non-combat case and
    /// differs only when three or more fighters converge.
    public func opponentIndex(for index: Int) -> Int? {
        if index != 0 {
            return world.actors[0].isAlive ? 0 : nil
        }
        let prince = world.actors[0]
        return world.actors.indices.dropFirst()
            .filter { world.actors[$0].isAlive && world.actors[$0].room == prince.room }
            .min {
                abs(world.actors[$0].charX - prince.charX)
                    < abs(world.actors[$1].charX - prince.charX)
            }
    }
}
