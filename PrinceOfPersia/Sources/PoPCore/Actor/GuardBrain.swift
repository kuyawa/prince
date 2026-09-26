/// The guard's mind.
///
/// Port source: `reference/PrinceJS/src/Enemy.js#updateBehaviour` and the decision helpers
/// around it.
///
/// ## It is a probability table, not a strategy
///
/// Every choice is a fixed threshold compared against a random number:
///
/// ```js
/// if (this.strikeProbability > this.game.rnd.between(0, 254)) { this.strike(); }
/// ```
///
/// The twelve columns are the twelve difficulty levels the level editor exposes, and the values
/// are hand-tuned. They are transcribed verbatim; there is nothing here to "improve".
///
/// ## The generator
///
/// The reference draws from Phaser's `rnd`, seeded from the clock — so PrinceJS is **not
/// replayable** at this point. SDLPoP's `prandom` is:
///
/// ```c
/// word prandom(word max) {
///   random_seed = random_seed * 214013 + 2531011;
///   return (random_seed >> 16) % (max + 1);
/// }
/// ```
///
/// the same MSVC linear congruential generator already ported for wall patterns. Using it here
/// makes guard behaviour reproducible from a seed, which the port source cannot offer. That is
/// ARCHITECTURE.md open question 2, settled in favour of SDLPoP.
public enum GuardBrain {
    /// `Enemy.STRIKE_PROBABILITY`, indexed by skill.
    public static let strikeProbability = [61, 100, 61, 61, 61, 40, 100, 150, 0, 48, 32, 48]
    /// `Enemy.RESTRIKE_PROBABILITY`.
    public static let restrikeProbability = [0, 0, 0, 5, 5, 175, 16, 8, 0, 255, 255, 150]
    /// `Enemy.BLOCK_PROBABILITY`.
    public static let blockProbability = [0, 150, 150, 200, 200, 255, 200, 250, 0, 255, 255, 255]
    /// `Enemy.IMPAIRBLOCK_PROBABILITY`.
    public static let impairBlockProbability = [0, 61, 61, 100, 100, 145, 100, 250, 0, 145, 255, 175]
    /// `Enemy.ADVANCE_PROBABILITY`.
    public static let advanceProbability = [255, 200, 200, 200, 255, 255, 200, 0, 0, 255, 100, 100]
    /// `Enemy.REFRAC_TIMER`.
    public static let refracTimerTable = [16, 16, 16, 16, 8, 8, 8, 8, 0, 8, 0, 0]
    /// `Enemy.EXTRA_STRENGTH`, added to the level's strength.
    public static let extraStrength = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    /// `Enemy.STRENGTH`, indexed by **level number**, not skill.
    public static let levelStrength = [4, 3, 3, 3, 3, 4, 5, 4, 4, 5, 5, 5, 4, 6, 10, 0]

    /// The distance bands a guard keeps. Straight from the reference.
    public static let tooFar = 35
    public static let tooClose = 12
    public static let turnAt = -20

    /// `Enemy.resetBlockTimer` / `resetStrikeTimer`.
    public static let blockTimerReset = 4
    public static let strikeTimerReset = 15

    /// `Utils.applyStrength` — the player's chosen difficulty scales every probability.
    public static func applyStrength(_ value: Int, strength: Int) -> Int {
        guard strength >= 0, strength < 100 else { return value }
        return Int((Double(value * strength) / 100).rounded(.up))
    }

    /// `Enemy` constructor's health line.
    public static func health(skill: Int, levelNumber: Int) -> Int {
        let extra = extraStrength.indices.contains(skill) ? extraStrength[skill] : 0
        let base = levelStrength.indices.contains(levelNumber) ? levelStrength[levelNumber] : 0
        return extra + base
    }

