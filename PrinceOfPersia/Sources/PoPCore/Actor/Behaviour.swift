/// The control layer: turning player input into a sequence to run.
///
/// Port source: `reference/PrinceJS/src/Kid.js#updateBehaviour` (lines 237–490) and the
/// movement verbs it dispatches to (lines 1223–1700).
///
/// `updateBehaviour` does **not** run the sequence. In the reference it is called from
/// `updateActor` immediately before `processCommand`, so a verb here only assigns
/// `action` — which restarts the sequence from index 0 — and the caller then executes it.
/// Keeping that split means one dispatch per tick, exactly as the reference does it.
///
/// ## What is here, and what is not
///
/// **Implemented:** the locomotion verbs — `turn`, `standjump`, `startrun`, `runturn`,
/// `turnrun`, `runjump`, `rdiveroll`, `standup`, `crawl`, `runstop`, `stoop`, `step`,
/// along with `nearBarrier` and `canCrossGate`.
///
/// **Not yet implemented, and why:**
///
/// - `jump()` is not a verb. It is a decision tree over five tile probes that routes into
///   the ledge system — `checkClimbable`, `jumphanglong`, `jumpbackhang`, `jumpup`,
///   `highjump`, `climbstairs`. It cannot be done before the hanging states are.
/// - `checkBarrier` reads Phaser sprite bounds, and `Tile.Base#getBounds` computes
///   `x = roomX * 32 + 40` — mixing screen pixels with engine units. Untangling that
///   faithfully is its own job.
/// - `checkButton`, `checkSpikes`, `checkChoppers` need the interactive-tile (trob) layer.
/// - `advance`, `retreat`, `block`, `strike`, `fastsheathe`, `tryEngarde` are combat (M6).
public enum Behaviour {
    /// `Kid.updateBehaviour`, without an effects channel.
    ///
    /// A verb that needs to change the world — climbing past a loose board, revealing an exit
    /// door — records it as an effect instead of reaching into the level.
    ///
    /// It throws because a verb may end the tick with `processCommand`, and `startFall` runs the
    /// fall sequence from inside `updateBehaviour`.
    /// `Kid.updateBehaviour`.
    ///
    /// The interpreter is here because two verbs — `step` against a mirror, and `step` into a
    /// gate — call `setBump`, and `setBump` ends the tick with `processCommand`. That is the
    /// reference’s own shape: a behaviour verb may run the sequence, it just does not *have* to.
    public static func update(
        _ state: inout ActorState,
        intents: Intents,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        // The reference bails out before the actor has a position.
        if state.charX == 0 && state.charY == 0 { return }

        // Re-arm the per-direction guards once the key is released.
        if !intents.contains(.left) && state.charFace == -1 {
            state.allowCrawl = true
            state.allowAdvance = true
        }
        if !intents.contains(.right) && state.charFace == 1 {
            state.allowCrawl = true
            state.allowAdvance = true
        }
        if !intents.contains(.left) && state.charFace == 1 { state.allowRetreat = true }
        if !intents.contains(.right) && state.charFace == -1 { state.allowRetreat = true }
        if !intents.contains(.up) { state.allowBlock = true }
        if !intents.contains(.action) { state.allowStrike = true }

        switch state.action {
        case "stand":
            state.blockEngarde = false
            state.ledgeSwing = 0
            // Combat entry (tryEngarde) is M6.
            if intents.contains(.left) && state.charFace == 1 {
                return turn(&state, world: world)
            }
            if intents.contains(.right) && state.charFace == -1 {
                return turn(&state, world: world)
            }
            if intents.contains(.left), intents.contains(.up), state.charFace == -1 {
                return standjump(&state)
            }
            if intents.contains(.right), intents.contains(.up), state.charFace == 1 {
                return standjump(&state)
            }
            if intents.contains(.left), intents.contains(.action), state.charFace == -1 {
                return try step(&state, world: world, interpreter: interpreter, effects: &effects)
            }
            if intents.contains(.right), intents.contains(.action), state.charFace == 1 {
                return try step(&state, world: world, interpreter: interpreter, effects: &effects)
            }
            if intents.contains(.left), state.charFace == -1 {
                return try startrun(&state, world: world, interpreter: interpreter, effects: &effects)
            }
            if intents.contains(.right), state.charFace == 1 {
                return try startrun(&state, world: world, interpreter: interpreter, effects: &effects)
            }
            if intents.contains(.up) { return jump(&state, world: world, effects: &effects) }
            if intents.contains(.down) { return stoop(&state, world: world) }
            // The action key alone is the pickup: `if (this.keyS()) { return this.tryPickup(); }`.
            if intents.contains(.action) {
                return tryPickup(&state, world: world, effects: &effects)
            }
            if intents.contains(.down) { return stoop(&state, world: world) }
            // `tryPickup()` — potions and swords — is still M7c.
            if intents.contains(.action) { return }

        case "startrun":
            state.blockEngarde = false
            state.charRepeat = false
            if (1...3).contains(state.charFrame) {
                if intents.contains(.up) { return standjump(&state) }
            } else if intents.contains(.up) {
                if (4...6).contains(state.charFrame) { return runjump(&state) }
                return standjump(&state)
            }

        case "running":
            state.charRepeat = false
            if intents.contains(.left), state.charFace == 1 { return runturn(&state) }
            if intents.contains(.right), state.charFace == -1 { return runturn(&state) }
            if !intents.contains(.left), state.charFace == -1 { return runstop(&state) }
            if !intents.contains(.right), state.charFace == 1 { return runstop(&state) }
            if intents.contains(.up) { return runjump(&state) }
            if intents.contains(.down) { return rdiveroll(&state) }

        case "turn":
            state.blockEngarde = false
            state.charRepeat = false
            if intents.contains(.left), state.charFace == -1, state.charFrame == 48 {
                return try turnrun(&state, world: world, interpreter: interpreter, effects: &effects)
            }
            if intents.contains(.right), state.charFace == 1, state.charFrame == 48 {
                return try turnrun(&state, world: world, interpreter: interpreter, effects: &effects)
            }

        case "stoop":
            state.charRepeat = false
            // Frame 109 is the frame his hand is actually on the floor. Both pickups are gated on
            // it, so a key pressed a frame early is simply carried until then.
            if state.pickupSword, state.charFrame == 109 {
                return gotSword(&state, world: world, effects: &effects)
            }
            if state.pickupPotion, state.charFrame == 109 {
                return drinkPotion(&state, world: world, effects: &effects)
            }
            if !intents.contains(.down), state.charFrame == 109 { return standup(&state) }
            if intents.contains(.left), state.charFace == -1, state.allowCrawl { return crawl(&state) }
            if intents.contains(.right), state.charFace == 1, state.allowCrawl { return crawl(&state) }

        case "hang":
            state.charRepeat = false
            // A hanging Prince pressed against a wall straightens up.
            if world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room).kind.isBarrier {
                state.beginAction("hangstraight")
                return
            }
            let above = world.tile(x: state.charBlockX, y: state.charBlockY - 1, room: state.room)
            if above.kind == .looseBoard,
               let ref = resolve(state, dx: 0, dy: -1, world: world) {
                // The board he is hanging from gives way, and takes him with it.
                effects.append(.shookLooseBoard(ref))
                if world.trob(x: state.charBlockX, y: state.charBlockY - 1, room: state.room)?
                    .looseBoard?.fallStarted == true {
                    return try hangFall(&state, world: world, interpreter: interpreter, effects: &effects)
                }
            }
            if intents.contains(.up), !state.grabWait {
                return climbup(&state, world: world, effects: &effects)
            }
            if !intents.contains(.action) { return try hangFall(&state, world: world, interpreter: interpreter, effects: &effects) }
            if state.charFrame == 92 { state.ledgeSwing += 1 }

        case "hangstraight":
            state.charRepeat = false
            if intents.contains(.up), !state.grabWait {
                return climbup(&state, world: world, effects: &effects)
            }
            if !intents.contains(.action) { return try hangFall(&state, world: world, interpreter: interpreter, effects: &effects) }

        case "climbup", "climbdown":
            state.charRepeat = false
            let spotted = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)
            // The board he is climbing past gives way underneath him.
            if spotted.kind == .looseBoard,
               world.trob(x: state.charBlockX, y: state.charBlockY, room: state.room)?
                   .looseBoard?.fallStarted == true {
                try FallCycle.startFall(
                    &state, world: world, interpreter: interpreter, effects: &effects
                )
            } else if state.charFrame == 142, spotted.kind == .space {
                // He has climbed out into nothing.
                try FallCycle.startFall(
                    &state, world: world, interpreter: interpreter, effects: &effects
                )
            }
            // The reference also calls `level.recheckCurrentRoom()` on the two frames that finish a
            // climb. That is a camera decision, and the host derives the camera room from the
            // Prince every frame already.

