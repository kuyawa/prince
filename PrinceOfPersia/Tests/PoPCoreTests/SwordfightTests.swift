import Testing
@testable import PoPCore

// The Prince's half of a swordfight.
//
// `CombatTests` covers `Fighter`'s shared verbs and the guard's mind — the half that was ported.
// This file covers what `Kid` overrides: the stance he takes up **without being asked**, the parry
// window that is not the guard's, and the flight. That half was missing entirely, and the symptom
// was reported as "the prince doesn't fight with the guard, the sword is never used, pressing shift
// does nothing and the guard kills the prince every time".

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

/// The Prince and level 1's own guard, in room 21's clean top-row corridor.
///
/// Room 21 is the level's guard room and its top row is `[PILLAR, FLOOR, FLOOR, TORCH, FLOOR,
/// TORCH, FLOOR, FLOOR, FLOOR, PILLAR]`. The guard is already at column 7 and needs no moving;
/// only the Prince is placed.
private func duel(princeHasSword: Bool = true, princeColumn: Int = 4) throws -> Simulation {
    var sim = try Simulation(level: try levelOne(), seed: 1)
    var prince = sim.world.actors[0]
    prince.room = 21
    prince.charBlockY = 0
    prince.charBlockX = princeColumn
    prince.charX = CoordinateSpace.x(fromBlockX: princeColumn)
    prince.charY = CoordinateSpace.y(fromBlockY: 0)
    prince.action = "stand"
    prince.charFace = 1
    prince.hasSword = princeHasSword
    sim.world.actors[0] = prince
    return sim
}

/// A world with nothing in it but the corridor, for driving `Behaviour` directly.
private func corridor() throws -> World { World(try levelOne()) }

private func princeInTheCorridor(column: Int = 4) -> ActorState {
    var a = ActorState(location: column, room: 21, face: 1, action: "stand", charName: "kid")
    a.charBlockY = 0
    a.charX = CoordinateSpace.x(fromBlockX: column)
    a.charY = CoordinateSpace.y(fromBlockY: 0)
    a.hasSword = true
    a.health = 3
    a.maxHealth = 3
    return a
}

private func guardInTheCorridor(column: Int = 5) -> ActorState {
    var a = ActorState(location: column, room: 21, face: -1, action: "engarde", charName: "guard-3")
    a.baseCharName = "guard"
    a.charBlockY = 0
    a.charX = CoordinateSpace.x(fromBlockX: column)
    a.charY = CoordinateSpace.y(fromBlockY: 0)
    a.hasSword = true
    a.swordDrawn = true
    a.health = 3
    return a
}

// MARK: - The sword he is carrying

@Test func levelOneStartsWithThePrinceEmptyHanded() throws {
    // `Kid`'s constructor is `this.hasSword = PrinceJS.currentLevel > 1`, and `Game.js` only
    // overwrites it when the level carries a boolean — which **no shipped level does**. Reading the
    // absent key as `true` was invisible while he could not draw a sword at all; with the stance
    // wired it would have had him fight the first guard with a sword he had never picked up.
    #expect(!World(try levelOne()).actors[0].hasSword, "level one arms him through `gotSword`")
    #expect(World(try LevelRuntime(try GameData.level(2))).actors[0].hasSword)
}

// MARK: - The entry

@Test func thePrinceDrawsHisSwordWithoutBeingAsked() throws {
    // The heart of the report. `stand` asks `tryEngarde` **before** it looks at a movement key,
    // and nothing about the call is a key press: walking into reach of a guard he is facing is
    // enough. Shift is the strike, so a missing entry reads as "the sword is never used".
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    var foeSlot: ActorState? = guardInTheCorridor(column: 5)
    let foe = guardInTheCorridor(column: 5)
    var effects: [ActorEffect] = []

    try Behaviour.update(
        &hero, intents: .none, world: world, interpreter: makeKidInterpreter(),
        opponent: &foeSlot, effects: &effects
    )

    #expect(hero.action == "engarde")
    #expect(hero.swordDrawn)
    #expect(effects.contains(.sound(.unsheatheSword)), "and it is audible: \(effects)")
    _ = world
}

