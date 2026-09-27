/// Gravity and the per-tick movement integration.
///
/// Port source: `reference/PrinceJS/src/Fighter.js`.
///
/// ```js
/// Fighter.GRAVITY = 3;  Fighter.GRAVITY_FLOAT = 1;
/// Fighter.TOP_SPEED = 33;  Fighter.TOP_SPEED_FLOAT = 4;
///
/// updateVelocity:     this.charX += this.charXVel;  this.charY += this.charYVel;
/// updateAcceleration: if (this.actionCode === 4) { charYVel += GRAVITY or GRAVITY_FLOAT, clamped }
/// ```
///
/// **Gravity applies only when `actionCode` is 4.** `actionCode` is written by `ACT`
/// (249), so the sequences decide when an actor is subject to gravity — `stepfall` uses
/// 3 and `freefall` uses 4. Applying gravity unconditionally would break every jump.
///
/// All integral, in `charY`'s unit (pixels).
public enum Physics {
    public static let gravity = 3
    public static let gravityFloat = 1

    /// Terminal fall speed. The reference clamps rather than accelerating without end.
    public static let topSpeed = 33
    public static let topSpeedFloat = 4

    /// The `actionCode` value that enables gravity.
    public static let gravityActionCode = 4

    /// `Fighter.updateAcceleration`.
    public static func accelerate(_ state: inout ActorState) {
        guard state.actionCode == gravityActionCode else { return }

        if state.isInFloat {
            state.charYVel += gravityFloat
            if state.charYVel > topSpeedFloat { state.charYVel = topSpeedFloat }
        } else {
            state.charYVel += gravity
            if state.charYVel > topSpeed { state.charYVel = topSpeed }
        }
    }

    /// `Fighter.updateVelocity`.
    public static func move(_ state: inout ActorState) {
        state.charX += state.charXVel
        state.charY += state.charYVel
    }
}

/// The fall-and-land cycle.
///
/// Port source: `Fighter.js#checkFall`, `#land`, `#startFall`, `#checkRoomChange` and
/// `Kid.js#inFallDistance`, `#startFall`, `Kid.js#checkFloor`'s fall branch.
///
/// The hang and ledge-grab paths are omitted — they need `checkBarrier`, which is part
/// of the remaining M3 work. Everything here is the open-air path.
public enum FallCycle {
    /// `Fighter.distanceToFloor`.
    public static func distanceToFloor(_ state: ActorState) -> Int {
        CoordinateSpace.y(fromBlockY: state.charBlockY) - state.charY - state.charFdy
    }

    /// `Fighter.distanceToTopFloor` — how far his foot is from the floor of the row *above*.
    ///
    /// Negative when he is above that row, which is the case that matters: `tryGrabEdge` allows a
    /// grab while it is at least -50, so a Prince who has jumped too high cannot catch the ledge on
    /// the way back down.
    public static func distanceToTopFloor(_ state: ActorState) -> Int {
        CoordinateSpace.y(fromBlockY: state.charBlockY - 1) - state.charY - state.charFdy
    }

    /// `Fighter.stopFall` — a caught ledge ends the fall outright.
    public static func stopFall(_ state: inout ActorState) {
        state.fallingBlocks = 0
        state.isInFallDown = false
        state.swordDrawn = false
    }

    /// `Kid.checkLedgeSwing` — once he has swung four times, letting go carries him sideways.
    ///
    /// ```js
    /// if (this.ledgeSwing >= 4) { this.charX += (this.inFloat ? 2.0 : 1.5) * this.charFace; }
    /// ```
    ///
    /// This is the swing-to-momentum mechanic: work the ledge, then drop, and the drop lands you
    /// somewhere else. The float potion widens the drift from 1.5 to 2 units a tick.
    public static func checkLedgeSwing(_ state: inout ActorState) {
        guard state.ledgeSwing >= 4 else { return }
        state.ledgeSwingHalves += state.isInFloat ? 4 : 3
        let whole = state.ledgeSwingHalves / 2
        state.ledgeSwingHalves -= whole * 2
        state.charX += whole * state.charFace
    }

