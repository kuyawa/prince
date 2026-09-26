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
        // The reference compares Phaser screen centres here; in engine units the tile
        // centre is x(fromBlockX:) and the actor's centre is charX + charFdx * face.
        return true
    }

    /// `Fighter.checkRoomChange` — drop through the floor of the room below.
    ///
    /// The reference uses **192**, not the room height of 189. Reproduced as written.
    public static func checkRoomChange(_ state: inout ActorState, world: (any ActorWorldQuery)?) {
        guard state.charY > 192 else { return }
        state.charY -= 192
        state.baseY += Geometry.roomHeight
        if let links = world?.roomLinks(state.room) {
            state.room = links.down
        }
    }

    /// `Fighter.checkFall` — land if the actor has reached a walkable tile.
    public static func checkFall(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
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

        let tile = world.tile(x: state.charBlockX, y: state.charBlockY, room: state.room)
        if tile.kind == .spikes {
            effects.append(.died)
        } else if state.isAlive {
            switch fallingBlocks {
            case 0, 1:
                state.beginAction("stand")
            default:
                // Landed on too many falling blocks: fatal.
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
