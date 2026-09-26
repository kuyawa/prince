/// The barrier collision, and the bump it produces.
///
/// Port source: `reference/PrinceJS/src/Kid.js#checkBarrier` (line 600), `#bump` (723),
/// `#setBump` (763), `#bumpSound` (769), `#bumpFall` (776) and `Fighter#alignToFloor`.
///
/// This was the last thing in the port that was stubbed rather than written, because it reads
/// Phaser sprite geometry. `SpriteMetrics` closed that gap: every rectangle here is built from
/// measured cel sizes, and the arithmetic is transcribed rather than re-derived.
///
/// ## Two rectangles, and they disagree
///
/// `checkBarrier` asks either `intersects(charBounds)` or `intersectsAbs(charBoundsAbs)`, and the
/// second only counts when the sword is sheathed. The two actor rectangles are built differently
/// — one from the frame data, one from the live sprite — and differ by a few pixels. The tile side
/// disagrees too: `screenBounds` is a four-pixel strip forty pixels into the cell, `screenBoundsAbs`
/// is the full cel at the tile origin. Reproducing one and approximating the other would move where
/// walls stop the Prince, which is most of how the game feels to walk around in.
public enum Barrier {
    /// The actions that skip the check entirely.
    ///
    /// ```js
    /// if (["jumpup", "highjump", "jumphanglong", "jumpbackhang",
    ///      "climbup", "climbdown", "climbfail", "stand", "turn", "fastsheathe"].includes(this.action))
    ///   return;
    /// if (this.action.substring(0, 4) === "step" ||
    ///     (this.action.substring(0, 4) === "hang" && this.action !== "hangdrop")) return;
    /// ```
    static let exemptActions: Set<String> = [
        "jumpup", "highjump", "jumphanglong", "jumpbackhang",
        "climbup", "climbdown", "climbfail", "stand", "turn", "fastsheathe",
    ]

    /// Whether `action` is one `checkBarrier` ignores.
    ///
    /// The two prefix tests are the reference’s. `step` covers `step`, `step2`…`step14` and
    /// `stepfall`; `hang` covers every hang *except* `hangdrop`, which is the one where a Prince
    /// is dropping and so can hit something.
    static func skips(_ action: String) -> Bool {
        if exemptActions.contains(action) { return true }
        if action.hasPrefix("step") { return true }
        if action.hasPrefix("hang"), action != "hangdrop" { return true }
        return false
    }

