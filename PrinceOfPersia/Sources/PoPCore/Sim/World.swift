/// A level plus its mutable state, presented to the simulation as one world.
///
/// `LevelRuntime` is the decoded level and never changes. `LevelState` is everything that does —
/// gate positions, button presses, whether the exit opened. Together they satisfy `TileWorld`,
/// which is what the movement code and the VM ask for.
public struct World: Sendable {
    public let level: LevelRuntime
    public private(set) var state: LevelState

    /// Every actor in the level. **Index 0 is always the Prince.**
    ///
    /// Combat has to address an opponent, and the reference does it with a direct object
    /// reference. In a value-type simulation the index is the equivalent, and fixing the Prince
    /// at zero keeps the common case cheap.
    public internal(set) var actors: [ActorState]

    /// The shared generator. It lives in the world so that a seed reproduces a whole run,
    /// including every guard decision.
    public internal(set) var rng: LCG

    /// The player's chosen difficulty, 0–100. Scales every guard probability.
    public var strength: Int

    public init(_ level: LevelRuntime, seed: Int = 0, strength: Int = 100) {
        self.level = level
        self.state = LevelState(level)
        self.rng = LCG(seed: seed)
        self.strength = strength

        var list = [ActorState.prince(from: level.data.prince)]
        for spawn in level.data.guards {
            list.append(ActorState.enemy(from: spawn, levelNumber: level.data.number))
        }
        self.actors = list
    }

    public var prince: ActorState { actors[0] }
    public var enemies: [ActorState] { Array(actors.dropFirst()) }
    public var livingEnemies: [ActorState] { actors.dropFirst().filter(\.isAlive) }

    /// One tick of the interactive tiles. Call once per simulation tick, after the actor has
    /// been stepped.
    public mutating func update() {
        state.update()
    }

    /// The same tick, with the sounds the mechanisms made handed to the caller.
    public mutating func update(effects: inout [ActorEffect], cameraRoom: Int? = nil) {
        // The camera room is the Prince's: a chopper cutting in another room is off screen and
        // therefore silent, which is what `handleChop`'s room test is for.
        state.update(cameraRoom: cameraRoom ?? actors[0].room)
            .forEach { effects.append(.sound($0)) }
    }

    /// `handleChop` — set one specific chopper going.
    ///
    /// The row cascade goes through `activateChopper`; this is the direct call the cascade itself
    /// makes, exposed so a test can start a blade in the middle of a row.
    public mutating func chopChopper(at ref: TileRef, audible: Bool) {
        guard var chopper = state.chopper(at: ref) else { return }
        chopper.chop(audible: audible)
        state.replace(trob: .chopper(chopper), at: ref)
    }

    /// Steps a chopper's cycle forward without any actor present.
    ///
    /// A seam for tests: a cut can only land on steps 1 to 3 of a fifteen-step cycle, so a test
    /// that wants a killing blow has to place the blades on the right step first.
    public mutating func advanceChoppers(to step: Int) {
        for (ref, var trob) in state.trobs {
            guard var chopper = trob.chopper else { continue }
            chopper.chop(audible: false)
            while chopper.step < step { _ = chopper.update() }
            trob = .chopper(chopper)
            state.replace(trob: trob, at: ref)
        }
    }

    /// `Chopper.showBlood` — the stain is left behind even when the actor survives.
    public mutating func markChopperBloody(at ref: TileRef) {
        guard var chopper = state.chopper(at: ref) else { return }
        chopper.showBlood()
        state.replace(trob: .chopper(chopper), at: ref)
    }

    /// `Level.activateChopper` — start the leftmost chopper in a row.
    /// `Level.activateChopper`. Pass `after: -1` for "the leftmost blade in the row", which is
    /// what an actor walking in does.
    public mutating func activateChopper(after column: Int, row: Int, room: Int, cameraRoom: Int) {
        state.activateChopper(after: column, row: row, room: room, cameraRoom: cameraRoom)
    }

    /// The chopper at a position, if there is one.
    public func chopper(at ref: TileRef) -> Chopper? { state.chopper(at: ref) }

    /// Potions waiting for their one-second delay to elapse.
    public private(set) var pendingPotions: [PendingPotion] = []

    /// How long the third potion lasts: 18 s at the 1/12 s tick.
    public static let floatTicks = 216

    /// Queues a potion effect as if one had just been drunk.
    ///
    /// A seam for tests: only five levels contain a non-RECOVER potion, and no single level has
    /// all five, so the effects cannot be exercised end to end from level data alone.
    public mutating func queuePotionForTesting(_ effect: PotionEffect) {
        pendingPotions.append(PendingPotion(effect: effect))
    }