    /// `Fighter.distanceToEdge` — how far the actor's foot is from the edge of its tile.
    public static func distanceToEdge(_ state: ActorState) -> Int {
        if state.charFace == 1 {
            return CoordinateSpace.x(fromBlockX: state.charBlockX + 1)
                - 1 - state.charX - state.charFdx + state.charFfoot
        }
        return state.charX + state.charFdx + state.charFfoot
            - CoordinateSpace.x(fromBlockX: state.charBlockX)
    }

    /// `Fighter.alignToTile` — snap an actor onto a tile, which is how a death by spikes or by
    /// chopper puts the body in the right place.
    ///
    /// ```js
    /// if (this.faceL()) { this.charX = convertBlockXtoX(tile.roomX) - 2; }
    /// else              { this.charX = convertBlockXtoX(tile.roomX + 1) + 1; }
    /// this.charY = convertBlockYtoY(tile.roomY);
    /// this.room = tile.room;
    /// ```
    ///
    /// Note the asymmetry: facing left he is pinned two units inside the *left* edge of the tile,
    /// facing right one unit inside the *right* edge. The room change needs no `charX` shift here
    /// because `updateBase` recomputes the screen origin from the new room — and the port's
    /// renderer is room-local, so there is nothing to recompute.
    public static func alignToTile(_ state: inout ActorState, to ref: TileRef) {
        if state.charFace == -1 {
            state.charX = CoordinateSpace.x(fromBlockX: ref.x) - 2
        } else {
            state.charX = CoordinateSpace.x(fromBlockX: ref.x + 1) + 1
        }
        state.charY = CoordinateSpace.y(fromBlockY: ref.y)
        state.charBlockX = ref.x
        state.charBlockY = ref.y
        state.room = ref.room
    }

    /// `Kid.inFallDistance` — whether a drop lies ahead.
    ///
    /// The `this.x === 0` test in the reference is a screen-space check whose meaning is
    /// unclear; the port keeps the structure and treats it as "not at the room's left
    /// edge", which is what `charX == 0` means in engine units.
    public static func isInFallDistance(_ state: ActorState, aheadTile: Tile) -> Bool {
        switch aheadTile.kind {
        case .space, .topBigPillar, .tapestryTop:
            return true
        default:
            break
        }
        if state.charX == 0 || !["runstop", "runturn", "runjump", "standjump"].contains(state.action) {
            return true
        }

        // **Stubbed, and only reachable while running.** The reference compares Phaser sprite
        // centres:
        //     let offsetX = this.faceL() ? 10 : -14;
        //     return Math.abs(tile.centerX - this.centerX + offsetX) >= 25;
        // `centerX` is a screen-space sprite property, so reproducing it needs the same
        // bounds work `checkBarrier` needs (open question 11). Returning `true` means a
        // running actor over a gap always falls, which is the common case and matches the
        // reference whenever the actor is not teetering on the very edge of a tile.
        return true
    }

    /// `Fighter.checkRoomChange` — drop straight through the floor of the room below.
    ///
    /// **The reference uses 192 here, not the room height of 189.** Reproduced as written.
    /// Guards use this; the Prince uses `checkRoomChange` below.
    public static func fighterCheckRoomChange(
        _ state: inout ActorState,
        world: (any ActorWorldQuery)?
    ) {
        guard state.charY > 192 else { return }
        state.charY -= 192
        state.baseY += Geometry.roomHeight
        if let links = world?.roomLinks(state.room) {
            state.room = links.down
        }
    }

