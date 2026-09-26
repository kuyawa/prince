/// Tile-driven checks that run after the actor has moved.
///
/// Port source: `reference/PrinceJS/src/Kid.js#prepareCheckFloor`, `#checkButton`.
///
/// These live apart from `FallCycle` because they are not about falling; they are the actor
/// probing the tile it is standing on.
public enum TileChecks {
    /// `Kid.prepareCheckFloor` — which tile the actor should be tested against.
    ///
    /// The adjustments are not decoration: while hanging or climbing, the actor's logical tile is
    /// one row *below* the one its feet are in, and `fcheck` is forced on because those frames
    /// do not carry the bit themselves.
    public struct FloorProbe {
        public var skip = false
        public var tile = LevelRuntime.offMapTile
        public var checkCharFcheck = false
    }

    public static func prepareCheckFloor(_ state: ActorState, world: any TileWorld) -> FloorProbe {
        var probe = FloorProbe()

        // A single frame the reference skips entirely.
        if state.charFrame == 141 { probe.skip = true; return probe }

        var blockY = state.charBlockY
        let isHanging = state.action == "hang" || state.action == "hangstraight"
        let climbingHigh = state.action == "climbup" && (135...140).contains(state.charFrame)
        let climbingLow = state.action == "climbdown" && (91...140).contains(state.charFrame)

        if isHanging || climbingHigh || climbingLow {
            blockY -= 1
        }

        var checkCharFcheck = state.charFcheck
        if ["hang", "hangstraight", "climbup", "climbdown", "runturn"].contains(state.action) {
            checkCharFcheck = true
        }

        probe.tile = world.tile(x: state.charBlockX, y: blockY, room: state.room)
        probe.checkCharFcheck = checkCharFcheck
        return probe
    }

    /// `Kid.checkButton` — pressing a floor button by standing on it.
    ///
    /// ```js
    /// switch (this.actionCode) {
    ///   case 0: case 1: case 2: case 5: case 6: case 7:
    ///     if (checkCharFcheck) {
    ///       if (tile) switch (tile.element) {
    ///         case TILE_RAISE_BUTTON: case TILE_DROP_BUTTON: tile.push();
    ///       }
    ///     }
    /// }
    /// ```
    ///
    /// The `actionCode` gate matters: the seven listed codes are the standing, running, hanging
    /// and bumping states. Falling (3, 4) does not press buttons.
    /// The action codes that press buttons. Note the absence of 3 and 4 — falling does not.
    static let buttonPressingActionCodes: Set<Int> = [0, 1, 2, 5, 6, 7]

    @discardableResult
    public static func checkButton(_ state: inout ActorState, world: inout World) -> TileRef? {
        guard buttonPressingActionCodes.contains(state.actionCode) else { return nil }

        let probe = prepareCheckFloor(state, world: world)
        guard !probe.skip, probe.checkCharFcheck else { return nil }
        guard probe.tile.kind == .raiseButton || probe.tile.kind == .dropButton else { return nil }

        guard let ref = world.level.resolve(
            x: state.charBlockX, y: state.charBlockY, room: state.room
        ) else { return nil }

        return world.pressButton(at: ref) ? ref : nil
    }

    // MARK: - Spikes

    /// `Fighter.checkSpikes` — raise every spike field in the actor’s column, and in the column
    /// ahead when he is close enough to the edge of his own.
    ///
    /// ```js
    /// checkSpikes: function () {
    ///   if (this.distanceToEdge() < 5) { this.trySpikes(this.charBlockX + this.charFace, ...); }
    ///   this.trySpikes(this.charBlockX, this.charBlockY);
    /// }
    /// ```
    ///
    /// The column walk stops at a *wall* only — not a tapestry, not a gate. So a spike field
    /// below a wall stays put, and one below open floor is raised from anywhere in the room.
    public static func checkSpikes(
        _ state: inout ActorState, world: inout World, effects: inout [ActorEffect]
    ) {
        if FallCycle.distanceToEdge(state) < 5 {
            trySpikes(
                x: state.charBlockX + state.charFace, from: state.charBlockY,
                state: &state, world: &world, effects: &effects
            )
        }
        trySpikes(
            x: state.charBlockX, from: state.charBlockY,
            state: &state, world: &world, effects: &effects
        )
    }