@Test func aPrinceWithoutASwordCannotDrawOne() throws {
    var sim = try duel(princeHasSword: false)
    sim.run(3, intents: [.action])
    #expect(sim.world.actors[0].action != "engarde")
    #expect(!sim.world.actors[0].swordDrawn)
}

@Test func aPrinceWhoLandedInAHeapDoesNotStandUpIntoAStance() throws {
    // `blockEngarde` is set by `Kid.land` on the no-sword branch, and `tryEngarde` refuses while
    // it is set. `stand` clears it first, which is why a `stand` action is the way back in.
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    var foeSlot: ActorState? = guardInTheCorridor(column: 5)
    let foe = guardInTheCorridor(column: 5)
    var effects: [ActorEffect] = []

    hero.blockEngarde = true
    #expect(!Combat.tryEngarde(&hero, foe, world: world, effects: &effects))
    #expect(hero.action == "stand")

    hero.blockEngarde = false
    #expect(Combat.tryEngarde(&hero, foe, world: world, effects: &effects))
    _ = world
}

@Test func aGuardHeCannotReachDoesNotCallTheSwordOut() throws {
    // Reach is not distance: `canReachOpponent` walks the tiles between them, so a guard in
    // another room, or behind a wall, is not an opponent yet.
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    var away = guardInTheCorridor(column: 5)
    away.room = 22
    var foeSlot: ActorState? = away
    var effects: [ActorEffect] = []

    try Behaviour.update(
        &hero, intents: .none, world: world, interpreter: makeKidInterpreter(),
        opponent: &foeSlot, effects: &effects
    )
    #expect(hero.action == "stand")
    #expect(!hero.swordDrawn)
    _ = world
}

@Test func aFleeingPrinceHasToAskForTheNextFight() throws {
    // `flee` is what `fastsheathe` buys. While it is set the entry needs the action key, which is
    // the reference's second `tryEngarde` block.
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    var foeSlot: ActorState? = guardInTheCorridor(column: 5)
    let foe = guardInTheCorridor(column: 5)
    var effects: [ActorEffect] = []

    hero.flee = true
    try Behaviour.update(
        &hero, intents: .none, world: world, interpreter: makeKidInterpreter(),
        opponent: &foeSlot, effects: &effects
    )
    #expect(hero.action == "stand", "he is not talked back into it")

    try Behaviour.update(
        &hero, intents: [.action], world: world, interpreter: makeKidInterpreter(),
        opponent: &foeSlot, effects: &effects
    )
    #expect(hero.action == "engarde", "the action key is the way back in")
    #expect(!hero.flee)
    _ = world
}

@Test func turningTowardAnOpponentIsTheDraw() throws {
    // `Kid.turn` is an override, not `Fighter.turn`: an armed Prince who turns toward someone he
    // can reach plays `turndraw`, and the turn *is* the draw. `canReachOpponent(turn: true)` is
    // what makes an opponent behind him reachable at all.
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    let behind = guardInTheCorridor(column: 3)
    var foeSlot: ActorState? = behind
    var effects: [ActorEffect] = []

    try Behaviour.update(
        &hero, intents: [.left], world: world, interpreter: makeKidInterpreter(),
        opponent: &foeSlot, effects: &effects
    )

    #expect(hero.action == "turndraw", "not a plain turn")
    #expect(hero.swordDrawn)
    #expect(effects.contains(.sound(.unsheatheSword)))
    _ = world
}

@Test func anUnarmedPrinceJustTurns() throws {
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    hero.hasSword = false
    let behind = guardInTheCorridor(column: 3)
    var foeSlot: ActorState? = behind
    var effects: [ActorEffect] = []

    try Behaviour.update(
        &hero, intents: [.left], world: world, interpreter: makeKidInterpreter(),
        opponent: &foeSlot, effects: &effects
    )

    #expect(hero.action == "turn")
    #expect(!hero.swordDrawn)
    _ = world
}