    /// `Enemy.updateBehaviour`.
    ///
    /// Every decision consumes exactly as many draws from `rng` as the reference does, so a seed
    /// reproduces a whole fight.
    public static func update(
        _ g: inout ActorState,
        opponent: ActorState,
        world: any TileWorld,
        strength: Int,
        rng: inout LCG
    ) {
        guard g.isAlive, opponent.isAlive else { return }

        if willStartFight(g, opponent, world: world) { g.hasStartedFight = true }
        guard g.hasStartedFight else { return }

        if g.refracTimer > 0 { g.refracTimer -= 1 }
        if g.blockTimer > 0 { g.blockTimer -= 1 }
        if g.strikeTimer > 0 { g.strikeTimer -= 1 }

        // A guard already losing the exchange does not think about the next one.
        if ["stabbed", "stabkill", "dropdead", "stepfall"].contains(g.action) { return }

        let distance = Combat.opponentDistance(g, opponent, world: world)
        if distance == -999 { return }

        if g.swordDrawn {
            if distance >= tooFar {
                oppTooFar(&g, opponent: opponent, world: world, rng: &rng, strength: strength)
            } else if distance < turnAt {
                Combat.turnengarde(&g, opponent)
            } else if distance < tooClose {
                oppTooClose(&g, opponent: opponent, world: world)
            } else {
                oppInRange(&g, opponent: opponent, world: world, rng: &rng, strength: strength)
            }
        } else if Combat.canReachOpponent(g, opponent, world: world, below: g.lookBelow)
                    || Combat.canSeeOpponent(g, opponent, world: world, below: g.lookBelow) {
            if !g.sneakUp || Combat.facingOpponent(g, opponent) {
                Combat.engarde(&g, world: world)
            }
        }
    }

    /// `Enemy.willStartFight`.
    public static func willStartFight(
        _ g: ActorState, _ o: ActorState, world: any TileWorld
    ) -> Bool {
        g.isActive && !g.hasStartedFight
            && (opponentCloseRoom(g, o, world: world)
                || abs(Combat.opponentDistance(g, o, world: world)) < 35)
    }

    /// `Enemy.opponentCloseRoom` — the same room, or within a column of the boundary.
    public static func opponentCloseRoom(
        _ f: ActorState, _ o: ActorState, world: any TileWorld
    ) -> Bool {
        if Combat.inSameRoom(f, o) { return true }
        if let links = world.roomLinks(f.room) {
            if links.left > 0, o.room == links.left, o.charBlockX >= Geometry.roomColumns - 1 {
                return true
            }
            if links.right > 0, o.room == links.right, f.charBlockX >= Geometry.roomColumns - 1 {
                return true
            }
        }
        return false
    }

    // MARK: - Decisions

    static func oppTooFar(
        _ g: inout ActorState, opponent: ActorState, world: any TileWorld,
        rng: inout LCG, strength: Int
    ) {
        if g.refracTimer != 0 { return }
        let distance = Combat.opponentDistance(g, opponent, world: world)
        if opponent.action == "running", distance < 40 { return Combat.strike(&g, opponent) }
        if opponent.action == "runjump", distance < 50 { return Combat.strike(&g, opponent) }
        enemyAdvance(&g, opponent: opponent, world: world)
    }

    static func oppTooClose(_ g: inout ActorState, opponent: ActorState, world: any TileWorld) {
        if g.charFace == opponent.charFace
            || !["engarde", "advance", "retreat"].contains(opponent.action) {
            enemyRetreat(&g, opponent: opponent, world: world)
        } else {
            enemyAdvance(&g, opponent: opponent, world: world)
        }
    }

    static func oppInRange(
        _ g: inout ActorState, opponent: ActorState, world: any TileWorld,
        rng: inout LCG, strength: Int
    ) {
        let distance = Combat.opponentDistance(g, opponent, world: world)
        if !opponent.swordDrawn {
            guard g.refracTimer == 0 else { return }
            if distance <= 25 { Combat.strike(&g, opponent) }
            else { enemyAdvance(&g, opponent: opponent, world: world) }
        } else {
            oppInRangeArmed(&g, opponent: opponent, world: world, rng: &rng, strength: strength)
        }
    }

    static func oppInRangeArmed(
        _ g: inout ActorState, opponent: ActorState, world: any TileWorld,
        rng: inout LCG, strength: Int
    ) {
        guard Combat.onSameLevel(g, opponent) else { return }
        let distance = Combat.opponentDistance(g, opponent, world: world)

        if distance < 10 || distance >= 28 {
            tryAdvance(&g, opponent: opponent, world: world, rng: &rng, strength: strength)
            return
        }

        tryBlock(&g, opponent: opponent, world: world, rng: &rng, strength: strength)
        guard g.refracTimer == 0 else { return }
        if distance < 12 {
            tryAdvance(&g, opponent: opponent, world: world, rng: &rng, strength: strength)
        } else {
            tryStrike(&g, opponent: opponent, rng: &rng, strength: strength)
        }
    }

