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

    /// What happens after the Prince dies: a beat, four seconds, then a countdown that restarts
    /// the level — or any key, which skips the rest of it.
    public private(set) var death = DeathSequence()

    /// Whether the Prince was alive at the end of the previous tick. The death is detected on the
    /// tick the flag falls, so every cause of death is caught without each of them having to
    /// remember to say so.
    private var wasPrinceAlive = true

    /// Set once a restart has been asked for, so a headless run asks once rather than every tick.
    /// The host reloads the level and gets a fresh `Simulation` anyway; a test does not.
    private var hasRequestedRestart = false

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

    /// `Game.handleDead`, `Game.checkTimers` and `Game.buttonPressed`.
    ///
    /// The death is noticed from the Prince's own flag rather than from a `.died` effect, because
    /// the effect carries no actor: spikes, boards, choppers, guards and a plain fall out of the
    /// world all end the same way, and none of them should have to report it separately.
    private mutating func advanceDeath() {
        let isAlive = world.prince.isAlive
        if wasPrinceAlive, !isAlive, !hasRequestedRestart {
            death.start()
        }
        wasPrinceAlive = isAlive

        guard death.isRunning, !hasRequestedRestart else { return }

        // A key *press* ends the wait wherever it has got to; otherwise the countdown does.
        //
        // **A press, not a hold.** The reference listens on Phaser's `onDownCallback`, which is a
        // key-down event, and the distinction shows: a player killed while running right is still
        // holding right, and treating that as a press would restart the level a fifth of a second
        // after the death animation started. What the player has to do is let go and press again.
        if death.acceptsButtonPress, !pressedIntents.subtracting(previousIntents).isEmpty {
            death.stop()
            hasRequestedRestart = true
            effects.append(.restartLevel)
            return
        }

        if death.advance() {
            death.stop()
            hasRequestedRestart = true
            effects.append(.restartLevel)
            return
        }

        // `Interface.update` beeps each time the flashing text comes back on.
        if death.shouldBeep { effects.append(.sound(.beep)) }
    }

    /// The input for the tick being run, and for the one before it. Kept because the death wait
    /// needs the *rising edge* — a key going down — and the tick's intents are otherwise gone by
    /// the time it runs.
    private var pressedIntents: Intents = .none
    private var previousIntents: Intents = .none

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
        pressedIntents = intents

        // `Game.checkForOpponent`, before anyone is stepped. The Prince's behaviour asks whether he
        // can reach his opponent and `checkFight` runs for both fighters, so it has to be settled
        // before either of them runs.
        updatePrinceOpponent()

        // Guards first, matching the reference's creation order.
        for index in world.actors.indices.dropFirst() {
            step(actorAt: index, intents: .none)
        }
        step(actorAt: 0, intents: intents)

        // Gates and buttons advance once per tick, after the actors have moved.
        world.update(effects: &effects, interpreter: interpreters[ActorKind.animationTable(for: "kid")])

        // The one-second drink animation, and the float potion's eighteen-second clock.
        applyDuePotions()
        world.advanceFloatTimers()

        // The hourglass. Set once, on the tick it runs out.
        let wasExpired = clock.hasExpired
        clock.advance()
        if clock.hasExpired, !wasExpired { effects.append(.timeUp) }

        advanceDeath()
        previousIntents = pressedIntents
        ticksInLevel += 1
    }

    /// The status bar's contents for this tick.
    public func hud(font: BitmapFont) -> HudDescription {
        HudRenderer.describe(
            world: world, clock: clock, ticksInLevel: ticksInLevel, death: death, font: font
        )
    }

    /// Runs the hourglass forward without running the level.
    ///
    /// A seam: sixty minutes is 43,200 ticks, which is too many to play out for one assertion.
    /// The effect itself is still produced by `tick`, so this changes *when* the hourglass is
    /// read, not how.
    public mutating func advanceClock(ticks: Int) {
        for _ in 0..<ticks { clock.advance() }
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
        // `updateSplash` is the first thing `updateActor` does.
        Splash.update(&world.actors[index])

        // `Kid.updateTimer` — the bump sound's rate limit, and the half-second after a grab
        // during which the ledge cannot be climbed.
        if world.actors[index].bumpTimer > 0 { world.actors[index].bumpTimer -= 1 }
        if world.actors[index].grabWaitTicks > 0 {
            world.actors[index].grabWaitTicks -= 1
            if world.actors[index].grabWaitTicks == 0 { world.actors[index].grabWait = false }
        }

        let charName = world.actors[index].charName
        guard let interpreter = interpreters[ActorKind.animationTable(for: charName)] else { return }

        var actor = world.actors[index]

        // `updateBehaviour` — input for the Prince, the guard brain for everyone else.
        if index == 0 {
            // The opponent goes in as a copy and comes back out, the way the reference's live
            // object reference would: `Kid.fastsheathe` is the one verb that writes to it.
            let foeIndex = opponentIndex(for: 0)
            var foe = foeIndex.map { world.actors[$0] }
            try? Behaviour.update(
                &actor, intents: intents, world: world,
                interpreter: interpreter, opponent: &foe, effects: &effects
            )
            if let foeIndex, let foe { world.actors[foeIndex] = foe }
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
            let released = Combat.checkFight(
                &mine, &other, world: world, effects: &effects
            )
            world.actors[index] = mine
            world.actors[opponent] = other
            // The guard died and the Prince has just sheathed his sword. The reference drops its
            // reference to the opponent in that same branch; a stale one would keep him in a
            // fighting stance, or turn him back to face a corpse.
            if index == 0, released { princeOpponent = nil }
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
        _ = try? Barrier.checkBarrier(
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
            // After the landing test, so a caught ledge is not also swung from.
            FallCycle.checkLedgeSwing(&actor)
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
    /// Every guard fights the Prince, which is the pairing the reference ends up with in every
    /// non-combat case. The Prince fights whoever `Game.checkForOpponent` last found for him —
    /// see `princeOpponent`, which is sticky and may name a guard who has since died.
    public func opponentIndex(for index: Int) -> Int? {
        if index != 0 {
            return world.actors[0].isAlive ? 0 : nil
        }
        return princeOpponent
    }

    // MARK: - The Prince's opponent

    /// `Game.checkForOpponent` — the Prince's opponent, and the one piece of combat state that
    /// outlives a tick.
    ///
    /// The reference holds a live reference to this guard, which is why nothing there has to
    /// remember it. A value-type world does, and the reason it cannot simply be looked up fresh
    /// each tick is the **kill**: the search only ever returns a *living* guard, so a query that
    /// died with the guard would stop `Fighter.checkFight` from running on exactly the tick that
    /// sheathes the Prince's sword — and he is then left standing in his stance for ever, with his
    /// sword out and no verb that can put it away.
    private var princeOpponent: Int?

    /// The four-pass search, in the reference's order, stopping at the first hit.
    ///
    /// Assigns only when it *finds* someone, which is what makes the opponent sticky. A new
    /// opponent also ends the flight from the old one (`kid.flee = false`), so a Prince who fled
    /// one guard still fights the next.
    private mutating func updatePrinceOpponent() {
        let prince = world.actors[0]
        guard prince.isAlive else { return }

        guard let found = princeOpponentSearch(prince), found != princeOpponent else { return }
        princeOpponent = found
        world.actors[0].flee = false
    }

    /// Same room on his row, then the neighbouring rooms on his row, then the room whatever row,
    /// then the neighbours whatever row.
    private func princeOpponentSearch(_ prince: ActorState) -> Int? {
        let candidates = world.actors.indices.dropFirst()
            .filter { world.actors[$0].isAlive }

        let sameRow = { (index: Int) in
            world.actors[index].charBlockY == prince.charBlockY
        }
        let here = { (index: Int) in
            world.actors[index].room == prince.room
        }
        let near = { (index: Int) in
            Combat.opponentNearRoom(prince, world.actors[index], world: world)
        }

        return candidates.first { sameRow($0) && here($0) }
            ?? candidates.first { sameRow($0) && near($0) }
            ?? candidates.first { here($0) }
            ?? candidates.first { near($0) }
    }
}