// MARK: - The arms

@Test func theActionKeyStrikesButOnlyOnTheReferenceSFrames() throws {
    // The animation *is* the state machine. A strike is legal on 157-158, 165, 170-171, 7-8,
    // 20-21 or 15, and on no other frame at all.
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    var foeSlot: ActorState? = guardInTheCorridor(column: 5)
    let foe = guardInTheCorridor(column: 5)
    hero.action = "engarde"
    var effects: [ActorEffect] = []

    for frame in [157, 158, 165, 170, 171, 7, 8, 20, 21, 15] {
        hero.action = "engarde"
        hero.charFrame = frame
        hero.allowStrike = true
        Combat.strike(&hero, foe, effects: &effects)
        #expect(hero.action == "strike", "frame \(frame) is a strike frame")
        #expect(!hero.allowStrike, "and it consumes the key")
    }

    hero.action = "engarde"
    hero.charFrame = 100
    hero.allowStrike = true
    Combat.strike(&hero, foe, effects: &effects)
    #expect(hero.action == "engarde")
    #expect(hero.allowStrike, "a press one frame early is carried, not swallowed")
    _ = world
}

@Test func shiftInTheStanceReachesTheStrikeVerb() throws {
    // The dispatch, not the verb: `engarde` + the action key is `Combat.strike`, and the frame
    // gate is what decides whether anything happens.
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    var foeSlot: ActorState? = guardInTheCorridor(column: 5)
    let foe = guardInTheCorridor(column: 5)
    hero.action = "engarde"
    hero.charFrame = 157
    var effects: [ActorEffect] = []

    try Behaviour.update(
        &hero, intents: [.action], world: world, interpreter: makeKidInterpreter(),
        opponent: &foeSlot, effects: &effects
    )
    #expect(hero.action == "strike")
    _ = world
}

@Test func thePrincesParryWindowIsNotTheGuards() throws {
    // `Kid.block` overrides `Fighter.block` and disagrees with it on **every** frame number: the
    // Prince parries on 158, 165 and 167, the guard on 8, 20, 21, 18, 15 and 17.
    let world = try corridor()
    var foeSlot: ActorState? = guardInTheCorridor(column: 5)
    let foe = guardInTheCorridor(column: 5)
    var hero = princeInTheCorridor(column: 4)
    var theirMove = foe
    theirMove.charFrame = 161        // neither 18 nor 3

    hero.action = "engarde"
    hero.charFrame = 158
    hero.allowBlock = true
    _ = Combat.kidBlock(&hero, theirMove)
    #expect(hero.action == "block")
    #expect(!hero.allowBlock)

    // 165 does the same, and 167 is the late parry.
    hero.action = "engarde"
    hero.charFrame = 165
    Combat.kidBlock(&hero, theirMove)
    #expect(hero.action == "block")

    hero.action = "engarde"
    hero.charFrame = 167
    Combat.kidBlock(&hero, theirMove)
    #expect(hero.action == "striketoblock")

    // On the guard's own block frames the Prince does nothing — and, importantly, does not
    // swallow the key, so a press a frame early is carried.
    hero.action = "engarde"
    hero.charFrame = 8
    hero.allowBlock = true
    #expect(!Combat.kidBlock(&hero, theirMove))
    #expect(hero.action == "engarde")
    #expect(hero.allowBlock)

    // Frame 18 of the opponent's own swing is the one frame the Prince cannot parry from, and
    // the refusal leaves the key alone — the reference returns before `allowBlock = false`.
    hero.action = "engarde"
    hero.charFrame = 158
    hero.allowBlock = true
    var refusing = foe
    refusing.charFrame = 18
    #expect(!Combat.kidBlock(&hero, refusing))
    #expect(hero.action == "engarde")
    #expect(hero.allowBlock)
    _ = world
}

