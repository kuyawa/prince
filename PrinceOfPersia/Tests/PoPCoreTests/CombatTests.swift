import Testing
@testable import PoPCore

// M6a: sword fighting.
//
// Room 21's top row is [PILLAR, FLOOR, FLOOR, TORCH, FLOOR, TORCH, FLOOR, FLOOR, FLOOR, PILLAR]
// — a clean corridor, and the duel fixture throughout.
//
// The reference's guard AI draws from Phaser's clock-seeded `rnd`, so PrinceJS is not replayable
// here. SDLPoP's `prandom` is the same MSVC LCG already ported for wall patterns, and that is what
// the port uses — open question 2, settled.

private func worldOne() throws -> World {
    World(try LevelRuntime(try GameData.level(1)))
}

/// The Prince, armed and in a stance, at column 4 of room 21.
private func prince() -> ActorState {
    var a = ActorState(location: 4, room: 21, face: 1, action: "engarde", charName: "kid")
    a.charBlockY = 0
    a.charX = CoordinateSpace.x(fromBlockX: 4)
    a.charY = CoordinateSpace.y(fromBlockY: 0)
    a.hasSword = true
    a.swordDrawn = true
    a.health = 3
    a.maxHealth = 3
    return a
}

/// A guard at column 5, facing back.
private func guardFighter(skill: Int = 0) -> ActorState {
    var a = ActorState(location: 5, room: 21, face: -1, action: "engarde", charName: "guard-3")
    a.baseCharName = "guard"
    a.charBlockY = 0
    a.charX = CoordinateSpace.x(fromBlockX: 5)
    a.charY = CoordinateSpace.y(fromBlockY: 0)
    a.hasSword = true
    a.swordDrawn = true
    a.charSkill = skill
    a.health = GuardBrain.health(skill: skill, levelNumber: 1)
    return a
}

// MARK: - The probability tables

@Test func theGuardTablesAreTranscribedVerbatim() {
    // Enemy.js. The twelve columns are the twelve difficulty levels; the values are hand-tuned
    // and there is nothing here to "improve".
    #expect(GuardBrain.strikeProbability == [61, 100, 61, 61, 61, 40, 100, 150, 0, 48, 32, 48])
    #expect(GuardBrain.restrikeProbability == [0, 0, 0, 5, 5, 175, 16, 8, 0, 255, 255, 150])
    #expect(GuardBrain.blockProbability == [0, 150, 150, 200, 200, 255, 200, 250, 0, 255, 255, 255])
    #expect(GuardBrain.impairBlockProbability == [0, 61, 61, 100, 100, 145, 100, 250, 0, 145, 255, 175])
    #expect(GuardBrain.advanceProbability == [255, 200, 200, 200, 255, 255, 200, 0, 0, 255, 100, 100])
    #expect(GuardBrain.refracTimerTable == [16, 16, 16, 16, 8, 8, 8, 8, 0, 8, 0, 0])
    #expect(GuardBrain.levelStrength == [4, 3, 3, 3, 3, 4, 5, 4, 4, 5, 5, 5, 4, 6, 10, 0])
    // Every table must cover every skill, or a lookup would silently read zero.
    for table in [GuardBrain.strikeProbability, GuardBrain.restrikeProbability,
                  GuardBrain.blockProbability, GuardBrain.impairBlockProbability,
                  GuardBrain.advanceProbability, GuardBrain.refracTimerTable] {
        #expect(table.count == 12)
    }
}

@Test func guardHealthCombinesSkillAndLevel() {
    // Enemy: `EXTRA_STRENGTH[skill] + STRENGTH[level.number]`.
    #expect(GuardBrain.health(skill: 0, levelNumber: 1) == 3)
    #expect(GuardBrain.health(skill: 4, levelNumber: 1) == 4, "skill 4 carries an extra point")
    #expect(GuardBrain.health(skill: 0, levelNumber: 14) == 10)
}

@Test func theStrengthSettingScalesEveryProbability() {
    // `Utils.applyStrength` — the player's difficulty. `ceil`, not round.
    #expect(GuardBrain.applyStrength(61, strength: 100) == 61)
    #expect(GuardBrain.applyStrength(61, strength: 50) == 31, "ceil(30.5)")
    #expect(GuardBrain.applyStrength(100, strength: 1) == 1)
    #expect(GuardBrain.applyStrength(1, strength: 1) == 1)
}

