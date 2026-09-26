/// Sword fighting.
///
/// Port source: `reference/PrinceJS/src/Fighter.js` — the verbs at lines 398–535 and
/// `checkFight` at 231–312.
///
/// ## The animation is the state machine
///
/// Every verb is gated on `frameID`. A strike is only legal on frames 157–158, 165, 170–171,
/// 7–8, 20–21 or 15; a step only on 158, 171, 8 or 20–21. Pressing the key on the wrong frame
/// does nothing at all. That is why combat feels deliberate rather than mashable, and it is the
/// single most important thing to preserve.
///
/// ## What is omitted
///
/// `canReachOpponent` is simplified to a distance test. The reference walks a tile path between
/// the two fighters using `checkPathToOpponent`, which measures from `centerX` — Phaser sprite
/// geometry, the same thing `checkBarrier` still owes (open question 11). The simplification
/// means a guard may engage through a thin barrier that the original would have stopped at.
public enum Combat {
    /// Reach in pixels beyond which a fighter will not close.
    public static let engageRange = 35

    // MARK: - Queries

    /// `Fighter.opponentOnSameLevel`.
    public static func onSameLevel(_ f: ActorState, _ o: ActorState) -> Bool {
        o.charBlockY == f.charBlockY
    }

    public static func inSameRoom(_ f: ActorState, _ o: ActorState) -> Bool {
        o.room == f.room
    }

    /// `Fighter.canSeeRoomLeft` — is the view across the boundary clear?
    public static func canSeeRoomLeft(_ f: ActorState, world: any TileWorld) -> Bool {
        guard let links = world.roomLinks(f.room), links.left > 0 else { return false }
        let here = world.tile(x: 0, y: f.charBlockY, room: f.room)
        let there = world.tile(x: Geometry.roomColumns - 1, y: f.charBlockY, room: links.left)
        return !here.kind.isSeeBarrier && !there.kind.isSeeBarrier
    }

    public static func canSeeRoomRight(_ f: ActorState, world: any TileWorld) -> Bool {
        guard let links = world.roomLinks(f.room), links.right > 0 else { return false }
        let here = world.tile(x: Geometry.roomColumns - 1, y: f.charBlockY, room: f.room)
        let there = world.tile(x: 0, y: f.charBlockY, room: links.right)
        return !here.kind.isSeeBarrier && !there.kind.isSeeBarrier
    }

    /// `Fighter.opponentNearRoomLeft`, with `full: false`.
    public static func opponentNearRoomLeft(
        _ f: ActorState, _ o: ActorState, world: any TileWorld, full: Bool
    ) -> Bool {
        guard let links = world.roomLinks(f.room), links.left > 0,
              canSeeRoomLeft(f, world: world), o.room == links.left
        else { return false }
        return full || o.charBlockX >= 8 || f.charBlockX <= 0
    }

    public static func opponentNearRoomRight(
        _ f: ActorState, _ o: ActorState, world: any TileWorld, full: Bool
    ) -> Bool {
        guard let links = world.roomLinks(f.room), links.right > 0,
              canSeeRoomRight(f, world: world), o.room == links.right
        else { return false }
        return full || o.charBlockX <= 0 || f.charBlockX >= 8
    }

    public static func opponentNearRoom(
        _ f: ActorState, _ o: ActorState, world: any TileWorld, full: Bool = false
    ) -> Bool {
        inSameRoom(f, o)
            || opponentNearRoomLeft(f, o, world: world, full: full)
            || opponentNearRoomRight(f, o, world: world, full: full)
    }

    /// `Fighter.opponentDistance`.
    ///
    /// Signed: positive means the opponent is in front. The `+13` when they face each other is
    /// the reference's allowance for two fighters' bodies between their origins.
    public static func opponentDistance(
        _ f: ActorState, _ o: ActorState, world: any TileWorld
    ) -> Int {
        guard onSameLevel(f, o) else {
            return canWalkOnNextTile(f, world: world) ? 999 : -999
        }

        let sameRoom = inSameRoom(f, o)
        let left = opponentNearRoomLeft(f, o, world: world, full: true)
        let right = opponentNearRoomRight(f, o, world: world, full: true)
        guard sameRoom || left || right else { return 999 }

        var roomOffset = 0
        if !sameRoom {
            if left { roomOffset = -150 * f.charFace }
            else if right { roomOffset = 150 * f.charFace }
        }

        var distance = (o.charX - f.charX) * f.charFace
        if distance >= 0, f.charFace != o.charFace { distance += 13 }
        return distance + roomOffset
    }

    /// `Fighter.facingOpponent`.
    public static func facingOpponent(_ f: ActorState, _ o: ActorState) -> Bool {
        f.charFace == -1 ? o.charX <= f.charX : o.charX >= f.charX
    }

    /// `Fighter.canWalkOnNextTile`.
    public static func canWalkOnNextTile(_ f: ActorState, world: any TileWorld) -> Bool {
        let blockX = CoordinateSpace.blockX(fromX: f.charX + f.charFdx * f.charFace)
        if world.tile(x: blockX + f.charFace, y: f.charBlockY, room: f.room).kind.isSafeWalkable {
            return true
        }
        if f.charBlockY < Geometry.roomRows - 1 {
            return world.tile(x: blockX + f.charFace, y: f.charBlockY + 1, room: f.room)
                .kind.isSafeWalkable
        }
        return false
    }

