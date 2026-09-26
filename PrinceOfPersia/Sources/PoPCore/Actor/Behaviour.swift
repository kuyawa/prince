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
    /// `Kid.updateBehaviour`.
    public static func update(
        _ state: inout ActorState,
        intents: Intents,
        world: any TileWorld
    ) {
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
                return step(&state, world: world)
            }
            if intents.contains(.right), intents.contains(.action), state.charFace == 1 {
                return step(&state, world: world)
            }
            if intents.contains(.left), state.charFace == -1 {
                return startrun(&state, world: world)
            }
            if intents.contains(.right), state.charFace == 1 {
                return startrun(&state, world: world)
            }
            // `jump()` and `tryPickup()` are deferred — see the type comment.
            if intents.contains(.up) { return }
            if intents.contains(.down) { return stoop(&state) }
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
                return turnrun(&state, world: world)
            }
            if intents.contains(.right), state.charFace == 1, state.charFrame == 48 {
                return turnrun(&state, world: world)
            }

        case "stoop":
            state.charRepeat = false
            // Pickup paths (`gotSword`, `drinkPotion`) need the trob layer (M7).
            if !intents.contains(.down), state.charFrame == 109 { return standup(&state) }
            if intents.contains(.left), state.charFace == -1, state.allowCrawl { return crawl(&state) }
            if intents.contains(.right), state.charFace == 1, state.allowCrawl { return crawl(&state) }

        default:
            // Hanging, climbing, falling and combat all have their own arms in the
            // reference; none is reachable until the systems they depend on exist.
            break
        }
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
    public static func startrun(_ state: inout ActorState, world: any TileWorld) {
        if nearBarrier(state, world: world) { return step(&state, world: world) }
        state.beginAction("startrun")
    }

    public static func runturn(_ state: inout ActorState) {
        state.beginAction("runturn")
    }

    public static func turnrun(_ state: inout ActorState, world: any TileWorld) {
        if nearBarrier(state, world: world) {
            step(&state, world: world)
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

    /// `Kid.stoop`. The reference inspects the tile behind the actor; nothing here
    /// changes the action beyond entering the stoop.
    public static func stoop(_ state: inout ActorState) {
        state.beginAction("stoop")
    }

    /// `Kid.step` — the fine-grained approach to an edge.
    ///
    /// The action name is **built from the distance**, `"step" + min(px, 14)`, which is why
    /// the animation table carries `step1` through `step14` as separate sequences. That
    /// is the whole point of this verb: the Prince's final position at a ledge depends on
    /// which of the fourteen he is running.
    ///
    /// **Omitted:** the CHOPPER and MIRROR branches, which trim `px` using `distanceToEdge`
    /// against the blade or the mirror, and the `setBump`/`bump` calls that stop the step
    /// outright. Both need `checkBarrier`'s bounds geometry. Where the reference would
    /// bump, this clamps `px` to a minimum of zero — the actor stops short rather than
    /// being pushed back. Behaviour is identical in rooms without choppers or mirrors.
    public static func step(_ state: inout ActorState, world: any TileWorld) {
        var px = 11

        let tileF = world.tile(
            x: state.charBlockX + state.charFace, y: state.charBlockY, room: state.room
        )

        if nearBarrier(state, world: world)
            || [.space, .topBigPillar, .tapestryTop, .potion,
                .looseBoard, .dropButton, .raiseButton, .sword].contains(tileF.kind) {
            px = distanceToEdge(state)

            if tileF.kind.isBarrier, px - 2 <= 0 {
                // `setBump` is the bump mechanic, which needs `checkBarrier`. Stop short.
                px = max(px, 0)
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
    /// Note the gate test calls `canCrossGate` with `walk` and `turn` both false, which
    /// short-circuits the `(!walk || centreX …)` clause in the reference. That is why this
    /// needs no screen-space geometry, while the `walk: true` callers do.
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

        let frontBlocks =
            tileF.kind == .gate
            && ((!turn && state.charFace == -1) || (turn && state.charFace == 1))
            && world.gateBlocks(x: frontX, y: y, room: state.room)

        let hereBlocks =
            tile.kind == .gate
            && ((!turn && state.charFace == 1) || (turn && state.charFace == -1))
            && world.gateBlocks(x: x, y: y, room: state.room)

        return !(frontBlocks || hereBlocks)
    }
}