    static func tryAdvance(
        _ g: inout ActorState, opponent: ActorState, world: any TileWorld,
        rng: inout LCG, strength: Int
    ) {
        if g.charSkill == 0 || g.strikeTimer == 0 {
            let probability = applyStrength(
                advanceProbability.indices.contains(g.charSkill)
                    ? advanceProbability[g.charSkill] : 0,
                strength: strength
            )
            if probability > rng.next(upperBound: 254) {
                enemyAdvance(&g, opponent: opponent, world: world)
            }
        }
    }

    /// `Enemy.tryBlock`. The four frame checks mean a guard only guards when the Prince is
    /// visibly winding up.
    static func tryBlock(
        _ g: inout ActorState, opponent: ActorState, world: any TileWorld,
        rng: inout LCG, strength: Int
    ) {
        guard opponent.frameID(152, 153) || opponent.frameID(162)
                || opponent.frameID(2, 3) || opponent.frameID(12)
        else { return }

        let table = g.blockTimer != 0 ? impairBlockProbability : blockProbability
        let probability = applyStrength(
            table.indices.contains(g.charSkill) ? table[g.charSkill] : 0, strength: strength
        )
        if probability > rng.next(upperBound: 254) {
            Combat.block(&g, opponent, world: world)
        }
    }

    static func tryStrike(
        _ g: inout ActorState, opponent: ActorState, rng: inout LCG, strength: Int
    ) {
        if opponent.frameID(169) || opponent.frameID(151)
            || opponent.frameID(19) || opponent.frameID(1) { return }

        let table = g.frameID(150) ? restrikeProbability : strikeProbability
        let probability = applyStrength(
            table.indices.contains(g.charSkill) ? table[g.charSkill] : 0, strength: strength
        )
        if probability > rng.next(upperBound: 254) {
            Combat.strike(&g, opponent)
        }
    }

    /// `Enemy.enemyAdvance` — a guard only advances onto ground it can stand on.
    static func enemyAdvance(_ g: inout ActorState, opponent: ActorState, world: any TileWorld) {
        guard g.hasStartedFight else { return }

        if !Combat.canReachOpponent(g, opponent, world: world, below: g.lookBelow),
           !Combat.canSeeOpponent(g, opponent, world: world, below: g.lookBelow) {
            g.swordDrawn = false
            g.beginAction("stand")
            return
        }

        let here = world.tile(x: g.charBlockX, y: g.charBlockY, room: g.room)
        if here.kind.isSpace, !["advance", "retreat", "strike"].contains(g.action) {
            g.beginAction("stepfall")
            return
        }

        if canWalkSafely(g, x: g.charBlockX + g.charFace, y: g.charBlockY,
                         world: world, below: true) {
            Combat.advance(&g)
        } else if canWalkSafely(g, x: g.charBlockX - g.charFace, y: g.charBlockY, world: world) {
            Combat.retreat(&g)
        }
    }

    /// `Enemy.retreat`.
    static func enemyRetreat(_ g: inout ActorState, opponent: ActorState, world: any TileWorld) {
        guard Combat.canReachOpponent(g, opponent, world: world, below: g.lookBelow) else { return }
        guard !Behaviour.nearBarrier(g, world: world, walk: true) else { return }

        if canWalkSafely(g, x: g.charBlockX - g.charFace, y: g.charBlockY, world: world) {
            Combat.retreat(&g)
        }
    }

    /// `Enemy.canWalkSafely`.
    ///
    /// Takes coordinates rather than a `Tile`, because the port's `Tile` is a value without the
    /// room position the reference's sprite objects carry.
    static func canWalkSafely(
        _ g: ActorState, x: Int, y: Int, world: any TileWorld, below: Bool = false
    ) -> Bool {
        let tile = world.tile(x: x, y: y, room: g.room)
        if tile.kind.isSafeWalkable { return true }
        // Looking one row down lets a guard advance to the edge of a drop when the Prince is
        // standing on the floor below it.
        if below, tile.kind.isSpace, y < Geometry.roomRows - 1 {
            return world.tile(x: x, y: y + 1, room: g.room).kind.isSafeWalkable
        }
        return false
    }
}