    /// The frames on which `Kid.checkRoomChange` does nothing at all.
    ///
    /// ```js
    /// // Ignore frames around alternating chx (+/-)
    /// if ([16, 17, 27, 28, 47, 48, 49, 50, 51, 61, 62, 76, 77,
    ///      116, 117, 125, 126, 127, 128, 157].includes(this.charFrame)) { return; }
    /// ```
    ///
    /// The comment says what it is for: these are frames that **flip the sprite's x offset**
    /// (`chx`), and crossing a room on one of them would apply the flip on the wrong side of a
    /// room boundary. The port skipped this guard for a while on the stated grounds that "the
    /// `charY` branch below is unaffected" — but the guard is the first statement in the
    /// function, so its `return` skips *everything*, the `charY` test included. It is a plain
    /// early return and is reproduced as one.
    static let frozenFrames: Set<Int> = [
        16, 17, 27, 28, 47, 48, 49, 50, 51, 61, 62, 76, 77,
        116, 117, 125, 126, 127, 128, 157,
    ]

    /// `Kid.checkRoomChange`.
    ///
    /// **189, not 192** — the Kid's threshold differs from the Fighter's. The rest of the
    /// reference function only fires `onChangeRoom` to move the camera as the actor nears an
    /// edge; it never changes `room` itself, which happens in `updateBlockPosition`. Those
    /// dispatches are not emitted because the host reads `state.room` each frame.
    ///
    /// `Fighter.checkRoomChange` — the guards' version — has no frame guard at all, which is why
    /// only this one has it.
    public static func checkRoomChange(_ state: inout ActorState, world: any TileWorld) {
        guard !frozenFrames.contains(state.charFrame) else { return }
        guard state.charY > Geometry.roomHeight else { return }
        state.charY -= Geometry.roomHeight
        state.baseY += Geometry.roomHeight
        changeRoomDown(&state, world: world)
    }

    /// `Kid.changeRoomDown` — falling out of the bottom of a room.
    ///
    /// Includes the corner cases: with no room directly below, an actor at the right-hand edge
    /// drops into the room below the one to its right, and one at the left edge into the room
    /// below the one to its left. Both shift `charX` by a whole room so it stays room-local.
    static func changeRoomDown(_ state: inout ActorState, world: any TileWorld) {
        guard let links = world.roomLinks(state.room) else { return }

        if links.down > 0 {
            state.room = links.down
            return
        }

        if state.charBlockX >= Geometry.roomColumns - 1 {
            // `room = rooms[rooms[room].links.right].links.down`
            let right = links.right
            let room = right > 0 ? (world.roomLinks(right)?.down ?? 0) : 0
            if room > 0 {
                state.charX -= CoordinateSpace.xUnitsPerRoom
                state.baseX += Geometry.screenWidth
                state.charBlockX = 0
            }
            state.room = room
        } else if state.charBlockX <= 0 {
            var room = links.left
            if room > 0 {
                room = world.roomLinks(room)?.down ?? 0
                state.charX += CoordinateSpace.xUnitsPerRoom
                state.baseX -= Geometry.screenWidth
                state.charBlockX = Geometry.roomColumns - 1
            }
            state.room = room
        } else {
            state.room = links.down
        }
    }

    /// `Kid.checkFloor`'s **standing** branch (action codes 0, 1, 5, 7).
    ///
    /// ```js
    /// case 0: case 1: case 5: case 7:
    ///   this.inFallDown = false;
    ///   if (checkCharFcheck) {
    ///     switch (tile.element) {
    ///       case SPACE: case TOP_BIG_PILLAR: case TAPESTRY_TOP:
    ///         if (!this.alive) return;
    ///         if (this.inFallDistance(tileR)) this.startFall();
    ///         ...
    /// ```
    ///
    /// This is what makes the Prince drop when the ground disappears from under him — without
    /// it he stands in mid-air over a gap, which is exactly what level 1's spawn is: the Prince
    /// starts at column 1 of a room whose floor begins at column 3.
    ///
    /// The loose-board, spike and button cases of the same switch need the trob layer (M3c).
    public static func checkFloorStanding(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        guard [0, 1, 5, 7].contains(state.actionCode) else { return }
        state.isInFallDown = false

        // `checkCharFcheck` — the frame's fcheck bit 6 gates the whole switch.
        guard state.charFcheck else { return }

        let tile = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)

