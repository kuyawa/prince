/// The mutable state of one actor — the `char*` field set plus the program counter.
///
/// Port source: `reference/PrinceJS/src/Actor.js`, `Fighter.js` and `Kid.js`.
///
/// A value type on purpose. The simulation is a pure fold over this struct, so a test
/// can snapshot it, compare two runs, or step it backwards from a golden trace. Nothing
/// here touches SpriteKit, and nothing here is a reference to anything.
public struct ActorState: Sendable, Equatable {
    /// Which sprite family this actor draws from — `"kid"`, `"guard"`, `"skeleton"`, and so
    /// on. Selects the atlas prefix and the animation table.
    public var charName: String

    // MARK: - The program

    /// The sequence currently executing. Named `action` in the reference.
    public var action: String

    /// Cursor into the current sequence. `_seqpointer` in the reference.
    public var sequencePointer: Int

    /// Set `true` by `step` and cleared by `CMD_FRAME`. The dispatch loop spins on it.
    public var isProcessing: Bool

    // MARK: - Position
    //
    // See CoordinateSpace: charX is in x-units (140 per room), charY is in pixels
    // (189 per room). They are not the same unit and must never be mixed.

    public var charX: Int
    public var charY: Int

    /// `+1` facing right, `-1` facing left.
    public var charFace: Int

    /// World offset of the current room. `baseY` carries a `+3` from `Fighter.updateBase`.
    public var baseX: Int
    public var baseY: Int
    public var room: Int

    /// Derived from the actor's *foot*, not its origin. Recomputed by `updateBlockPosition`.
    public var charBlockX: Int
    public var charBlockY: Int

    // MARK: - The current frame

    public var charFrame: Int

    /// Per-frame draw offsets within the sequence, from the frame definition.
    public var charFdx: Int
    public var charFdy: Int

    /// Bits 0–4 of `fcheck`: the foot's sub-tile column, in x-units.
    public var charFfoot: Int

    /// Bit 7 of `fcheck`.
    public var charFood: Bool

    /// Bit 6 of `fcheck`.
    public var charFcheck: Bool

    /// Bit 5 of `fcheck`.
    public var charFthin: Bool

    /// Whether this frame has a sword overlay (`fsword` present).
    public var hasSwordFrame: Bool
    public var swordFrame: Int
    public var swordDx: Int
    public var swordDy: Int

    // MARK: - Fighter

    public var charXVel: Int
    public var charYVel: Int

    /// Set by `ACT` (249). `updateAcceleration` applies gravity only when it is 4.
    public var actionCode: Int

    public var isAlive: Bool
    public var swordDrawn: Bool

    /// Read by `IFWTLESS` (247) to choose a floating variant of the current action.
    public var isInFloat: Bool

    /// Set by `checkFloor`'s fall branch. Used by `checkBarrier` (remaining M3 work).
    public var isInFallDown: Bool

    /// Set by `startFall` for the actions that need an immediate floor probe, and consumed by
    /// `checkFloor`'s falling branch.
    ///
    /// ```js
    /// case 3: case 4:
    ///   if (this.actionCode === 3 && !this.checkFloorStepFall) return;   // stepfall skips
    ///   this.checkFloorStepFall = false;
    ///   this.checkFall(tile);
    /// ```
    ///
    /// Without this, a scripted `stepfall` lands on the first tick: its `charY` has not moved
    /// yet, so `charY + 6 >= floorY` is already true.
    public var checkFloorStepFall: Bool

    /// How many loose boards the actor has fallen through. 0 or 1 is survivable;
    /// more is fatal on landing (`Fighter.land`).
    public var fallingBlocks: Int

    // MARK: - Control layer
    //
    // Read and written by `Behaviour.update`. Each `allow…` flag latches false when an
    // action starts and is re-armed once the corresponding key is released, which is how
    // the reference stops one held key from repeating an action every tick.

    public var allowCrawl: Bool
    public var allowAdvance: Bool
    public var allowRetreat: Bool
    public var allowBlock: Bool
    public var allowStrike: Bool

    /// Set by `Kid.step` when the actor is pressed against a ledge and must test the
    /// ground ahead before committing.
    public var charRepeat: Bool

    /// Counts frames of swinging while hanging. Read by `checkLedgeSwing`.
    public var ledgeSwing: Int

    public var blockEngarde: Bool
    public var grabWait: Bool
    public var hasSword: Bool
    public var flee: Bool

    // MARK: - Init