// MARK: - Distance

@Test func opponentDistanceIsSignedAndForwardPositive() throws {
    let world = try worldOne()
    var prince = prince()
    var foe = guardFighter()
    prince.charFdx = 0
    foe.charFdx = 0

    // Fourteen x-units apart (one tile), facing each other, plus the reference's 13-pixel
    // allowance for two bodies between the origins.
    #expect(Combat.opponentDistance(prince, foe, world: world) == 27)
    // Facing the same way, the allowance does not apply.
    foe.charFace = 1
    #expect(Combat.opponentDistance(prince, foe, world: world) == 14)
}

@Test func opponentDistanceIsNegativeBehindAnd999WhenUnreachable() throws {
    let world = try worldOne()
    var prince = prince()
    var foe = guardFighter()
    prince.charFdx = 0
    foe.charFdx = 0

    // Put the guard behind him.
    foe.charX = CoordinateSpace.x(fromBlockX: 3)
    #expect(Combat.opponentDistance(prince, foe, world: world) < 0)

    // A different row is out of reach entirely.
    foe.charBlockY = 1
    #expect(abs(Combat.opponentDistance(prince, foe, world: world)) == 999)
}

// MARK: - Striking

@Test func aStrikeOnTheRightFrameAtTheRightDistanceStabs() throws {
    let world = try worldOne()
    var prince = prince()
    var foe = guardFighter()

    // `checkFight` only resolves a strike on frames 153-154 or 3-4, and only lands the blow
    // on 154 or 4.
    prince.action = "strike"
    prince.charFrame = 154
    foe.action = "engarde"
    foe.charFrame = 161          // neither 150 nor 0, so the parry branch is skipped

    let before = foe.health
    var effects: [ActorEffect] = []
    Combat.checkFight(&prince, &foe, world: world, effects: &effects)

    #expect(foe.health == before - 1)
    #expect(foe.action == "stabbed")
    #expect(!foe.isAlive == false, "still standing at one health lost from three")
}

@Test func aStrikeOnTheWrongFrameDoesNothing() throws {
    let world = try worldOne()
    var prince = prince()
    var foe = guardFighter()

    prince.action = "strike"
    prince.charFrame = 100       // no strike frame
    foe.action = "engarde"
    foe.charFrame = 161

    var effects: [ActorEffect] = []
    Combat.checkFight(&prince, &foe, world: world, effects: &effects)
    #expect(foe.health == 3, "the animation decides, not the keypress")
}

@Test func aStrikeThatMeetsAWindUpIsParried() throws {
    let world = try worldOne()
    var prince = prince()
    var foe = guardFighter()

    prince.action = "strike"
    prince.charFrame = 154
    foe.action = "engarde"
    foe.charFrame = 150          // mid-strike: steel rings, nobody bleeds

    var effects: [ActorEffect] = []
    Combat.checkFight(&prince, &foe, world: world, effects: &effects)

    #expect(foe.health == 3)
    #expect(foe.blocked, "the parry is recorded on the defender")
    #expect(prince.action == "blockedstrike")
}

@Test func anUnarmedPrinceDiesFromOneBlow() throws {
    // `stab`: a Kid without his sword drawn does not take a wound, he takes the lot.
    let world = try worldOne()
    var unarmed = prince()
    unarmed.swordDrawn = false

    var effects: [ActorEffect] = []
    Combat.stab(&unarmed, effects: &effects)

    #expect(!unarmed.isAlive)
    #expect(unarmed.action == "stabkill")
    #expect(effects.contains(.died))
    _ = world
}

@Test func losingAllHealthIsFatal() throws {
    var foe = guardFighter()
    foe.health = 1
    var effects: [ActorEffect] = []
    Combat.stab(&foe, effects: &effects)
    #expect(foe.health == 0)
    #expect(!foe.isAlive)
    #expect(foe.action == "stabkill")
}

// MARK: - The guard's mind