        // Standing on a loose board starts it shaking — and it will give way.
        if tile.kind == .looseBoard,
           let ref = world.resolve(x: state.charBlockX, y: state.charBlockY, room: state.room) {
            effects.append(.shookLooseBoard(ref))
            return
        }

        guard [TileKind.space, .topBigPillar, .tapestryTop].contains(tile.kind) else { return }
        guard state.isAlive else { return }

        // `tileR` is the tile *behind* the actor: `getTileAt(tile.roomX - this.charFace, ...)`.
        let behind = world.tile(
            x: state.charBlockX - state.charFace, y: state.charBlockY, room: state.room
        )
        if isInFallDistance(state, aheadTile: behind) {
            try startFall(&state, world: world, interpreter: interpreter, effects: &effects)
        }
    }

    /// `Fighter.checkFall` — land if the actor has reached a walkable tile.
    public static func checkFall(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        // `checkFloor` calls this for action codes 3 and 4, but a `stepfall` only probes the
        // floor when `startFall` armed the flag — otherwise a scripted fall would land on its
        // first tick, before any of its CHY instructions have moved the actor.
        if state.actionCode == 3 && !state.checkFloorStepFall { return }
        state.checkFloorStepFall = false

        let blockY = state.charBlockY
        guard state.charY + 6 >= CoordinateSpace.y(fromBlockY: blockY) else { return }

        var tile = world.tile(x: state.charBlockX, y: blockY, room: state.room)
        if tile.kind.isWalkable {
            try land(&state, world: world, interpreter: interpreter, effects: &effects)
            return
        }

        if tile.kind.isFreeFallBarrier {
            state.charX -= (tile.kind.isBarrierLeft ? 10 : 5) * state.charFace
            state.updateBlockPosition()
            tile = world.tile(x: state.charBlockX, y: blockY, room: state.room)
            if tile.kind.isWalkable {
                try land(&state, world: world, interpreter: interpreter, effects: &effects)
            }
        }
    }

    /// `Fighter.land`.
    public static func land(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        state.charY = CoordinateSpace.y(fromBlockY: state.charBlockY)
        state.charXVel = 0
        state.charYVel = 0

        // `let fallingBlocks = this.inFloat ? 0 : this.fallingBlocks` — a floating Prince walks
        // away from a fall that would otherwise be fatal.
        let fallingBlocks = state.isInFloat ? 0 : state.fallingBlocks
        state.fallingBlocks = 0
        state.isInFallDown = false
        state.swordDrawn = false

        // `Fighter.land` picks an action by how far he fell, and each has its own sound.
        let tile = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)
        if tile.kind == .spikes {
            // The reference plays the kid's impale scream for everyone here and notes the
            // generic splat in a comment; the comment is the intent, the string is the code.
            effects.append(.sound(.spikedBySpikes))
            if let ref = world.resolve(x: state.charBlockX, y: state.charBlockY, room: state.room) {
                alignToTile(&state, to: ref)
            }
            // `dieSpikes`: a skeleton is immune, everyone else is impaled.
            if state.isAlive, state.charName != "skeleton" {
                Combat.die(&state, action: "impale", effects: &effects)
            }
        } else if state.isAlive {
            switch fallingBlocks {
            case 0, 1:
                effects.append(.sound(.softLanding))
                state.beginAction("stand")

            case 2:
                // `Kid.land` sets the action *then* calls `damageLife(true)` — the flag is what
                // draws the splash five units higher, as if he went down on one knee. The order
                // matters: `showSplash` refuses a death animation, and the action has to be
                // `medland` at that point, not `dropdead`.
                effects.append(.sound(.mediumLandingOof))
                state.beginAction("medland")
                Combat.damageLife(&state, crouching: true, effects: &effects)

            default:
                // Landed on through too many floors.
                effects.append(.sound(.freeFallLand))
                Combat.die(&state, action: "falldead", effects: &effects)
            }
        }
        try interpreter.step(&state, world: world, effects: &effects)
    }

    /// `Kid.startFall` — the open-air path. Returns the action begun.
    ///
    /// The reference's `maskTile` calls only affect what the renderer draws, so they
    /// are not reproduced here; M4 handles masking from the tile map directly.
    @discardableResult
    public static func startFall(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws -> String {
        // These actions need an immediate floor probe; a plain step or run does not.
        if ["turn", "turnrun", "turnengarde", "highjump", "hangdrop"].contains(state.action) {
            state.checkFloorStepFall = true
        }

        state.fallingBlocks = min(0, state.fallingBlocks)
        state.isInFallDown = true
        // With the sword out a knockback goes the other way, so a fighting Prince is pushed into
        // his opponent rather than away from the wall he just hit.
        state.backwardsFall = state.swordDrawn ? -1 : 1

        // **Letting go of a ledge is not a step fall.** It has two actions of its own, and which
        // one runs is decided by what is underneath him.
        if state.action.hasPrefix("hang") {
            return try releaseLedge(&state, world: world, interpreter: interpreter, effects: &effects)
        }

        var action = "stepfall"
        if state.charFrame == 44 { action = "rjumpfall" }
        if state.charFrame == 26 { action = "jumpfall" }
        if state.charFrame == 13 { action = "stepfall2" }

        if distanceToEdge(state) <= 5,
           ["running", "runstop"].contains(state.action) || state.action.hasPrefix("step") {
            state.charX -= 7 * state.charFace
        }

        state.swordDrawn = false
        state.action = action
        try interpreter.step(&state, world: world, effects: &effects)
        return action
    }

    /// `Kid.startFall`'s hang branch — letting go of a ledge.
    ///
    /// ```js
    /// if (this.action.substring(0, 4) === "hang") {
    ///   let blockX = this.charBlockX;
    ///   if (this.action === "hangstraight") { blockX -= this.charFace; }
    ///   let tile = this.level.getTileAt(blockX, this.charBlockY, this.room);
    ///   if (![SPACE, TOP_BIG_PILLAR, TAPESTRY_TOP].includes(tile.element)) {
    ///     tile = this.level.getTileAt(this.charBlockX, this.charBlockY, this.room);
    ///     if (tile.isBarrier()) { this.charX -= 7 * this.charFace; }
    ///     this.action = "hangdrop";       // ground under him: drop, and land on it
    ///     this.stopFall();
    ///   } else {
    ///     tile = this.level.getTileAt(this.charBlockX, this.charBlockY, this.room);
    ///     if (tile.isBarrier()) { this.charX -= 7 * this.charFace; }
    ///     this.action = "hangfall";       // a hole under him: let go and go through it
    ///     this.level.maskTile(this.charBlockX - this.charFace, this.charBlockY, this.room, this);
    ///     this.processCommand();
    ///   }
    /// }
    /// ```
    ///
    /// The port used to answer this with a bare `action = "stepfall"`, which threw the decision
    /// away. `stepfall` probes the floor as soon as `checkFloorStepFall` is armed — so a Prince
    /// who let go of a hole landed on the floor *beside* it, in the room he was already in,
    /// instead of dropping through to the room below. Walking off the same hole worked, because
    /// that path never goes through here; only the ledge did.
    ///
    /// `hangstraight` is the pose he takes when the wall is in front of him, and it hangs him a
    /// column behind where it looks, which is why the probe moves back by `charFace`.
    @discardableResult
    static func releaseLedge(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws -> String {
        var overX = state.charBlockX
        if state.action == "hangstraight" { overX -= state.charFace }
        let over = world.tile(x: overX, y: state.charBlockY, room: state.room)

        // Either way he is pushed clear of whatever he has been hanging against.
        let under = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)
        if under.kind.isBarrier { state.charX -= 7 * state.charFace }

        let empty: Set<TileKind> = [.space, .topBigPillar, .tapestryTop]
        if empty.contains(over.kind) {
            state.beginAction("hangfall")
            try interpreter.step(&state, world: world, effects: &effects)
            return "hangfall"
        }

        state.beginAction("hangdrop")
        stopFall(&state)
        return "hangdrop"
    }
}