    /// Places an actor at a spawn location.
    ///
    /// **This reproduces `Fighter`'s constructor exactly**, including
    /// `location % 10` / `location / 10`. That is the *actor* convention, and it
    /// disagrees with the 1-based event convention by one position within each row —
    /// ARCHITECTURE.md open question 8. It is reproduced faithfully here so that
    /// behaviour matches the port source, and isolated here so that resolving the
    /// question changes exactly one expression.
    public init(
        location: Int,
        room: Int,
        face: Int,
        action: String = "stand",
        charName: String = "kid"
    ) {
        let blockX = location % 10
        let blockY = location / 10

        self.charName = charName
        self.action = action
        self.sequencePointer = 0
        self.isProcessing = false

        self.charBlockX = blockX
        self.charBlockY = blockY
        self.charX = CoordinateSpace.x(fromBlockX: blockX)
        self.charY = CoordinateSpace.y(fromBlockY: blockY)
        self.charFace = face
        self.baseX = 0
        self.baseY = 0
        self.room = room

        self.charFrame = 0
        self.charFdx = 0
        self.charFdy = 0
        self.charFfoot = 0
        self.charFood = false
        self.charFcheck = false
        self.charFthin = false
        self.hasSwordFrame = false
        self.swordFrame = 0
        self.swordDx = 0
        self.swordDy = 0

        self.charXVel = 0
        self.charYVel = 0
        self.actionCode = 1
        self.isAlive = true
        self.swordDrawn = false
        self.isInFloat = false
        self.isInFallDown = false
        self.checkFloorStepFall = false
        self.fallingBlocks = 0

        self.allowCrawl = true
        self.allowAdvance = true
        self.allowRetreat = true
        self.allowBlock = true
        self.allowStrike = true
        self.charRepeat = false
        self.ledgeSwing = 0
        self.blockEngarde = false
        self.grabWait = false
        self.hasSword = false
        self.flee = false
    }

    // MARK: - Reference semantics

    /// Mirrors the JavaScript `action` **setter**, which resets the cursor:
    ///
    /// ```js
    /// set action(value) { this._action = value; this._seqpointer = 0; }
    /// ```
    ///
    /// `CMD_GOTO` does *not* go through the setter — it assigns `_action` and
    /// `_seqpointer` directly. That distinction is load-bearing: using the setter in
    /// `GOTO` would restart every sequence from the top and loop forever.
    public mutating func beginAction(_ name: String) {
        action = name
        sequencePointer = 0
    }

    /// `Actor.updateCharFrame` — unpack the frame definition's `fcheck`.
    ///
    /// Absent fields map to zero. The reference reads `undefined` and would carry NaN
    /// into every later offset; that path is unreachable because referenced frames are
    /// always complete, but an `Int` model still has to choose something.
    public mutating func applyFrameDefinition(_ definition: FrameDef?) {
        guard let definition else { return }
        charFdx = definition.dx ?? 0
        charFdy = definition.dy ?? 0

        let check = definition.check ?? FrameCheck(rawValue: 0)
        charFfoot = Int(check.foot)
        charFood = check.isHalfPixelOffset
        charFcheck = check.isCheckActive
        charFthin = check.isThin

        hasSwordFrame = definition.swordFrame != nil
    }

    /// The pure half of `Fighter.updateBlockXY`:
    ///
    /// ```js
    /// let footX = this.charX + this.charFdx * this.charFace - this.charFfoot * this.charFace;
    /// let footY = this.charY + this.charFdy;
    /// this.charBlockX = convertXtoBlockX(footX);
    /// this.charBlockY = Math.min(convertYtoBlockY(footY), 2);
    /// ```
    ///
    /// The `min(…, 2)` clamp is the engine's, not a safety net: an actor can never be
    /// in a row below the room's three.
    ///
    /// The room-wrapping half of `updateBlockXY` needs the level graph, so it takes a world:
    ///
    /// ```js
    /// if (this.charBlockX < 0) {
    ///   if (this.action === "highjump" && this.faceR()) return;
    ///   let leftRoom = this.level.rooms[this.room].links.left;
    ///   if (leftRoom > 0) {
    ///     this.charX += 140;      // one room width, in x-units
    ///     this.baseX -= 320;      // one room width, in screen pixels
    ///     this.charBlockX = 9;
    ///     this.room = leftRoom;
    ///   }
    /// }
    /// ```
    ///
    /// **`charX` stays room-local.** Crossing a boundary shifts it by a whole room (140
    /// x-units) so the actor appears at the opposite edge of the room it just entered.
    public mutating func updateBlockPosition(world: (any ActorWorldQuery)? = nil) {
        let footX = charX + charFdx * charFace - charFfoot * charFace
        let footY = charY + charFdy

        let previousBlockY = charBlockY
        charBlockX = CoordinateSpace.blockX(fromX: footX)
        charBlockY = min(CoordinateSpace.blockY(fromY: footY), 2)

        updateFallingBlocks(previousBlockY: previousBlockY)
        transitionRoomIfNeeded(world: world)
    }

    /// `Fighter.updateFallingBlocks` — counts the floor levels the actor has dropped through.
    /// More than one is fatal on landing.
    private mutating func updateFallingBlocks(previousBlockY: Int) {
        guard isInFallDown else { return }
        if charBlockY != previousBlockY { fallingBlocks += 1 }
    }

    private mutating func transitionRoomIfNeeded(world: (any ActorWorldQuery)?) {
        // Climbing manages its own position.
        if action == "climbup" || action == "climbdown" { return }

        if charBlockX < 0 {
            if action == "highjump" && charFace == 1 { return }
            guard let links = world?.roomLinks(room), links.left > 0 else { return }
            charX += CoordinateSpace.xUnitsPerRoom
            baseX -= Geometry.screenWidth
            charBlockX = Geometry.roomColumns - 1
            room = links.left
        } else if charBlockX >= Geometry.roomColumns {
            if action == "highjump" && charFace == -1 { return }
            guard let links = world?.roomLinks(room), links.right > 0 else { return }
            charX -= CoordinateSpace.xUnitsPerRoom
            baseX += Geometry.screenWidth
            charBlockX = 0
            room = links.right
        }
    }
}
