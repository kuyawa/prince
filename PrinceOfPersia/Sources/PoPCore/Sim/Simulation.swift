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

    /// One simulation tick.
    public mutating func tick(intents: Intents) {
        effects.removeAll(keepingCapacity: true)

        // Guards first, matching the reference's creation order.
        for index in world.actors.indices.dropFirst() {
            step(actorAt: index, intents: .none)
        }
        step(actorAt: 0, intents: intents)

        // Gates and buttons advance once per tick, after the actors have moved.
        world.update()
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
        let charName = world.actors[index].charName
        guard let interpreter = interpreters[ActorKind.animationTable(for: charName)] else { return }

        var actor = world.actors[index]

        // `updateBehaviour` — input for the Prince, the guard brain for everyone else.
        if index == 0 {
            let prince = actor
            Behaviour.update(&actor, intents: intents, world: world, effects: &effects)
            _ = prince
        } else {
            var rng = world.rng
            GuardBrain.update(
                &actor, opponent: world.actors[0], world: world,
                strength: world.strength, rng: &rng
            )
            world.rng = rng
        }
        world.actors[index] = actor
        world.apply(effects)

        // `processCommand`.
        actor = world.actors[index]
        try? interpreter.step(&actor, world: world, effects: &effects)
        world.actors[index] = actor
        world.apply(effects)

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

        // `checkButton`.
        actor = world.actors[index]
        TileChecks.checkButton(&actor, world: &world)
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
        world.apply(effects)

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