    /// `Fighter.trySpikes` — walk down the column raising spike fields until a wall stops us.
    static func trySpikes(
        x: Int, from startY: Int,
        state: inout ActorState, world: inout World, effects: inout [ActorEffect]
    ) {
        var y = startY
        while y < Geometry.roomRows {
            let tile = world.tile(x: x, y: y, room: state.room)
            if tile.kind == .spikes,
               let ref = world.resolve(x: x, y: y, room: state.room),
               let sound = world.raiseSpikes(at: ref) {
                effects.append(.sound(sound))
            }
            if tile.kind == .wall { return }
            y += 1
        }
    }

    /// The `TILE_SPIKES` case of `Kid.checkFloor`’s standing branch.
    ///
    /// ```js
    /// case TILE_SPIKES:
    ///   if (this.inSpikeDistance(tile)) {
    ///     if ((tile.state !== FULL_OUT && ["running","runjump","runturn"].includes(this.action))
    ///         || this.action === "softland"
    ///         || (this.action === "medland" && this.frameID(108, 109))
    ///         || (this.action === "standjump" && this.frameID(26, 28))) {
    ///       this.game.sound.play("SpikedBySpikes");
    ///       this.alignToTile(tile);
    ///       this.dieSpikes();
    ///     }
    ///   }
    ///   tile.raise();
    /// ```
    ///
    /// **Two things here are load-bearing and look like mistakes.** `inSpikeDistance` returns
    /// `true` unconditionally — neither `Kid` nor `Fighter` overrides it, so the geometry test
    /// the name promises does not exist. And a runner only dies while the field is *not* fully
    /// out, which reads backwards until you notice that a field he disturbed himself is still
    /// rising when he steps onto it: `checkSpikes` raised it one tick earlier.
    ///
    /// This is a separate function from `FallCycle.checkFloorStanding` rather than a case inside
    /// it, because this branch needs a *mutable* world (raising a field is world state) while the
    /// falling branch only reads. The guards are duplicated on purpose; the two branches are
    /// mutually exclusive, so exactly one of them can fire for a given tile.
    public static func checkSpikeFloor(
        _ state: inout ActorState, world: inout World, effects: inout [ActorEffect]
    ) {
        guard buttonPressingActionCodes.contains(state.actionCode) else { return }
        guard state.charFcheck else { return }

        let x = state.charBlockX, y = state.charBlockY, room = state.room
        guard world.tile(x: x, y: y, room: room).kind == .spikes,
              let ref = world.resolve(x: x, y: y, room: room)
        else { return }

        let phase = world.spikes(at: ref)?.phase
        let runningIntoRisingSpikes = phase != .fullOut
            && ["running", "runjump", "runturn"].contains(state.action)
        let landingOnThem = state.action == "softland"
            || (state.action == "medland" && (108...109).contains(state.charFrame))
            || (state.action == "standjump" && (26...28).contains(state.charFrame))

        if runningIntoRisingSpikes || landingOnThem {
            // The kid has his own scream; a guard gets the generic splat.
            effects.append(.sound(state.charName == "kid" ? .spikedBySpikes : .hardLandingSplat))
            FallCycle.alignToTile(&state, to: ref)
            dieSpikes(&state, effects: &effects)
        }

        // The field comes up whether or not it just killed anybody.
        if let sound = world.raiseSpikes(at: ref) { effects.append(.sound(sound)) }
    }

    /// `Fighter.dieSpikes` — the impaling death. A skeleton is immune.
    public static func dieSpikes(_ state: inout ActorState, effects: inout [ActorEffect]) {
        guard state.isAlive, state.charName != "skeleton" else { return }
        Combat.die(&state, action: "impale", effects: &effects)
    }
}
