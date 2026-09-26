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
}