    /// `Fighter.canSeeOpponent`.
    ///
    /// The final clause compares Phaser screen positions; in engine units that is a horizontal
    /// span of 70 x-units (160 screen pixels) and 70 vertical pixels.
    public static func canSeeOpponent(
        _ f: ActorState, _ o: ActorState, world: any TileWorld, below: Bool = false
    ) -> Bool {
        guard o.isAlive, o.isActive else { return false }
        guard o.charBlockY == f.charBlockY || (below && o.charBlockY == f.charBlockY + 1) else {
            return false
        }
        guard f.charX > 0, o.charX > 0 else { return false }

        return opponentNearRoom(f, o, world: world)
            || opponentNearRoom(o, f, world: world)
            || (abs(o.charX - f.charX) <= 70 && abs(o.charY - f.charY) <= 70)
    }

    /// `Fighter.canReachOpponent` — **simplified.**
    ///
    /// The reference walks a tile path between the fighters, measuring from `centerX`. That is
    /// screen geometry, so this keeps the distance test and drops the path walk.
    public static func canReachOpponent(
        _ f: ActorState, _ o: ActorState, world: any TileWorld, below: Bool = false
    ) -> Bool {
        guard canSeeOpponent(f, o, world: world, below: below) else { return false }
        return abs(opponentDistance(f, o, world: world)) < 40
    }

    /// `Fighter.sneaks` — actions that count as moving quietly, so a guard will not react.
    public static func sneaks(_ f: ActorState) -> Bool {
        ["stoop", "stand", "standup", "turn", "jumpbackhang", "jumphanglong",
         "hang", "hangstraight", "hangdrop", "climbup", "climbdown", "testfoot"]
            .contains(f.action) || f.action.hasPrefix("step")
    }

    /// `Fighter.isHanging`.
    public static func isHanging(_ f: ActorState) -> Bool {
        ["hang", "hangstraight", "climbup", "climbdown", "hangdrop", "jumphanglong"]
            .contains(f.action)
    }

    // MARK: - Verbs

    /// `Fighter.engarde` — draw and take up a stance.
    @discardableResult
    public static func engarde(
        _ f: inout ActorState,
        world: any TileWorld,
        effects: inout [ActorEffect]
    ) -> Bool {
        guard f.hasSword else { return false }
        guard !Behaviour.nearBarrier(f, world: world) else { return false }

        f.beginAction("engarde")
        f.swordDrawn = true
        f.flee = false
        if f.charName == "kid" { effects.append(.sound(.unsheatheSword)) }
        return true
    }

    /// `Fighter.turnengarde`.
    public static func turnengarde(
        _ f: inout ActorState,
        _ o: ActorState,
        effects: inout [ActorEffect]
    ) {
        guard f.hasSword, !f.flee else { return }
        guard f.action != "turnengarde" else { return }
        guard ["stand", "engarde", "advance", "retreat"].contains(f.action) else { return }
        guard onSameLevel(f, o) else { return }

        // The Prince only takes the long way round from a standing start at a distance.
        let isKid = f.charName == "kid"
        if isKid, !f.swordDrawn { effects.append(.sound(.unsheatheSword)) }
        f.beginAction(isKid && f.action == "stand" && abs(o.charX - f.charX) > 10
            ? "beginturnengarde" : "turnengarde")
        f.swordDrawn = true
    }

    /// `Fighter.sheathe`.
    public static func sheathe(_ f: inout ActorState) {
        guard f.swordDrawn else { return }
        f.beginAction("resheathe")
        f.swordDrawn = false
        f.flee = false
    }

    /// `Fighter.advance` — a step forward, only on four frames of the cycle.
    public static func advance(_ f: inout ActorState) {
        if f.action == "stand" {
            return
        }
        if f.frameID(158) || f.frameID(171) || f.frameID(8) || f.frameID(20, 21) {
            f.beginAction("advance")
            f.allowAdvance = false
        }
    }

    /// `Fighter.retreat`.
    public static func retreat(_ f: inout ActorState) {
        if f.frameID(158) || f.frameID(170) || f.frameID(8) || f.frameID(20, 21) {
            f.beginAction("retreat")
            f.allowRetreat = false
        }
    }

    /// `Fighter.strike`.
    public static func strike(
        _ f: inout ActorState,
        _ o: ActorState,
        effects: inout [ActorEffect]
    ) {
        if !onSameLevel(f, o), f.charName != "kid" { return }

        // The Prince's swing whistles on two frames.
        if f.charName == "kid", f.frameID(157, 158) { effects.append(.sound(.stabAir)) }

        if f.frameID(157, 158) || f.frameID(165) || f.frameID(170, 171)
            || f.frameID(7, 8) || f.frameID(20, 21) || f.frameID(15) {
            f.beginAction("strike")
            f.allowStrike = false
        } else if f.frameID(150) || f.frameID(161) || f.frameID(0) || f.blocked {
            f.beginAction("blocktostrike")
            f.allowStrike = false
            f.blocked = false
        }
    }