@Test func aGuardEngagesOnlyWhenItHasNoticedThePrince() throws {
    var world = try worldOne()
    var foe = guardFighter()
    var hero = prince()

    // Out of range and in another room: nothing happens.
    foe.room = 22
    foe.hasStartedFight = false
    var rng = LCG(seed: 1)
    var fx: [ActorEffect] = []
    GuardBrain.update(&foe, opponent: hero, world: world, strength: 100, rng: &rng, effects: &fx)
    #expect(!foe.hasStartedFight)

    // In the same room, it wakes up.
    foe.room = 21
    GuardBrain.update(&foe, opponent: hero, world: world, strength: 100, rng: &rng, effects: &fx)
    #expect(foe.hasStartedFight)
}

@Test func theGuardBrainIsReproducibleFromItsSeed() throws {
    // The reference draws from a clock-seeded generator and cannot be replayed. SDLPoP's
    // `prandom` is the same LCG already used for wall patterns, and makes this possible.
    func run(seed: Int) throws -> (actions: [String], state: UInt32) {
        var world = try worldOne()
        var foe = guardFighter()
        var hero = prince()
        var rng = LCG(seed: seed)
        var actions: [String] = []
        var fx: [ActorEffect] = []
        for _ in 0..<60 {
            GuardBrain.update(
                &foe, opponent: hero, world: world, strength: 100, rng: &rng, effects: &fx
            )
            actions.append(foe.action)
        }
        return (actions, rng.state)
    }

    let first = try run(seed: 7)
    let again = try run(seed: 7)
    #expect(first.actions == again.actions)
    #expect(first.state == again.state)

    // And a different seed consumes the generator differently.
    let other = try run(seed: 8)
    #expect(other.state != first.state)
}

@Test func aSneakingPrinceDoesNotWakeAGuard() throws {
    var world = try worldOne()
    var foe = guardFighter()
    var hero = prince()
    hero.action = "stoop"        // one of the quietly-moving actions
    foe.hasStartedFight = false
    foe.sneakUp = true
    foe.swordDrawn = false
    // Facing AWAY: `sneakUp` only suppresses engagement when the guard is not already looking
    // at the Prince.
    foe.charFace = 1
    #expect(!Combat.facingOpponent(foe, hero))

    var rng = LCG(seed: 3)
    var fx: [ActorEffect] = []
    GuardBrain.update(&foe, opponent: hero, world: world, strength: 100, rng: &rng, effects: &fx)
    // It has noticed — they are in the same room — but must not draw.
    #expect(foe.hasStartedFight)
    #expect(!foe.swordDrawn, "it will not engage a crouching Prince it is not facing")

    // Facing him, it does draw.
    foe.charFace = -1
    GuardBrain.update(&foe, opponent: hero, world: world, strength: 100, rng: &rng, effects: &fx)
    #expect(foe.swordDrawn)
}

@Test func aGuardAtZeroStrengthNeverBlocks() {
    // Skill 0 has zero block and restrike probabilities, so the arithmetic can never trigger.
    #expect(GuardBrain.blockProbability[0] == 0)
    #expect(GuardBrain.restrikeProbability[0] == 0)
    #expect(GuardBrain.applyStrength(0, strength: 100) == 0)
}

// MARK: - Verbs are frame-gated

@Test func aStrikeIsOnlyLegalOnSixFrameWindows() {
    var state = prince()
    state.action = "engarde"

    var fx: [ActorEffect] = []

    // Off-frame: nothing.
    state.charFrame = 100
    Combat.strike(&state, guardFighter(), effects: &fx)
    #expect(state.action == "engarde")

    // On-frame: the strike begins.
    state.charFrame = 157
    Combat.strike(&state, guardFighter(), effects: &fx)
    #expect(state.action == "strike")

    // From a neutral frame it becomes a wind-up instead.
    state.action = "engarde"
    state.charFrame = 150
    Combat.strike(&state, guardFighter(), effects: &fx)
    #expect(state.action == "blocktostrike")
}

@Test func engardeNeedsASwordAndClearGround() throws {
    let world = try worldOne()
    var fx: [ActorEffect] = []
    var unarmed = prince()
    unarmed.hasSword = false
    #expect(!Combat.engarde(&unarmed, world: world, effects: &fx))

    var armed = prince()
    armed.action = "stand"
    armed.swordDrawn = false
    #expect(Combat.engarde(&armed, world: world, effects: &fx))
    #expect(armed.swordDrawn)
    #expect(armed.action == "engarde")
}