    /// `Kid.checkBarrier`.
    @discardableResult
    public static func checkBarrier(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws -> Bool {
        guard state.isAlive, !skips(state.action) else { return false }
        let atlas = world.atlasName

        let x = state.charBlockX, y = state.charBlockY, room = state.room
        let tile = world.tile(x: x, y: y, room: room)
        let above = world.tile(x: x, y: y - 1, room: room)
        let behind = world.tile(x: x - state.charFace, y: y, room: room)

        // Falling into a two-tile-high barrier: pushed clear of it and dropped into a bump.
        if state.action == "freefall",
           tile.kind.isFreeFallBarrier, above.kind.isFreeFallBarrier {
            if Behaviour.moveL(state) {
                state.charX = CoordinateSpace.x(fromBlockX: x + 1) - 1
            } else if Behaviour.moveR(state) {
                state.charX = CoordinateSpace.x(fromBlockX: x)
            }
            state.updateBlockPosition()
            try bump(&state, world: world, interpreter: interpreter, effects: &effects)
            return true
        }

        let walkingIntoIt = Behaviour.moveR(state)
            && (tile.kind.isBarrier
                || (state.centerX() <= behind.centerX(column: x - state.charFace, atlas: atlas)
                    && [TileKind.tapestry, .tapestryTop].contains(behind.kind)))

        if walkingIntoIt {
            // A mirror is a barrier you walk *through* — the reference simply returns.
            if tile.kind == .mirror { return false }

            let hit = tile.screenBounds(column: x, row: y).intersects(state.charBounds())
                || (tile.screenBoundsAbs(column: x, row: y, atlas: atlas)
                        .intersects(state.charBoundsAbs())
                    && !state.swordDrawn)
            guard hit else { return false }

            // A tapestry is a barrier you push *past*: the reference steps him back a column first,
            // which is what lets the Prince walk behind one.
            if !tile.kind.isBarrier { state.charBlockX -= state.charFace }
            if state.swordDrawn {
                state.charX = CoordinateSpace.x(fromBlockX: state.charBlockX) - 2
            } else {
                state.charX = CoordinateSpace.x(fromBlockX: state.charBlockX) + 5
            }
            state.updateBlockPosition()
            try bump(&state, world: world, interpreter: interpreter, effects: &effects)
            return true
        }

        // Not moving into it: probe a column ahead, offset further with the sword out because the
        // blade sticks out in front of him.
        let offsetX = state.swordDrawn ? 12 * state.charFace : 0
        let blockX = CoordinateSpace.blockX(
            fromX: state.charX + state.charFdx * state.charFace - offsetX
        )

        var next = world.tile(x: blockX, y: y, room: room)
        if next.kind.isBarrier {
            switch next.kind {
            case .wall:
                // A wall stops him wherever he is; he is nudged clear and bumps. With the sword
                // out he is not moved at all — the blade has already taken the space.
                if !state.swordDrawn {
                    if Behaviour.moveL(state) {
                        state.charX = CoordinateSpace.x(fromBlockX: blockX + 1) - 1
                    } else if Behaviour.moveR(state) {
                        state.charX = CoordinateSpace.x(fromBlockX: blockX)
                    }
                    state.updateBlockPosition()
                }
                try bump(&state, world: world, interpreter: interpreter, effects: &effects)
                return true

            case .gate, .tapestry, .tapestryTop:
                let close = next.screenBounds(column: blockX, row: y)
                    .intersects(state.charBounds())
                    || (next.screenBoundsAbs(column: blockX, row: y, atlas: atlas)
                            .intersects(state.charBoundsAbs())
                        && !state.swordDrawn)
                if Behaviour.moveL(state), close {
                    if state.action == "stand", tile.kind == .gate {
                        // Standing against a gate he is simply pushed back a little.
                        state.charX = CoordinateSpace.x(fromBlockX: state.charBlockX) + 3
                        state.updateBlockPosition()
                    } else if state.centerX() - 8 > next.centerX(column: blockX, atlas: atlas) {
                        state.charX = CoordinateSpace.x(fromBlockX: blockX + 1) - 1
                        state.updateBlockPosition()
                        try bump(&state, world: world, interpreter: interpreter, effects: &effects)
                        return true
                    }
                }

            default:
                break
            }
        }

        // A mirror is solid from behind, but a running jump passes through.
        next = world.tile(x: blockX - state.charFace, y: y, room: room)
        if next.kind == .mirror, Behaviour.moveL(state), state.action != "runjump" {
            state.charX += 5
            try bump(&state, world: world, interpreter: interpreter, effects: &effects)
            return true
        }
        return false
    }

    // MARK: - The bump

    /// `Kid.bump`.
    ///
    /// Four separate outcomes, and which one fires depends on what is under him and how far he is
    /// from the floor. The `frameID` cases are the jump frames: a Prince who bumps *mid-jump* lands
    /// instead, which is what stops him hanging in the air against a wall.
    public static func bump(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        let tile = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)

        if tile.kind == .space {
            state.charX -= 2 * state.charFace * state.backwardsFall
            try bumpFall(&state, world: world, interpreter: interpreter, effects: &effects)
            return
        }

        if FallCycle.distanceToFloor(state) >= 5 {
            try bumpFall(&state, world: world, interpreter: interpreter, effects: &effects)
            return
        }

        if state.frameID(24, 25) || state.frameID(40, 42) || state.frameID(102, 106) {
            state.charX -= 5 * state.charFace
            try FallCycle.land(
                &state, world: world, interpreter: interpreter, effects: &effects
            )
            return
        }

        // Sword sheathed and the tile is not walkable: pushed back five. With the sword out the
        // shove is smaller and depends on which way he is moving, because a fighting Prince is
        // not simply repelled.
        if !state.swordDrawn, !tile.kind.isWalkable, state.action != "highjump" {
            state.charX -= 5 * state.charFace
        }

        if state.swordDrawn {
            if Behaviour.moveR(state) {
                state.charX -= 2
            } else if Behaviour.moveL(state) {
                state.charX += 6
            } else {
                state.charX += 5 * state.charFace
            }
            bumpSound(&state, effects: &effects)
            return
        }

        // A landing is already an animation; interrupting it with a bump would cut it short.
        guard !["softland", "medland"].contains(state.action) else { return }
        state.blockEngarde = true
        setBump(&state, world: world, effects: &effects)
        try interpreter.step(&state, world: world, effects: &effects)
    }

    /// `Kid.setBump` — the standing bump: noise, action, and back onto the floor.
    static func setBump(
        _ state: inout ActorState, world: any TileWorld, effects: inout [ActorEffect]
    ) {
        bumpSound(&state, effects: &effects)
        state.beginAction("bump")
        alignToFloor(&state, world: world)
    }

    /// `Kid.bumpSound` — rate-limited to one every ten ticks.
    ///
    /// Without the timer a Prince held against a wall plays the bump on every tick, which is a
    /// buzz rather than a thud.
    static func bumpSound(_ state: inout ActorState, effects: inout [ActorEffect]) {
        guard state.bumpTimer == 0 else { return }
        effects.append(.sound(.bumpIntoWallSoft))
        state.bumpTimer = 10
    }

    /// `Kid.bumpFall` — a bump that turns into a fall.
    static func bumpFall(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        state.isInFallDown = true

        // Already free-falling: he just loses a step of momentum.
        if state.actionCode == 4 {
            state.charX -= state.charFace * state.backwardsFall
            state.charXVel = 0
            state.ledgeSwing = 0
            return
        }

        state.charX -= 2 * state.charFace * state.backwardsFall
        bumpSound(&state, effects: &effects)
        state.beginAction("bumpfall")
        try interpreter.step(&state, world: world, effects: &effects)
    }

    /// `Fighter.alignToFloor` — drop the actor onto the row its block says it is on.
    static func alignToFloor(_ state: inout ActorState, world: any TileWorld) {
        state.charY = CoordinateSpace.y(fromBlockY: state.charBlockY)
        state.isInJumpUp = false
    }
}