@Test func theSequenceRunsInsideTheParryWhenTheStabIsLanding() throws {
    // `Kid.block`'s `processCommand()`, which is the only verb in either half that runs the
    // sequence from inside itself. It is *asked for* rather than done, because the interpreter
    // belongs to `Behaviour`.
    var world = try corridor()
    var hero = princeInTheCorridor(column: 4)
    var foe = guardInTheCorridor(column: 5)
    foe.charFrame = 3

    hero.action = "engarde"
    hero.charFrame = 158
    hero.allowBlock = true
    #expect(Combat.kidBlock(&hero, foe))
    _ = world
}

@Test func downInTheStanceSheathesAndHoldsTheGuardOff() throws {
    // `Kid.fastsheathe` is the one verb that reaches into the opponent, which is why
    // `Behaviour.update` takes it `inout`.
    var sim = try duel()
    sim.run(2, intents: .none)
    #expect(sim.world.actors[0].action == "engarde")

    sim.tick(intents: [.down])

    let prince = sim.world.actors[0]
    #expect(prince.action == "fastsheathe")
    #expect(!prince.swordDrawn)
    #expect(prince.flee)
    #expect(sim.world.actors[1].refracTimer == 9)
}

// MARK: - The whole duel

@Test func thePrincesSwordTakesHealthOffTheGuard() throws {
    // The report, end to end and against the real level: the Prince stands in room 21 with the
    // guard, draws, and Shift draws blood. The guard is the one who ends the fight in the bug
    // report; here it is the other way round.
    var sim = try duel()
    sim.run(2, intents: .none)
    #expect(sim.world.actors[0].action == "engarde", "he drew it on his own")

    var wounded = false
    for _ in 0..<60 {
        sim.tick(intents: [.action])
        if sim.world.actors[1].health < 3 { wounded = true; break }
    }
    #expect(wounded, "Shift is the strike, and the strike lands")
}

@Test func killingTheGuardPutsThePrincesSwordAway() throws {
    // The reason the opponent is sticky state rather than a fresh lookup. A query that only ever
    // returns a *living* guard stops `checkFight` running on exactly the tick that sheathes the
    // Prince's sword, and he is then left standing in his stance for ever — sword out, unable to
    // walk, strike, stoop or pick anything up.
    var sim = try duel()
    sim.run(2, intents: .none)
    sim.world.actors[1].health = 1

    var killed = false
    for _ in 0..<80 {
        sim.tick(intents: [.action])
        if !sim.world.actors[1].isAlive { killed = true; break }
    }
    #expect(killed, "the Prince can win")

    sim.run(4, intents: .none)
    #expect(!sim.world.actors[0].swordDrawn, "the sword goes away when the fight does")
    #expect(sim.opponentIndex(for: 0) == nil, "and the fight is released")

    // Free again: back to a plain stand, and the stance is not a trap.
    sim.run(40, intents: .none)
    #expect(sim.world.actors[0].action == "stand")
}

@Test func theOpponentIsSettledByTheTickAndStaysPut() throws {
    // `Game.checkForOpponent`: four passes, first hit wins, and it only ever *assigns* — which is
    // what makes the opponent outlive the guard who was it.
    var sim = try duel()
    #expect(sim.opponentIndex(for: 0) == nil, "nothing is settled before a tick")

    sim.tick(intents: .none)
    #expect(sim.opponentIndex(for: 0) == 1)

    // A dead guard is still the opponent until `checkFight` has sheathed the sword over him.
    sim.world.actors[1].health = 1
    sim.world.actors[0].action = "engarde"
    var fx: [ActorEffect] = []
    Combat.stab(&sim.world.actors[1], effects: &fx)
    #expect(!sim.world.actors[1].isAlive)

    // The tick *after* the kill still runs `checkFight` against him, which is what sheathes the
    // sword; a living-only query would have dropped him here and never noticed.
    sim.tick(intents: .none)
    #expect(sim.opponentIndex(for: 0) == nil, "and then it is released")
}
