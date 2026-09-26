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

    // MARK: - Falling boards

    /// `Kid.damageStruck` — a board landed on him.
    ///
    /// ```js
    /// damageStruck: function () {
    ///   if (!this.alive) { return; }
    ///   if (this.action.includes("land")) { return; }
    ///   if (this.fallingBlocks < 2) { this.fallingBlocks = 2; }
    ///   if (!this.inFallDown) { this.land(); }
    /// },
    /// ```
    ///
    /// **The trick is the `fallingBlocks = 2`.** Rather than taking a point off directly, the
    /// reference makes the game think he has just fallen two floors and calls the ordinary landing
    /// — which is a medium landing, which is one point of damage. So a board's damage and a
    /// two-floor drop's damage are the same code path, and a board can finish off a Prince who is
    /// already at one health, because `land` reaches `damageLife`.
    ///
    /// The `includes("land")` guard stops a board landing on somebody who is already landing.
    ///
    /// **Guards are exempt.** `Game.floorStopFall` does call `checkLooseFloor` on every enemy, but
    /// `Fighter.checkLooseFloor` is `function (tile) {}` — empty. Only `Kid` overrides it. So the
    /// exemption belongs here rather than at the call site, because it is the method that does not
    /// exist for a guard, not the loop that skips them.
    public static func damageStruck(
        _ state: inout ActorState,
        world: any TileWorld,
        interpreter: SequenceInterpreter,
        effects: inout [ActorEffect]
    ) throws {
        guard state.charName == "kid" else { return }
        guard state.isAlive else { return }
        guard !state.action.contains("land") else { return }
        if state.fallingBlocks < 2 { state.fallingBlocks = 2 }
        guard !state.isInFallDown else { return }
        try FallCycle.land(&state, world: world, interpreter: interpreter, effects: &effects)
    }

    /// `Fighter.dieSpikes` — the impaling death. A skeleton is immune.
    public static func dieSpikes(_ state: inout ActorState, effects: inout [ActorEffect]) {
        guard state.isAlive, state.charName != "skeleton" else { return }
        Combat.die(&state, action: "impale", effects: &effects)
    }
    // MARK: - Choppers

    /// `Fighter.chopDistance` — how far the actor is from a chopper’s blades, in screen pixels.
    ///
    /// ```js
    /// chopDistance: function (tile) {
    ///   let offsetX = -16;
    ///   return tile.centerX - this.centerX + offsetX;
    /// }
    /// ```
    ///
    /// **Both centres are Phaser sprite centres, and a Phaser sprite is as wide as its current
    /// frame** — `PIXI.Sprite.width = scale.x * texture.frame.width`. The tile cel is a constant
    /// 60 px, but the actor’s runs from 11 px standing to 49 px mid-strike, so half of it swings
    /// by more than the 6-pixel window the result is tested against. `SpriteMetrics` reads the
    /// real numbers out of the atlas JSON.
    ///
    /// **One deliberate deviation.** `checkChoppers` runs *before* `updateCharPosition` in
    /// `updateActor`, so the reference is measuring the sprite as it was left at the end of the
    /// previous tick — last tick’s frame and last tick’s screen x. Reproducing that would mean
    /// keeping a shadow copy of Phaser’s transform purely to reproduce an artefact of its update
    /// order, and the DOS original had no such lag. The port measures the live state.
    public static func chopDistance(
        _ state: ActorState, tileColumn: Int, levelAtlas: String
    ) -> Int {
        let tileWidth = SpriteMetrics.width(
            atlas: levelAtlas, frame: "\(levelAtlas)_\(TileKind.chopper.rawValue)"
        ) ?? SpriteMetrics.dungeonTileSize.width

        var tempx = Double(state.charX + state.charFdx * state.charFace)
        let halfPixel = (state.charFood && state.charFace == -1)
            || (!state.charFood && state.charFace == 1)
        if halfPixel { tempx += 0.5 }

        let actorWidth = SpriteMetrics.actorWidth(
            charName: state.charName, frame: state.charFrame
        )

        // tile.centerX - actor.centerX - 16
        return tileColumn * Geometry.blockWidth + tileWidth / 2
            - CoordinateSpace.screenX(fromX: tempx) - actorWidth / 2 - 16
    }

    /// `Fighter.inChopDistance`. The window widens by ten pixels with the sword drawn — a blade
    /// held out in front is exactly what the extra reach represents.
    public static func inChopDistance(
        _ state: ActorState, tileColumn: Int, levelAtlas: String
    ) -> Bool {
        let window = 6 + (state.swordDrawn ? 10 : 0)
        return abs(chopDistance(state, tileColumn: tileColumn, levelAtlas: levelAtlas)) < window
    }

    /// `Fighter.checkChoppers`.
    ///
    /// The kid wakes the leftmost blades in his row every tick, and reaches into the neighbouring
    /// room when he is up against the boundary — which is how blades in an adjacent room can be
    /// heard before it is on screen.
    public static func checkChoppers(
        _ state: inout ActorState, world: inout World, effects: inout [ActorEffect]
    ) {
        if state.charName == "kid" {
            let cameraRoom = world.actors[0].room
            // `-1`: the leftmost blade in the row.
            world.activateChopper(
                after: -1, row: state.charBlockY, room: state.room, cameraRoom: cameraRoom
            )

            if let links = world.roomLinks(state.room) {
                if state.charBlockX == Geometry.roomColumns - 1, state.charX > 130,
                   links.right > 0 {
                    world.activateChopper(
                        after: -1, row: state.charBlockY,
                        room: links.right, cameraRoom: cameraRoom
                    )
                }
                if state.charBlockX == 0, state.charX < 5, links.left > 0 {
                    world.activateChopper(
                        after: -1, row: state.charBlockY,
                        room: links.left, cameraRoom: cameraRoom
                    )
                }
            }
        }
        tryChoppers(
            x: state.charBlockX, y: state.charBlockY,
            state: &state, world: &world, effects: &effects
        )
    }

    /// `Fighter.tryChoppers` — a chopper can be on the actor’s own column or the one in front.
    static func tryChoppers(
        x: Int, y: Int,
        state: inout ActorState, world: inout World, effects: inout [ActorEffect]
    ) {
        // Bones do not bleed.
        if state.charName == "skeleton" { return }

        for column in [x, x + 1] {
            guard let ref = world.resolve(x: column, y: y, room: state.room),
                  let chopper = world.chopper(at: ref)
            else { continue }
            tryChopper(chopper, at: ref, column: column, state: &state, world: &world,
                       effects: &effects)
        }
    }

    /// `Fighter.tryChopperTile`.
    ///
    /// Only steps 1 to 3 can cut, and step 3 is the frame the blades meet. A turning actor is
    /// spared — the reference excludes `turn` explicitly, and it is the only action excluded.
    static func tryChopper(
        _ chopper: Chopper, at ref: TileRef, column: Int,
        state: inout ActorState, world: inout World, effects: inout [ActorEffect]
    ) {
        guard chopper.step >= 1, chopper.step <= Chopper.cutStep else { return }
        guard state.action != "turn" else { return }
        guard inChopDistance(state, tileColumn: column, levelAtlas: world.level.atlasName) else {
            return
        }

        world.markChopperBloody(at: ref)
        guard state.isAlive else { return }

        dieChopper(&state, effects: &effects)
        effects.append(.sound(.halvedByChopper))
        FallCycle.alignToTile(&state, to: ref)
        // The two halves fall apart: five units when he faced left, nine when he faced right.
        state.charX += state.charFace == -1 ? -5 : -9
    }

    /// `Fighter.dieChopper`.
    public static func dieChopper(_ state: inout ActorState, effects: inout [ActorEffect]) {
        guard state.isAlive, state.charName != "skeleton" else { return }
        Combat.die(&state, action: "halve", effects: &effects)
    }
}