    /// Ages the delayed potions by one tick and hands back the ones that have come due.
    public mutating func advanceDelayedEffects() -> [PotionEffect] {
        var due: [PotionEffect] = []
        for index in pendingPotions.indices {
            pendingPotions[index].ticksRemaining -= 1
            if pendingPotions[index].ticksRemaining <= 0 {
                due.append(pendingPotions[index].effect)
            }
        }
        pendingPotions.removeAll { $0.ticksRemaining <= 0 }
        return due
    }

    /// Ages every actor's float timer. Returns nothing; the flag simply clears.
    public mutating func advanceFloatTimers() {
        for index in actors.indices where actors[index].isInFloat {
            actors[index].floatTicksRemaining -= 1
            if actors[index].floatTicksRemaining <= 0 {
                actors[index].isInFloat = false
                actors[index].floatTicksRemaining = 0
            }
        }
    }

    /// `Spikes.raise` — brings a spike field up and reports the noise it made, if any.
    @discardableResult
    public mutating func raiseSpikes(at ref: TileRef) -> SoundEffect? {
        guard var field = state.spikes(at: ref) else { return nil }
        let sound = field.raise()
        state.replace(trob: .spikes(field), at: ref)
        return sound
    }

    /// The spike field at a position, if there is one.
    public func spikes(at ref: TileRef) -> Spikes? { state.spikes(at: ref) }

    /// `Level.removeObject` — a potion or sword leaves plain floor behind.
    public mutating func removeObject(at ref: TileRef) { state.removeObject(at: ref) }

    /// `Button.push` — the floor-button sound, if a button actually went down.
    public func floorButtonSound(at ref: TileRef) -> SoundEffect? {
        state.floorButtonSound(at: ref)
    }

    @discardableResult
    public mutating func pressButton(at ref: TileRef) -> Bool {
        state.pressButton(at: ref)
    }

    /// Fire a level event by index. `Level.fireEvent`, exposed for tests and for the mechanisms
    /// that will call it directly (potion pickups, loose boards).
    public mutating func fire(_ event: Int, kind: TileKind, stuck: Bool = false) {
        state.fire(event, kind: kind, stuck: stuck)
    }

    /// `Loose.shake(true)` — disturb a board without standing on it.
    public mutating func shakeLooseBoard(at ref: TileRef) {
        state.shakeLooseBoard(at: ref)
    }

    /// Draws from the shared generator.
    public mutating func random(below max: Int) -> Int {
        rng.next(upperBound: max)
    }

    public func gate(at ref: TileRef) -> Gate? { state.gate(at: ref) }
    public func looseBoard(at ref: TileRef) -> LooseBoard? { state.trob(at: ref)?.looseBoard }
    public func exitDoor(at ref: TileRef) -> ExitDoor? { state.trob(at: ref)?.exitDoor }

    /// Apply the effects a behaviour produced against the world.
    public mutating func apply(_ effects: [ActorEffect]) {
        for effect in effects {
            switch effect {
            case let .shookLooseBoard(ref): state.shakeLooseBoard(at: ref)
            case let .maskedExitDoor(ref): state.maskExitDoor(at: ref)
            case let .removedObject(ref): state.removeObject(at: ref)
            case let .pendingPotion(isPrince, effect):
                guard isPrince else { break }
                pendingPotions.append(PendingPotion(
                    effect: effect, ticksRemaining: PendingPotion.delayTicks
                ))
            default: break
            }
        }
    }
    public var isExitDoorOpen: Bool { state.isExitDoorOpen }
    public var gateCount: Int { state.gates.count }
    public var buttonCount: Int { state.buttons.count }
}

extension World: TileWorld {
    public func tile(x: Int, y: Int, room: Int) -> Tile {
        // A board that has fallen is a hole in the floor from now on.
        if let ref = level.resolve(x: x, y: y, room: room),
           let replacement = state.override(at: ref) {
            return replacement
        }
        return level.tile(x: x, y: y, room: room)
    }

    public func resolve(x: Int, y: Int, room: Int) -> TileRef? {
        level.resolve(x: x, y: y, room: room)
    }

    public func roomLinks(_ room: Int) -> RoomLinks? {
        level.roomLinks(room)
    }

    public func gateBlocks(x: Int, y: Int, room: Int) -> Bool {
        state.gateBlocks(x: x, y: y, room: room)
    }

    public func trob(x: Int, y: Int, room: Int) -> Trob? {
        guard let ref = level.resolve(x: x, y: y, room: room) else { return nil }
        return state.trob(at: ref)
    }
}