        case "jumpfall", "rjumpfall", "bumpfall", "stepfall", "freefall":
            // The action key, held while falling, is the grab. It is one attempt per tick, and the
            // first one that finds a ledge ends the fall.
            state.charRepeat = false
            if intents.contains(.action) {
                _ = try tryGrabEdge(
                    &state, world: world, interpreter: interpreter, effects: &effects
                )
            }

        default:
            // The combat arms have their own file; see `Combat`.
            break
        }
    }

    /// Letting go of a ledge.
    ///
    /// This used to be a bare `action = "stepfall"`, which is not what the reference does:
    /// `Kid.startFall` has a whole branch for the hanging actions that chooses between
    /// `hangfall` and `hangdrop` on what is underneath him. `stepfall` probes the floor, so a
    /// Prince who let go over a hole landed beside it in the room he was already in. See
    /// `FallCycle.releaseLedge`.
    private static func hangFall(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        _ = try FallCycle.startFall(
            &state, world: world, interpreter: interpreter, effects: &effects
        )
    }


    // MARK: - Ledges

    /// `Kid.inGrabDistance` — is the tile close enough sideways to catch?
    ///
    /// The offset is asymmetric: facing left the tile must be two units further right than his
    /// centre, facing right five units further left. That is the reach of the arm, which is drawn
    /// on one side of the body.
    public static func inGrabDistance(
        _ state: ActorState, tile: Tile, column: Int, atlas: String, distance: Int = 30
    ) -> Bool {
        let offsetX = state.charFace == -1 ? 2 : -5
        return abs(tile.centerX(column: column, atlas: atlas) - state.centerX() + offsetX)
            <= distance
    }

    /// `Kid.tryGrabEdge` — the action key while falling.
    ///
    /// Two chances, in order: the ledge **in front** of him (`charBlockX + face`), then the one he
    /// is already under (`charBlockX`, with a tighter 20-unit reach). The first is the ordinary
    /// case; the second is what catches a Prince who has drifted past the edge and is falling down
    /// its face.
    ///
    /// Three guards decide whether either is allowed: he cannot have fallen more than two floors
    /// (unless floating), his foot must be within 10 units of the edge — 13 for a `stepfall`, which
    /// is the slowest kind of fall and so gets a longer reach — and he must be within 50 units
    /// below the floor above, or, for the two fast falls, actually past the floor he fell from.
    ///
    /// The tapestry exclusion is the odd one: facing left you cannot catch a tapestry, because a
    /// tapestry is a thing you stand *behind*, and catching one from the left would draw him in
    /// front of it.
    /// @discardableResult
    public static func tryGrabEdge(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws -> Bool {
        state.updateBlockPosition()

        // Too far a fall to catch anything — unless floating, which is what the potion is for.
        if state.fallingBlocks > 2, !state.isInFloat { return false }

        let x = state.charBlockX, y = state.charBlockY, room = state.room
        let atlas = world.atlasName
        let behind = world.tile(x: x - state.charFace, y: y - 1, room: room)
        let front = world.tile(x: x + state.charFace, y: y - 1, room: room)
        let above = world.tile(x: x, y: y - 1, room: room)

        let reach = distanceToEdge(state)
            <= 10 + (state.action == "stepfall" ? 3 : 0)
        let inDistance = reach
            && (FallCycle.distanceToTopFloor(state) >= -50
                || (["jumpfall", "freefall"].contains(state.action)
                    && FallCycle.distanceToFloor(state) > -3))

        let catchable: Set<TileKind> = [.space, .topBigPillar, .tapestryTop]

        if front.kind.isWalkable, catchable.contains(above.kind), inDistance,
           inGrabDistance(state, tile: front, column: x + state.charFace, atlas: atlas),
           !(state.charFace == -1 && front.kind == .tapestry) {
            try grab(&state, at: x, world: world, interpreter: interpreter, effects: &effects)
            return true
        }

        if above.kind.isWalkable, catchable.contains(behind.kind), inDistance,
           inGrabDistance(
               state, tile: above, column: x, atlas: atlas, distance: 20
           ),
           !(state.charFace == -1 && above.kind == .tapestry) {
            try grab(
                &state, at: x - state.charFace,
                world: world, interpreter: interpreter, effects: &effects
            )
            return true
        }
        return false
    }

    /// `Kid.grab` — catch the ledge at column `x`.
    ///
    /// He is pulled onto the ledge: facing right, one unit past its *right* edge; facing left,
    /// three units inside its left edge. The velocities are zeroed and the fall is stopped, so the
    /// hang is not a fall that happens to be drawn differently.
    ///
    /// `grabWait` then blocks a climb for half a second, which stops an action key held through
    /// the grab from pulling him straight back up on the next tick.
    static func grab(
        _ state: inout ActorState,
        at column: Int,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        state.updateBlockPosition()

        if state.charFace == -1 {
            state.charX = CoordinateSpace.x(fromBlockX: column) - 3
        } else {
            state.charX = CoordinateSpace.x(fromBlockX: column + 1) + 1
        }
        state.charY = CoordinateSpace.y(fromBlockY: state.charBlockY)
        state.charXVel = 0
        state.charYVel = 0
        state.ledgeSwing = 0
        state.ledgeSwingHalves = 0
        FallCycle.stopFall(&state)
        state.updateBlockPosition()

        state.beginAction("hang")
        effects.append(.sound(.bumpIntoWallHard))
        try interpreter.step(&state, world: world, effects: &effects)

        // Catching a ledge shakes a loose board above it — and if that is enough to tip the board
        // over, the thing he just caught is about to disappear.
        if aboveIsLooseBoard(state, world: world),
           let ref = resolve(state, dx: 0, dy: -1, world: world) {
            effects.append(.shookLooseBoard(ref))
        }

        state.grabWait = true
        // `Utils.delayed(..., 500)` — six ticks at 1/12 s.
        state.grabWaitTicks = 6
    }

    /// Whether the tile directly above the actor is a loose board.
    static func aboveIsLooseBoard(_ state: ActorState, world: any TileWorld) -> Bool {
        world.tile(x: state.charBlockX, y: state.charBlockY - 1, room: state.room).kind
            == .looseBoard
    }

    /// The tile reference a relative offset lands on.
    static func resolve(_ state: ActorState, dx: Int, dy: Int, world: any TileWorld) -> TileRef? {
        TileRef(
            room: state.room,
            x: state.charBlockX + dx * state.charFace,
            y: state.charBlockY + dy
        )
    }

    // MARK: - Verbs

    /// `Kid.turn`. The two `turndraw` branches are combat and belong to M6.
    public static func turn(_ state: inout ActorState, world: any TileWorld) {
        state.beginAction("turn")
    }

    public static func standjump(_ state: inout ActorState) {
        state.beginAction("standjump")
    }

    /// `Kid.startrun` — walking into a wall becomes a step instead.
    public static func startrun(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        if nearBarrier(state, world: world) {
            return try step(
                &state, world: world, interpreter: interpreter, effects: &effects
            )
        }
        state.beginAction("startrun")
    }

    public static func runturn(_ state: inout ActorState) {
        state.beginAction("runturn")
    }

    public static func turnrun(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        if nearBarrier(state, world: world) {
            try step(&state, world: world, interpreter: interpreter, effects: &effects)
            state.charX -= 2 * state.charFace
            return
        }
        state.beginAction("turnrun")
    }

    public static func runjump(_ state: inout ActorState) {
        state.beginAction("runjump")
    }

    public static func rdiveroll(_ state: inout ActorState) {
        state.beginAction("rdiveroll")
        state.allowCrawl = false
    }

    public static func standup(_ state: inout ActorState) {
        state.beginAction("standup")
        state.allowCrawl = true
    }

    public static func crawl(_ state: inout ActorState) {
        state.beginAction("crawl")
        state.allowCrawl = false
    }

    /// `Kid.runstop` — only allowed on two frames of the run cycle.
    public static func runstop(_ state: inout ActorState) {
        guard state.charFrame == 7 || state.charFrame == 11 else { return }
        state.beginAction("runstop")
    }


    // MARK: - Pickups

    /// `Kid.tryPickup` — the SHIFT key while standing. Looks at the tile under him and the one
    /// in front, and if either holds a sword or a potion, crouches onto it.
    ///
    /// **Two oddities are the reference’s and are reproduced.** Facing right, the step forward
    /// is a whole column (`charBlockX++`) and then `charX` gains one unit *only for a potion*.
    /// Facing left, the same `charBlockX++` moves him the *other* way, and `charX` lands three
    /// units short of the column centre. The net effect is that he ends up over the item either
    /// way, by two different routes, and `gotSword`/`drinkPotion` below depend on the result.
    public static func tryPickup(
        _ state: inout ActorState, world: any TileWorld, effects: inout [ActorEffect]
    ) {
        let here = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)
        let ahead = world.tile(
            x: state.charBlockX + state.charFace, y: state.charBlockY, room: state.room
        )

        state.pickupSword = here.kind == .sword || ahead.kind == .sword
        state.pickupPotion = here.kind == .potion || ahead.kind == .potion
        guard state.pickupPotion || state.pickupSword else { return }

        if state.charFace == 1 {
            if ahead.kind == .potion || ahead.kind == .sword { state.charBlockX += 1 }
            state.charX = CoordinateSpace.x(fromBlockX: state.charBlockX)
                + (state.pickupPotion ? 1 : 0)
        }
        if state.charFace == -1 {
            if here.kind == .potion || here.kind == .sword { state.charBlockX += 1 }
            state.charX = CoordinateSpace.x(fromBlockX: state.charBlockX) - 3
        }

        state.beginAction("stoop")
        state.allowCrawl = false
    }

    /// `Kid.gotSword` — the Prince picks up the sword, which is the moment level 1 turns from
    /// a walk into a fight.
    public static func gotSword(
        _ state: inout ActorState, world: any TileWorld, effects: inout [ActorEffect]
    ) {
        state.pickupSword = false
        state.allowCrawl = true
        state.beginAction("pickupsword")
        // `game.sound.play("Victory")`, and Victory is a music file: the theme strikes up as he
        // takes the sword, which is what makes the moment land.
        effects.append(.music(.victory))

        if let ref = world.resolve(
            x: state.charBlockX + state.charFace, y: state.charBlockY, room: state.room
        ) {
            effects.append(.removedObject(ref))
        }
        state.hasSword = true
    }

    /// `Kid.drinkPotion`.
    ///
    /// The bottle is consumed immediately; what it *does* lands a second later, which is what
    /// makes the animation readable. The delay is a wall-clock timeout in the reference, so it is
    /// counted in ticks here — twelve of them.
    public static func drinkPotion(
        _ state: inout ActorState, world: any TileWorld, effects: inout [ActorEffect]
    ) {
        state.pickupPotion = false

        // The bottle in front comes first; falling back to the tile underfoot is what lets him
        // drink one he is standing on rather than beside.
        var ref = world.resolve(
            x: state.charBlockX + state.charFace, y: state.charBlockY, room: state.room
        )
        if ref == nil || world.tile(
            x: state.charBlockX + state.charFace, y: state.charBlockY, room: state.room
        ).kind != .potion {
            ref = world.resolve(x: state.charBlockX, y: state.charBlockY, room: state.room)
        }
        guard let ref, let potion = world.trob(
            x: ref.x, y: ref.y, room: ref.room
        )?.potion else {
            state.allowCrawl = true
            return
        }

        effects.append(.sound(.drinkPotionGlugGlug))
        state.beginAction("drinkpotion")
        effects.append(.removedObject(ref))

        // A special potion — one with a modifier of 6 or more — fires an event instead of
        // having a direct effect. No shipped level contains one; the data is honoured and the
        // event plumbing is not built.
        if potion.isSpecial { return }
        if let effect = potion.effect {
            effects.append(.pendingPotion(actorIsPrince: true, effect: effect))
        }
    }

    /// `Kid.stoop` — crouching, or lowering yourself over an edge when there is space behind.
    public static func stoop(_ state: inout ActorState, world: any TileWorld) {
        let behind = world.tile(
            x: state.charBlockX - state.charFace, y: state.charBlockY, room: state.room
        )
        let overAnEdge = behind.kind == .space || behind.kind == .topBigPillar
            || (state.charFace == -1 && behind.kind == .tapestryTop)

        if overAnEdge {
            let centre = CoordinateSpace.x(fromBlockX: state.charBlockX)
            if state.charFace == -1, state.charX - centre > 4 {
                return climbdown(&state, world: world)
            }
            if state.charFace == 1, state.charX - centre < 9 {
                return climbdown(&state, world: world)
            }
        }
        state.beginAction("stoop")
    }

    // MARK: - Jumping

    /// `Kid.checkJump`.
    static func checkJump(_ state: ActorState, _ tile: Tile) -> Bool {
        (state.charFace == -1 && tile.kind.isSpace)
            || (state.charFace == 1 && tile.kind.isJumpSpace)
    }

    /// `Kid.checkClimbable` — anything walkable can be pulled onto, except a hanging when facing
    /// left, where the frame would be behind you.
    static func checkClimbable(_ state: ActorState, _ tile: Tile) -> Bool {
        tile.kind.isWalkable && (state.charFace == 1 || tile.kind != .tapestry)
    }

    /// `Kid.jump` — the decision tree behind the up key.
    ///
    /// Not one verb but five tile probes routing into the ledge system, ending in one of five
    /// different sequences: `jumpup`, `highjump`, `jumphanglong`, `jumpbackhang` or
    /// `climbstairs`.
    ///
    /// **Omitted:** the two mirror branches need `bump`, whose physics depend on the screen-space
    /// bounds `checkBarrier` still owes (open question 11). Each condition is still evaluated and
    /// returns without changing the action, so control flow matches the reference; only the bump
    /// itself is missing, and only in rooms containing a mirror.
    public static func jump(
        _ state: inout ActorState,
        world: any TileWorld,
        effects: inout [ActorEffect]
    ) {
        let x = state.charBlockX
        let y = state.charBlockY
        let face = state.charFace
        let room = state.room

        var tile = world.tile(x: x, y: y, room: room)
        let above = world.tile(x: x, y: y - 1, room: room)
        let aboveFront = world.tile(x: x + face, y: y - 1, room: room)
        let aboveBehind = world.tile(x: x - face, y: y - 1, room: room)
        let behind = world.tile(x: x - face, y: y, room: room)

        if tile.kind.isExitDoor {
            var doorX = x
            if tile.kind == .exitLeft {
                doorX = x + 1
                tile = world.tile(x: doorX, y: y, room: room)
            }
            if world.trob(x: doorX, y: y, room: room)?.exitDoor?.isOpen == true {
                return climbstairs(&state, x: doorX, world: world, effects: &effects)
            }
        }

        if face == -1, tile.kind == .mirror {
            let actorScreenX = CoordinateSpace.screenX(fromX: Double(state.charX))
            if abs(x * Geometry.blockWidth - actorScreenX) < 30 { return }
        }
        if aboveFront.kind == .mirror { return jumpup(&state) }

        if checkJump(state, above), checkClimbable(state, aboveFront) {
            return jumphanglong(&state)
        }

        if checkClimbable(state, above), checkJump(state, aboveBehind), behind.kind.isWalkable {
            if face == -1, CoordinateSpace.x(fromBlockX: x + 1) - state.charX < 11 {
                state.charBlockX += 1
                return jumphanglong(&state)
            }
            if face == 1, state.charX - CoordinateSpace.x(fromBlockX: x) < 9 {
                state.charBlockX -= 1
                return jumphanglong(&state)
            }
            return jumpup(&state)
        }

        if checkClimbable(state, above), checkJump(state, aboveBehind) {
            if face == -1, CoordinateSpace.x(fromBlockX: x + 1) - state.charX < 11 {
                return jumpbackhang(&state)
            }
            if face == 1, state.charX - CoordinateSpace.x(fromBlockX: x) < 9 {
                return jumpbackhang(&state)
            }
            return jumpup(&state)
        }

        if above.kind.isSpace { return highjump(&state) }
        jumpup(&state)
    }

    public static func jumpup(_ state: inout ActorState) {
        state.beginAction("jumpup")
        state.isInJumpUp = true
    }

    public static func highjump(_ state: inout ActorState) {
        state.beginAction("highjump")
    }

    /// The two offsets differ by a pixel and are not a typo.
    public static func jumpbackhang(_ state: inout ActorState) {
        let base = CoordinateSpace.x(fromBlockX: state.charBlockX)
        state.charX = state.charFace == -1 ? base + 7 : base + 6
        state.beginAction("jumpbackhang")
    }

    public static func jumphanglong(_ state: inout ActorState) {
        let base = CoordinateSpace.x(fromBlockX: state.charBlockX)
        state.charX = state.charFace == -1 ? base + 1 : base + 12
        state.beginAction("jumphanglong")
    }

    /// `Kid.climbstairs` — the exit.
    public static func climbstairs(
        _ state: inout ActorState,
        x: Int,
        world: any TileWorld,
        effects: inout [ActorEffect]
    ) {
        var column = x
        if world.tile(x: column, y: state.charBlockY, room: state.room).kind == .exitRight {
            column -= 1
        } else {
            column += 1
        }

        if state.charFace == 1 { state.charFace = -1 }
        state.charBlockX = column
        state.charX = CoordinateSpace.x(fromBlockX: column) + 3

        effects.append(.maskedExitDoor(TileRef(room: state.room, x: column, y: state.charBlockY)))
        effects.append(.leavingLevel)
        state.beginAction("climbstairs")
    }

    /// `Kid.climbup`.
    public static func climbup(
        _ state: inout ActorState,
        world: any TileWorld,
        effects: inout [ActorEffect]
    ) {
        state.blockEngarde = false
        let above = world.tile(x: state.charBlockX, y: state.charBlockY - 1, room: state.room)
        let gate = world.trob(x: state.charBlockX, y: state.charBlockY - 1, room: state.room)?.gate

        if state.charFace == -1, let gate, gate.phase == .fastDropping || !gate.canCross(height: 15) {
            state.beginAction("climbfail")
        } else {
            state.beginAction("climbup")
        }

        if above.kind == .looseBoard, let ref = resolve(state, dx: 0, dy: -1, world: world) {
            effects.append(.shookLooseBoard(ref))
        }
    }

    /// `Kid.climbdown`.
    public static func climbdown(_ state: inout ActorState, world: any TileWorld) {
        state.blockEngarde = false
        let base = CoordinateSpace.x(fromBlockX: state.charBlockX)
        let gate = world.trob(x: state.charBlockX, y: state.charBlockY, room: state.room)?.gate

        if state.charFace == -1, let gate, gate.phase == .fastDropping || !gate.canCross(height: 15) {
            state.charX = base + 3
        } else {
            state.charX = state.charFace == -1 ? base + 6 : base + 7
            state.beginAction("climbdown")
        }
    }

    /// `Kid.step` — the fine-grained approach to an edge.
    ///
    /// The action name is **built from the distance**, `"step" + min(px, 14)`, which is why
    /// the animation table carries `step1` through `step14` as separate sequences. That
    /// is the whole point of this verb: the Prince's final position at a ledge depends on
    /// which of the fourteen he is running.
    ///
    /// Four branches, and which one runs decides whether a step is a step, a bump, or merely a
    /// test of the ground. The chopper and mirror cases *trim* `px` rather than stopping him: a
    /// Prince may walk right up to the blades, but no further, and the difference between `px` and
    /// 11 is the whole point of this verb.
    public static func step(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        var px = 11

        let x = state.charBlockX, y = state.charBlockY, room = state.room
        let tile = world.tile(x: x, y: y, room: room)
        let tileF = world.tile(x: x + state.charFace, y: y, room: room)

        if (tile.kind == .chopper && state.charFace == -1)
            || (tileF.kind == .chopper && state.charFace == 1) {
            // Stops one unit short of the blades — and if there is no room at all he steps the
            // full eleven rather than freezing, which is what keeps him from sticking to a blade
            // he is already standing under.
            px = distanceToEdge(state) - 4 - (state.charFace == -1 ? 1 : 0)
            if px <= 0 { px = 11 }
        } else if (tile.kind == .mirror && state.charFace == -1)
            || (tileF.kind == .mirror && state.charFace == 1) {
            // A mirror stops him eight units out, and at that point he is bumped instead.
            px = distanceToEdge(state) - 8
            if px <= 0 {
                try Barrier.bump(
                    &state, world: world, interpreter: interpreter, effects: &effects
                )
                return
            }
        } else if nearBarrier(state, world: world)
            || [.space, .topBigPillar, .tapestryTop, .potion,
                .looseBoard, .dropButton, .raiseButton, .sword].contains(tileF.kind) {
            px = distanceToEdge(state)

            // A gate that is slamming shut or already too low to duck under, and a tapestry,
            // stop him six units earlier — but only walking right.
            let gate = world.trob(x: x, y: y, room: room)?.gate
            let gateBlocks = tile.kind == .gate
                && (gate?.phase == .fastDropping || gate?.canCross(height: 30) == false)
            if gateBlocks || tile.kind == .tapestry, state.charFace == 1 {
                px -= 6
                if px <= 0 {
                    Barrier.setBump(&state, world: world, effects: &effects)
                    try interpreter.step(&state, world: world, effects: &effects)
                    return
                }
            } else if tileF.kind == .potion || tileF.kind == .sword {
                if !nearBarrier(state, world: world), px == 0 { px = 11 }
            } else if tileF.kind.isBarrier, px - 2 <= 0 {
                Barrier.setBump(&state, world: world, effects: &effects)
                try interpreter.step(&state, world: world, effects: &effects)
                return
            } else if px == 0,
                      [.looseBoard, .dropButton, .raiseButton,
                       .space, .topBigPillar, .tapestryTop].contains(tileF.kind) {
                if state.charRepeat
                    || tileF.kind == .dropButton || tileF.kind == .raiseButton {
                    state.charRepeat = false
                    px = 11
                } else {
                    state.charRepeat = true
                    state.beginAction("testfoot")
                    return
                }
            }
        }

        guard px > 0 else { return }
        state.beginAction("step\(min(px, 14))")
    }

    /// `Fighter.moveR` — whether the actor is moving right *as part of an action*.
    ///
    /// This is not "is the right key held". It derives a direction from the current action plus
    /// facing, and several actions — stooping, bumping, standing, turning, striking — are
    /// pinned in place and never count as movement.
    public static func moveR(_ state: ActorState, extended: Bool = true) -> Bool {
        if ["stoop", "bump", "stand", "turn", "turnengarde", "strike"].contains(state.action) {
            return false
        }
        if extended && state.action == "engarde" { return false }
        return (state.charFace == -1 && ["retreat", "stabbed"].contains(state.action))
            || (state.charFace == 1 && !["retreat", "stabbed"].contains(state.action))
    }

    /// `Fighter.moveL` — the mirror of `moveR`.
    public static func moveL(_ state: ActorState, extended: Bool = true) -> Bool {
        if ["stoop", "bump", "stand", "turn", "turnengarde", "strike"].contains(state.action) {
            return false
        }
        if extended && state.action == "engarde" { return false }
        return (state.charFace == 1 && ["retreat", "stabbed"].contains(state.action))
            || (state.charFace == -1 && !["retreat", "stabbed"].contains(state.action))
    }

    /// `Fighter.distanceToEdge` — how far the actor's foot is from its tile's edge.
    public static func distanceToEdge(_ state: ActorState) -> Int {
        if state.charFace == 1 {
            return CoordinateSpace.x(fromBlockX: state.charBlockX + 1)
                - 1 - state.charX - state.charFdx + state.charFfoot
        }
        return state.charX + state.charFdx + state.charFfoot
            - CoordinateSpace.x(fromBlockX: state.charBlockX)
    }

    // MARK: - Barrier probes

    /// `Fighter.nearBarrier`.
    ///
    /// Note the gate test here calls `canCrossGate` with `walk` and `turn` both false, which
    /// short-circuits the `(!walk || centreX …)` clause; the `walk: true` callers do need the
    /// screen-space centres, and `SpriteMetrics` is what makes them available.
    public static func nearBarrier(
        _ state: ActorState,
        world: any TileWorld,
        blockX: Int? = nil,
        blockY: Int? = nil,
        walk: Bool = false,
        turn: Bool = false
    ) -> Bool {
        let x = blockX ?? state.charBlockX
        let y = blockY ?? state.charBlockY

        let tile = world.tile(x: x, y: y, room: state.room)
        let tileF = world.tile(x: x + state.charFace, y: y, room: state.room)

        return tileF.kind == .wall
            || !canCrossGate(state, world: world, x: x, y: y, tile: tile, walk: walk, turn: turn)
            || (tile.kind == .tapestry && state.charFace == 1)
            || (tileF.kind == .tapestry && state.charFace == -1)
            || (tileF.kind == .tapestryTop && state.charFace == -1)
    }

    /// `Fighter.canCrossGate`.
    public static func canCrossGate(
        _ state: ActorState,
        world: any TileWorld,
        x: Int,
        y: Int,
        tile: Tile,
        walk: Bool,
        turn: Bool
    ) -> Bool {
        let frontX = x + state.charFace
        let tileF = world.tile(x: frontX, y: y, room: state.room)

        // Walking, a gate he is already up against is crossable even while it is too low — he is
        // not walking *into* it, he is walking *out* from under it. The five-pixel margin is the
        // reference’s.
        let actorCentre = state.centerX()
        let tileCentre = tile.centerX(column: x, atlas: world.atlasName)

        let frontBlocks =
            tileF.kind == .gate
            && ((!turn && state.charFace == -1) || (turn && state.charFace == 1))
            && world.gateBlocks(x: frontX, y: y, room: state.room)
            && (!walk || actorCentre + 5 > tileCentre)

        let hereBlocks =
            tile.kind == .gate
            && ((!turn && state.charFace == 1) || (turn && state.charFace == -1))
            && world.gateBlocks(x: x, y: y, room: state.room)
            && (!walk || actorCentre - 5 < tileCentre)

        return !(frontBlocks || hereBlocks)
    }
}