    /// `Fighter.block`.
    public static func block(_ f: inout ActorState, _ o: ActorState, world: any TileWorld) {
        guard onSameLevel(f, o) else { return }

        if f.frameID(8) || f.frameID(20, 21) || f.frameID(18) || f.frameID(15) {
            if opponentDistance(f, o, world: world) >= 32 {
                return retreat(&f)
            }
            if !o.frameID(152), !o.frameID(2) { return }
            f.beginAction("block")
        } else {
            guard f.frameID(17) else { return }
            f.beginAction("striketoblock")
        }
        f.allowBlock = false
    }

    /// `Fighter.stabbed` — taking a hit.
    public static func stab(_ f: inout ActorState, effects: inout [ActorEffect]) {
        guard f.isAlive else { return }
        f.charY = CoordinateSpace.y(fromBlockY: f.charBlockY)
        guard f.health > 0 else { return }

        effects.append(.sound(f.charName == "kid" ? .stabbedByOpponent : .stabOpponent))

        if f.charName != "skeleton" {
            if f.charName == "kid", !f.swordDrawn {
                // Unarmed, the Prince does not survive a hit at all.
                die(&f, effects: &effects)
            } else {
                damageLife(&f, effects: &effects)
            }
        }

        // The action is chosen AFTER the damage, which is why `die` has to zero the health —
        // otherwise a fatal blow would be indistinguishable from a wound.
        if f.health == 0 {
            f.beginAction("stabkill")
        } else {
            f.beginAction("stabbed")
        }
    }

    /// `Fighter.die`.
    ///
    /// **It zeroes the health**, rather than leaving it where it was:
    ///
    /// ```js
    /// let damage = this.health;
    /// this.health -= damage;
    /// this.action = action || "dropdead";
    /// this.alive = false;
    /// ```
    ///
    /// That matters because `stabbed` decides between `stabkill` and `stabbed` by testing
    /// `health === 0` *after* the damage has been applied.
    public static func die(
        _ f: inout ActorState,
        action: String? = nil,
        effects: inout [ActorEffect]
    ) {
        guard f.isAlive else { return }
        if f.charName == "skeleton" {
            f.beginAction("stand")
            return
        }
        f.health = 0
        f.beginAction(action ?? "dropdead")
        f.isAlive = false
        f.swordDrawn = false
        effects.append(.died)
    }

    /// `Fighter.damageLife`.
    ///
    /// At one health left it does not decrement — it calls `die`, which is what actually takes
    /// the last point.
    public static func damageLife(_ f: inout ActorState, effects: inout [ActorEffect]) {
        guard f.isAlive, f.charName != "skeleton" else { return }
        if f.health > 1 {
            f.health -= 1
        } else {
            die(&f, effects: &effects)
        }
    }

    // MARK: - Resolution

    /// `Fighter.checkFight`.
    ///
    /// Takes both fighters, because the reference has each reach into the other: an `engarde`
    /// fighter whose opponent has turned away turns them back.
    public static func checkFight(
        _ f: inout ActorState,
        _ o: inout ActorState,
        world: any TileWorld,
        effects: inout [ActorEffect]
    ) {
        // A standing guard squares up to an opponent twenty pixels away or more.
        if f.charName != "kid", f.isActive, f.action == "stand",
           inSameRoom(f, o), !facingOpponent(f, o), f.charX > 0, o.charX > 0,
           abs(f.charX - o.charX) >= 20,
           !(f.sneakUp && sneaks(o)) {
            f.beginAction("turn")
        }

        guard f.hasStartedFight else { return }

        if f.blocked, f.action != "strike" {
            retreat(&f)
            f.blocked = false
            return
        }

        let distance = opponentDistance(f, o, world: world)
        if distance == -999 { return }

        switch f.action {
        case "engarde":
            if !o.isAlive {
                sheathe(&f)
            } else if distance < -4 {
                if !facingOpponent(f, o) { turnengarde(&f, o, effects: &effects) }
                if !facingOpponent(o, f) { turnengarde(&o, f, effects: &effects) }
            }

        case "strike":
            guard f.charBlockY == o.charBlockY else { return }
            guard o.action != "climbstairs" else { return }
            guard f.frameID(153, 154) || f.frameID(3, 4) else { return }

            if !o.frameID(150), !o.frameID(0) {
                if f.frameID(154) || f.frameID(4) {
                    // The strike lands on this frame or not at all.
                    let minHurt = o.swordDrawn ? 12 : 8
                    let maxHurt = 29 + (o.baseCharName == "fatguard" ? 2 : 0)
                    if (distance >= minHurt || distance <= 0), distance <= maxHurt {
                        stab(&o, effects: &effects)
                    }
                }
            } else {
                // The opponent is mid-strike or mid-block: steel rings, nobody bleeds.
                effects.append(.sound(.swordClash))
                o.blocked = true
                f.beginAction("blockedstrike")
            }

        default:
            break
        }
    }
}
