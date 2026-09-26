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

    /// `Fighter.distanceToEdge` — how far the actor's foot is from the edge of its tile.
    public static func distanceToEdge(_ state: ActorState) -> Int {
        if state.charFace == 1 {
            return CoordinateSpace.x(fromBlockX: state.charBlockX + 1)
                - 1 - state.charX - state.charFdx + state.charFfoot
        }
        return state.charX + state.charFdx + state.charFfoot
            - CoordinateSpace.x(fromBlockX: state.charBlockX)
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

    /// `Kid.checkRoomChange`.
    ///
    /// **189, not 192** — the Kid's threshold differs from the Fighter's. The rest of the
    /// reference function only fires `onChangeRoom` to move the camera as the actor nears an
    /// edge; it never changes `room` itself, which happens in `updateBlockPosition`. Those
    /// dispatches are not emitted because the host reads `state.room` each frame.
    ///
    /// The reference also returns early on twenty specific frames "around alternating chx",
    /// which exists to avoid a double room change while a frame is mid-flip. The `charY`
    /// branch below is unaffected by that guard, so it is not reproduced.
    public static func checkRoomChange(_ state: inout ActorState, world: any TileWorld) {
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

        let fallingBlocks = state.fallingBlocks
        state.fallingBlocks = 0
        state.isInFallDown = false
        state.swordDrawn = false

        // `Fighter.land` picks an action by how far he fell, and each has its own sound.
        let tile = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)
        if tile.kind == .spikes {
            effects.append(.sound(state.charName == "kid" ? .spikedBySpikes : .hardLandingSplat))
            effects.append(.died)
        } else if state.isAlive {
            switch fallingBlocks {
            case 0, 1:
                effects.append(.sound(.softLanding))
                state.beginAction("stand")
            case 2:
                effects.append(.sound(.mediumLandingOof))
                state.beginAction("medland")
                // A medium landing hurts.
                state.health = max(0, state.health - 1)
            default:
                // Landed on through too many floors: fatal.
                effects.append(.sound(.freeFallLand))
                state.isAlive = false
                effects.append(.died)
            }
        }
        try interpreter.step(&state, world: world, effects: &effects)
    }

    /// `Fighter.startFall` — the open-air path. Returns the action begun.
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
}
