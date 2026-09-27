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
/// ## The two halves of a duel
///
/// `Fighter`'s verbs are shared; `Kid` overrides four things — `updateBehaviour`, `block`,
/// `fastsheathe` and `startFall`. `GuardBrain` is the guard's half of the duel and has been
/// complete since M6. **The Prince's half was wired to nothing at all.** `Behaviour.update` had
/// a comment saying the combat arms were M6 and a `default: break` where they should have been,
/// so he could never draw his sword: Shift is the *strike*, not the entry, and the stance is taken
/// up without being asked. A missing `tryEngarde` therefore reads to a player as "the sword is
/// never used". Those verbs are at the bottom of this file, under "The Prince's own verbs".
///
/// The two halves do **not** share frame windows, and must not be tidied into one set: the Prince
/// parries on 158, 165 or 167, the guard on 8, 20, 21, 18, 15 or 17.
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

    /// `Fighter.canReachOpponent` — the real one, not a distance test.
    ///
    /// Two passes. The first asks whether there is a **clear line at all** — nothing but walkable,
    /// barrier-free tiles between them — and if so a plain distance check settles it. The second
    /// walks the columns again asking whether he could actually *stand* on each in turn, which is
    /// what a fighter closing for a swordfight needs to know.
    ///
    /// The `below` variant lets the path drop one row through a gap, which is how a guard on a
    /// ledge notices a Prince on the floor below him.
    ///
    /// **This was the last simplification in the port.** It was waiting on `centerX`, which is
    /// screen geometry, which is `SpriteMetrics`.
    public static func canReachOpponent(
        _ f: ActorState, _ o: ActorState, world: any TileWorld,
        below: Bool = false, turn: Bool = false
    ) -> Bool {
        guard canSeeOpponent(f, o, world: world, below: below) else { return false }
        let faceSign = turn ? -1 : 1

        // Pass one: is the corridor between them clear?
        let clear = checkPathToOpponent(
            f, o, world: world, from: f.charBlockX, blockY: f.charBlockY, room: f.room
        ) { x, y, room in
            let tile = world.tile(x: x, y: y, room: room)
            let tileF = world.tile(x: x + f.charFace * faceSign, y: y, room: f.room)
            let crossable = Behaviour.canCrossGate(
                f, world: world, x: x, y: y, tile: tile, walk: true, turn: turn
            )
            return (crossable && !(tile.kind.isBarrierWalk || tileF.kind.isBarrierWalk), false)
        }
        if clear, abs(opponentDistance(f, o, world: world)) < 40 { return true }

        // Pass two: could he stand his way along it?
        return checkPathToOpponent(
            f, o, world: world, from: f.charBlockX, blockY: f.charBlockY, room: f.room
        ) { x, y, room in
            if canWalkOnTile(f, o, world: world, x: x, y: y, room: room, turn: turn) {
                return (true, false)
            }
            let tile = world.tile(x: x, y: y, room: room)
            if below, tile.kind == .space, y < Geometry.roomRows - 1, o.charBlockY == y + 1 {
                let reachable = checkPathToOpponent(
                    f, o, world: world, from: x, blockY: y + 1, room: room
                ) { x2, y2, room2 in
                    (canWalkOnTile(f, o, world: world, x: x2, y: y2, room: room2, turn: turn), false)
                }
                return (reachable, true)
            }
            return (false, false)
        }
    }

    /// `Fighter.standsOnTile` — is this tile the one his feet are on?
    ///
    /// The reference compares tile *object identity* with `===`, which over a grid of shared tiles
    /// means the same position, not merely an equal tile.
    public static func standsOnTile(_ f: ActorState, x: Int, y: Int, room: Int) -> Bool {
        x == f.charBlockX && y == f.charBlockY && room == f.room
    }

    /// `Fighter.canWalkOnTile` — can he *stand* here, as opposed to merely pass through?
    ///
    /// The chopper case is the interesting one: he may walk onto a blade only facing right, and
    /// only when both he and his opponent are already past the blade’s origin. That is what stops a
    /// fighter stepping into the slicer to escape one.
    public static func canWalkOnTile(
        _ f: ActorState, _ o: ActorState, world: any TileWorld,
        x: Int, y: Int, room: Int, turn: Bool = false
    ) -> Bool {
        let tile = world.tile(x: x, y: y, room: room)
        guard Behaviour.canCrossGate(
            f, world: world, x: x, y: y, tile: tile, walk: true, turn: turn
        ) else { return false }

        if tile.kind == .chopper {
            guard f.charFace == 1 else { return false }
            let edge = x * Geometry.blockWidth + 15
            return f.spriteX() > edge && o.spriteX() > edge
        }
        return tile.kind.isSafeWalkable || standsOnTile(f, x: x, y: y, room: room)
    }

    /// `Fighter.checkPathToOpponent` — walk the columns between the two fighters, asking a question
    /// about each.
    ///
    /// Returns `true` only if the callback said yes at *every* column. Crosses room boundaries by
    /// wrapping through `links`, and the `+ 10` widening when the opponent is in another room is
    /// what lets a guard at a doorway reach into the next room.
    static func checkPathToOpponent(
        _ f: ActorState,
        _ o: ActorState,
        world: any TileWorld,
        from startX: Int,
        blockY: Int,
        room: Int,
        _ callback: (Int, Int, Int) -> (value: Bool, stop: Bool)
    ) -> Bool {
        let sameRoom = room == o.room
        var maxX = o.charBlockX + (sameRoom ? 0 : 10)
        var minX = o.charBlockX - (sameRoom ? 0 : 10)
        if isHanging(o) {
            if o.charFace == 1 { maxX += 1 } else if o.charFace == -1 { minX -= 1 }
        }

        var column = startX
        var currentRoom = room

        if f.centerX() <= o.centerX() {
            if column > maxX { column = maxX }
            while column <= maxX {
                if column == Geometry.roomColumns {
                    guard let links = world.roomLinks(currentRoom), links.right > 0 else {
                        return false
                    }
                    currentRoom = links.right
                }
                let result = callback(column % Geometry.roomColumns, blockY, currentRoom)
                if !result.value || result.stop { return result.value }
                column += 1
            }
        } else {
            if column < minX { column = minX }
            while column >= minX {
                if column == -1 {
                    guard let links = world.roomLinks(currentRoom), links.left > 0 else {
                        return false
                    }
                    currentRoom = links.left
                }
                let wrapped = (Geometry.roomColumns + column) % Geometry.roomColumns
                let result = callback(wrapped, blockY, currentRoom)
                if !result.value || result.stop { return result.value }
                column -= 1
            }
        }
        return true
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

    // MARK: - The Prince's own verbs

    /// `Kid.tryEngarde` — the sword comes out **on its own**.
    ///
    /// Not a key. A standing Prince who has the sword, can reach an opponent and faces him draws
    /// it without being asked, and that stance is what gives the strike key any meaning.
    ///
    /// Three details are easy to drop and all of them are load-bearing:
    ///
    /// - `blockEngarde` is set by `Barrier` on the landing branch of `Kid.land`: a Prince who
    ///   arrives in a heap does not stand up into a fighting stance.
    /// - `dodgeChoppers` runs *before* the reach test, so he takes the stance up from a position
    ///   the blades no longer reach — the nudge only moves him a pixel or three, and the blade's
    ///   reach is measured from where he ends up.
    /// - The reach is 35 instead of 100 when the guard has his back turned and is sneaking, which
    ///   is what makes an unaware guard walkable-up-to.
    ///
    /// `level.recheckCurrentRoom()` is the opponent search. In the port that belongs to the tick,
    /// not to the verb; see `Simulation`.
    @discardableResult
    public static func tryEngarde(
        _ f: inout ActorState, _ o: ActorState, world: any TileWorld, effects: inout [ActorEffect]
    ) -> Bool {
        guard f.hasSword, !f.blockEngarde else { return false }
        dodgeChoppers(&f, world: world)

        let engardeDistance = (!facingOpponent(o, f) && o.sneakUp) ? 35 : 100
        guard o.isAlive, opponentDistance(f, o, world: world) <= engardeDistance else { return false }
        return engarde(&f, world: world, effects: &effects)
    }

    /// `Kid.block` — the Prince's parry window, which is **not** the guard's.
    ///
    /// `Fighter.block` gates on 8, 20, 21, 18, 15 and 17; `Kid.block` on 158, 165 and 167, and it
    /// makes a different test of the opponent. The port had only the `Fighter` version, because
    /// only the guard half of the duel was wired.
    ///
    /// Returns whether the reference runs the sequence from inside the verb — its
    /// `if (this.opponent.frameID(3)) { this.processCommand(); }`. The interpreter belongs to
    /// `Behaviour`, so the caller runs it, exactly as `Behaviour.step` does for `setBump`.
    ///
    /// Note the shape of the early returns: a frame that cannot block leaves `allowBlock` **set**,
    /// so a key pressed a frame early is carried rather than swallowed.
    @discardableResult
    public static func kidBlock(_ f: inout ActorState, _ o: ActorState) -> Bool {
        var runSequence = false

        if f.frameID(158) || f.frameID(165) {
            // Frame 18 of a stab is the contact frame: there is nothing left to parry.
            if o.frameID(18) { return false }
            f.beginAction("block")
            if o.frameID(3) { runSequence = true }
        } else {
            guard f.frameID(167) else { return false }
            f.beginAction("striketoblock")
        }

        f.allowBlock = false
        return runSequence
    }

    /// `Kid.fastsheathe` — down in the stance: the sword goes away and he runs rather than fights.
    ///
    /// **This is the one place the Prince reaches into his opponent**, which is why the opponent is
    /// `inout`. `Kid`'s override is not the same function without it: it calls
    /// `this.opponent.fastsheathe()` and then pushes the opponent's `refracTimer` out nine ticks,
    /// so the fight really does stop rather than merely pausing on one side.
    ///
    /// `flee` is what he has bought: while it is set, `tryEngarde` is only reached with the
    /// action key held, so he has to ask for the next fight.
    public static func kidFastsheathe(_ f: inout ActorState, opponent o: inout ActorState?) {
        f.flee = true
        f.beginAction("fastsheathe")
        f.swordDrawn = false

        if var other = o {
            fastsheathe(&other)
            o = other
        }
    }

    /// `Enemy.fastsheathe` — only a shadow obeys. Every other guard keeps his sword out, which is
    /// why a Prince who flees a guard is still followed by one.
    ///
    /// A shadow is deactivated here as well as disarmed, which is `setInactive()` and not
    /// `setActive()`'s visibility: it keeps whatever visibility it already had.
    static func fastsheathe(_ f: inout ActorState) {
        if f.charName == "shadow" {
            f.isActive = false
            f.hasStartedFight = false
            f.beginAction("fastsheathe")
            f.swordDrawn = false
        }
        f.refracTimer = 9
    }

    /// `Fighter.dodgeChoppers` — the small sideways nudge out of the blades.
    ///
    /// The band is asymmetric and the nudge is the exact amount that lands him 16 pixels out
    /// either way. It exists so a stance is never taken up inside a chopper's reach.
    static func dodgeChoppers(_ f: inout ActorState, world: any TileWorld) {
        let distance = chopperDistance(f, world: world)
        if distance >= 13, distance <= 16 {
            f.charX -= 16 - distance
        } else if distance >= -16, distance <= -13 {
            f.charX += distance + 16
        }
        f.updateBlockPosition()
    }

    /// `Fighter.chopperDistance` — the gap to a blade on his column or the one in front.
    ///
    /// 999 is the reference's own sentinel and is why `dodgeChoppers` tests bands rather than
    /// equality. A skeleton is answered 999 outright, as the reference returns `undefined` for one.
    static func chopperDistance(_ f: ActorState, world: any TileWorld) -> Int {
        if f.charName == "skeleton" { return 999 }
        for column in [f.charBlockX, f.charBlockX + 1] {
            guard world.tile(x: column, y: f.charBlockY, room: f.room).kind == .chopper,
                  nearChopDistance(f, column: column, world: world)
            else { continue }
            return TileChecks.chopDistance(f, tileColumn: column, levelAtlas: world.atlasName)
        }
        return 999
    }

    /// `Fighter.nearChopDistance` — within 16 screen pixels of the blade's centre.
    static func nearChopDistance(_ f: ActorState, column: Int, world: any TileWorld) -> Bool {
        abs(TileChecks.chopDistance(f, tileColumn: column, levelAtlas: world.atlasName)) <= 16
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

        // The reference calls `showSplash` here as well as inside `damageLife`, and the second
        // call matters for the one path that does not go through it: an unarmed Prince, killed by
        // `die` outright. `stabkill` is not one of the four self-bloodying actions, so the pool
        // appears.
        Splash.show(&f)
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
    public static func damageLife(
        _ f: inout ActorState, crouching: Bool = false, effects: inout [ActorEffect]
    ) {
        guard f.isAlive, f.charName != "skeleton" else { return }
        // Before the action is touched. Splash.show refuses the four death animations, and this
        // blow may be the one about to start one. `crouching` is the medium landing, which draws
        // the pool five units higher.
        Splash.show(&f, crouching: crouching)
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
    ///
    /// Returns `true` when the fight is over and the caller should drop its reference to the
    /// opponent. That is the reference's `this.opponent = null`, in the same branch that sheathes
    /// the sword, and it is not bookkeeping: a caller that keeps looking only for *living* guards
    /// stops calling this the moment one dies, so the Prince is left standing in his stance for
    /// ever with his sword out and no way to put it away.
    @discardableResult
    public static func checkFight(
        _ f: inout ActorState,
        _ o: inout ActorState,
        world: any TileWorld,
        effects: inout [ActorEffect]
    ) -> Bool {
        // A standing guard squares up to an opponent twenty pixels away or more.
        if f.charName != "kid", f.isActive, f.action == "stand",
           inSameRoom(f, o), !facingOpponent(f, o), f.charX > 0, o.charX > 0,
           abs(f.charX - o.charX) >= 20,
           !(f.sneakUp && sneaks(o)) {
            f.beginAction("turn")
        }

        guard f.hasStartedFight else { return false }

        if f.blocked, f.action != "strike" {
            retreat(&f)
            f.blocked = false
            return false
        }

        let distance = opponentDistance(f, o, world: world)
        if distance == -999 { return false }

        switch f.action {
        case "engarde":
            if !o.isAlive {
                sheathe(&f)
                return true
            } else if distance < -4 {
                if !facingOpponent(f, o) { turnengarde(&f, o, effects: &effects) }
                if !facingOpponent(o, f) { turnengarde(&o, f, effects: &effects) }
            }

        case "strike":
            guard f.charBlockY == o.charBlockY else { return false }
            guard o.action != "climbstairs" else { return false }
            guard f.frameID(153, 154) || f.frameID(3, 4) else { return false }

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
        return false
    }
}
