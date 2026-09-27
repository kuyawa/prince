/// Builds a `RenderDescription` for one room.
///
/// Port source: `reference/PrinceJS/src/LevelBuilder.js#buildTile` and `#addTile`, plus the
/// tile classes in `src/tiles/`.
///
/// This lives in `PoPCore` rather than the host because it is game logic: which frame a tile
/// draws, and whether it draws in front of or behind an actor, is part of the game.
public enum RoomRenderer {
    /// `Level.js` sets `back.z = 10` and `front.z = 30`; actors sit at 20.
    ///
    /// The front layer drawing **over** the actor is what puts the Prince behind a wall's
    /// foreground detail instead of in front of it.
    public static let tileBackgroundZ = 10
    public static let tileBackgroundDetailZ = 11
    public static let actorZ = 20
    /// The sword overlay. `Fighter`'s constructor sets `this.sword.z = 21`.
    public static let swordZ = 21
    public static let tileForegroundZ = 30
    /// Detail drawn on top of the foreground — a gate's moving panel.
    public static let tileForegroundDetailZ = 31

    /// Tile sprites overhang their grid cell by this much. `addTile`: `y * BLOCK_HEIGHT - 13`.
    public static let tileOverhang = Geometry.tileOverhang

    public static func describe(
        world: World,
        room: Int,
        actors: [ActorState] = []
    ) -> RenderDescription {
        describe(level: world.level, world: world, room: room, actors: actors)
    }

    public static func describe(
        level: LevelRuntime,
        world: World? = nil,
        room: Int,
        actors: [ActorState] = []
    ) -> RenderDescription {
        let prefix = level.data.type == .dungeon ? "dungeon" : "palace"
        var sprites: [SpriteInstance] = []

        for strip in strips(for: room, in: level) {
            sprites.append(contentsOf: Self.sprites(
                for: strip, level: level, world: world, prefix: prefix
            ))
        }

        for actor in actors {
            sprites.append(contentsOf: describe(actor))
        }

        return RenderDescription(room: room, sprites: sprites)
    }

    /// Every sprite one band of tiles contributes, placed relative to the room being drawn.
    static func sprites(
        for strip: Strip,
        level: LevelRuntime,
        world: World?,
        prefix: String
    ) -> [SpriteInstance] {
        var sprites: [SpriteInstance] = []

        for row in strip.rows {
            for column in strip.columns {
                let tile = level.tile(x: column, y: row, room: strip.room)
                let baseX = column * Geometry.blockWidth + strip.dx
                let baseY = row * Geometry.blockHeight - tileOverhang + strip.dy

                for part in tileParts(
                    for: tile, level: level, world: world, room: strip.room,
                    column: column, row: row, prefix: prefix
                ) {
                    sprites.append(SpriteInstance(
                        frameName: part.frame,
                        x: baseX + part.dx,
                        y: baseY + part.dy,
                        anchor: .topLeft,
                        z: part.z,
                        clipTop: part.clipTop,
                        atlas: part.atlas
                    ))
                }
            }
        }

        return sprites
    }

    /// A band of tiles that lands on this room's screen, and where it lands.
    ///
    /// **The reference builds every room of the level into the same two display lists and lets
    /// the camera do the cropping.** `LevelBuilder.buildFromJSON` calls `buildRoom` for all of
    /// them, and `Level.addTile` appends to `level.back` and `level.front` whichever room the
    /// tile belongs to — nothing hides a neighbouring room's sprites. `Level.js#checkGates`
    /// looks as though it does, but `Gate.isVisible` only mutes the gate's *sound*.
    ///
    /// It matters because a tile cel is 60 px wide inside a 32 px cell: the art overhangs 28 px
    /// past its own cell on the right, and a wall's backing frame and a gate's moving panel are
    /// drawn 32 px into the *next* cell again. A room therefore paints into its neighbours'
    /// screens, and the leftmost 28 px of every room's screen belongs to the left neighbour's
    /// last column — a wall's side face, or the edge of a gate that is standing open.
    ///
    /// Three of the four neighbours can reach this room's 320 x 200 window:
    ///
    /// - the room to the **left**, column 9, at `x = -32`, of which 28 px shows;
    /// - the room **above**, row 2, at `y = -76`, of which 3 px shows below the top edge;
    /// - the room **below**, row 0, at `y = 176`, of which 16 px shows above the status bar.
    ///
    /// The room to the right starts at `x = +320` and every part of a tile is offset rightwards
    /// from there, so it can never reach the screen. It is left out rather than drawn invisible.
    ///
    /// Order matters, because the three strips collide: a later sprite draws over an earlier one
    /// at the same z. `LevelBuilder` walks the map's bottom row first and left to right within a
    /// row, so the room below comes before the room to the left, and the room above comes after
    /// this one.
    static func strips(for room: Int, in level: LevelRuntime) -> [Strip] {
        var strips = [Strip(room: room, dx: 0, dy: 0,
                            columns: 0..<Geometry.roomColumns, rows: 0..<Geometry.roomRows)]

        guard let links = level.placement(of: room)?.links else { return strips }

        // The map row below this one is built first.
        if links.down > 0, level.placement(of: links.down) != nil {
            strips.insert(Strip(room: links.down, dx: 0, dy: Geometry.roomHeight,
                                columns: 0..<Geometry.roomColumns, rows: 0..<1), at: 0)
        }

        // Then, within the same map row, left to right.
        if links.left > 0, level.placement(of: links.left) != nil {
            strips.insert(Strip(room: links.left, dx: -Geometry.roomWidth, dy: 0,
                                columns: (Geometry.roomColumns - 1)..<Geometry.roomColumns,
                                rows: 0..<Geometry.roomRows), at: 0)
        }

        // The map row above is built last of all.
        if links.up > 0, level.placement(of: links.up) != nil {
            strips.append(Strip(room: links.up, dx: 0, dy: -Geometry.roomHeight,
                                columns: 0..<Geometry.roomColumns,
                                rows: (Geometry.roomRows - 1)..<Geometry.roomRows))
        }

        return strips
    }

    /// One band of a room's tiles, placed relative to the room being drawn.
    struct Strip: Equatable {
        /// The room the tiles belong to. Tile state and `dungeonWallFrames` both read the
        /// neighbours of a tile in *its own* room, not in the room being drawn.
        var room: Int
        var dx: Int
        var dy: Int
        var columns: Range<Int>
        var rows: Range<Int>
    }

    // MARK: - Frame selection

    /// One sprite a tile contributes: a frame name plus an offset within the tile's cell.
    struct TilePart: Equatable {
        var frame: String
        var dx: Int = 0
        var dy: Int = 0
        var z: Int
        /// Pixels cut from the top. Only gates use this.
        var clipTop: Int = 0
        /// A sheet other than the level's own. Only the potion bubbles need this.
        var atlas: String? = nil
    }

    /// The three sprite names a plain tile contributes.
    struct TileFrames: Equatable {
        var background: String
        /// The `<element>_<modifier>` child that space and floor tiles add to their back
        /// sprite. It carries the tile's actual variation.
        var backgroundDetail: String?
        var foreground: String
    }

    /// Every sprite a tile draws, in the reference's back/front layering.
    ///
    /// Gates are the exception to the three-sprite shape: they add a `<prefix>_gate` child to
    /// the back and a `<prefix>_gate_fg` child at `(32, 16)` to the front, and those two are
    /// what slide upward as the gate rises.
    static func tileParts(
        for tile: Tile,
        level: LevelRuntime,
        world: World?,
        room: Int,
        column: Int,
        row: Int,
        prefix: String
    ) -> [TilePart] {
        if tile.kind == .gate {
            let ref = TileRef(room: room, x: column, y: row)
            let gate = world?.gate(at: ref) ?? Gate(modifier: tile.modifier)
            let clip = -gate.position

            return [
                TilePart(frame: "\(prefix)_4", z: tileBackgroundZ),
                TilePart(frame: "\(prefix)_gate", z: tileBackgroundDetailZ, clipTop: clip),
                TilePart(frame: "\(prefix)_4_fg", z: tileForegroundZ),
                TilePart(frame: "\(prefix)_gate_fg", dx: 32, dy: 16,
                         z: tileForegroundDetailZ, clipTop: clip),
            ]
        }

        if tile.kind == .exitRight {
            let ref = TileRef(room: room, x: column, y: row)
            let door = world?.state.trob(at: ref)?.exitDoor
            let clip = door?.clipTop ?? 0

            var parts = [
                TilePart(frame: "\(prefix)_17", z: tileBackgroundZ),
                // ExitDoor.js: make.sprite(10, 12, key, key + "_door")
                TilePart(frame: "\(prefix)_door", dx: 10, dy: 12,
                         z: tileBackgroundDetailZ, clipTop: clip),
                TilePart(frame: "\(prefix)_17_fg", z: tileForegroundZ),
            ]
            // The front door graphic only appears once the Prince starts climbing.
            if door?.isMasked == true {
                parts.append(TilePart(frame: "\(prefix)_door_fg", z: tileForegroundDetailZ))
            }
            return parts
        }

        if tile.kind == .looseBoard {
            let ref = TileRef(room: room, x: column, y: row)
            let board = world?.state.trob(at: ref)?.looseBoard ?? LooseBoard()

            // Loose.js swaps the BACK frame as the board shakes and then drops away.
            let background: String
            switch board.phase {
            case .shaking:
                // `this.key + Loose.frames[this.step]`, and frames run "_loose_1" ... "_loose_8".
                background = "\(prefix)_loose_\(min(board.step + 1, LooseBoard.shakeFrames))"
            case .falling:
                background = "\(prefix)_falling"
            case .inactive:
                background = "\(prefix)_11"
            }

            return [
                TilePart(frame: background, z: tileBackgroundZ),
                TilePart(frame: "\(prefix)_11_fg", z: tileForegroundZ),
            ]
        }

        if tile.kind == .spikes {
            // Spikes.js gives the field its own back and front child sprites, and *those* are
            // what the animation swaps; the parent cells never change. The frame the modifier
            // selects is aliased onto the field’s own `frame`, so a retracted field draws
            // `_2_0` and an emerging one `_2_1` through `_2_5`.
            let ref = TileRef(room: room, x: column, y: row)
            let field = world?.state.trob(at: ref)?.spikes ?? Spikes(modifier: tile.modifier)
            let frame = field.frameIndex

            return [
                TilePart(frame: "\(prefix)_2", z: tileBackgroundZ),
                TilePart(frame: "\(prefix)_2_\(frame)", z: tileBackgroundDetailZ),
                TilePart(frame: "\(prefix)_2_fg", z: tileForegroundZ),
                TilePart(frame: "\(prefix)_2_\(frame)_fg", z: tileForegroundDetailZ),
            ]
        }

        if tile.kind == .chopper {
            // Chopper.js: the blades are a back child and a front child, each cycling through
            // frames 0 to 5, and the blood stain is a child of the *front* at (12, 41).
            let ref = TileRef(room: room, x: column, y: row)
            let chopper = world?.state.trob(at: ref)?.chopper ?? Chopper()
            let frame = chopper.frameIndex
            var parts = [
                TilePart(frame: "\(prefix)_chopper_\(frame)", z: tileBackgroundDetailZ),
                TilePart(frame: "\(prefix)_chopper_\(frame)_fg", z: tileForegroundZ),
            ]
            if chopper.showsBlood {
                parts.append(TilePart(
                    frame: "chopper-blood_\(frame)", dx: 12, dy: 41,
                    z: tileForegroundDetailZ, atlas: "general"
                ))
            }
            return parts
        }

        if tile.kind == .potion {
            // Potion.js: the bottle is a *suffix on the front frame* — `dungeon_10_fg_1` —
            // and the bubbles are a child of the front at (25, 53), or 49 for the three wider
            // bottles. The bubbles live in the `general` atlas, not the level’s.
            let ref = TileRef(room: room, x: column, y: row)
            let potion = world?.state.trob(at: ref)?.potion
            let variant = potion?.modifier ?? max(1, min(5, tile.modifier))
            let step = potion?.step ?? 0
            let color = potion?.color ?? Potion.bubbleColors[variant - 1]
            let bottleY = (variant > 1 && variant < 5) ? 49 : 53

            return [
                TilePart(frame: "\(prefix)_10", z: tileBackgroundZ),
                TilePart(frame: "\(prefix)_10_fg_\(variant)", z: tileForegroundZ),
                TilePart(frame: "bubble_\(step + 1)_\(color)", dx: 25, dy: bottleY,
                         z: tileForegroundDetailZ, atlas: "general"),
            ]
        }

        if tile.kind == .sword {
            // Sword.js swaps the *back* frame for a `_bright` variant when the blade glints.
            let ref = TileRef(room: room, x: column, y: row)
            let sword = world?.state.trob(at: ref)?.sword ?? Sword()
            let background = sword.isBright ? "\(prefix)_22_bright" : "\(prefix)_22"

            return [
                TilePart(frame: background, z: tileBackgroundZ),
                TilePart(frame: "\(prefix)_22_fg", z: tileForegroundZ),
            ]
        }

        let frames = frames(
            for: tile, level: level, room: room, column: column, row: row, prefix: prefix
        )
        var parts = [TilePart(frame: frames.background, z: tileBackgroundZ)]
        if let detail = frames.backgroundDetail {
            parts.append(TilePart(frame: detail, z: tileBackgroundDetailZ))
        }
        parts.append(TilePart(frame: frames.foreground, z: tileForegroundZ))
        return parts
    }

    /// `LevelBuilder.buildTile`'s switch, reduced to the part that decides frame names.
    ///
    /// Several tile classes hand a *different* element to `Base` than the one stored in the
    /// level. `Tile.Mirror` passes `TILE_FLOOR`, so a mirror draws as floor and there is no
    /// `dungeon_13` frame in the atlas at all — asking for one silently renders nothing.
    static func frames(
        for tile: Tile,
        level: LevelRuntime,
        room: Int,
        column: Int,
        row: Int,
        prefix: String
    ) -> TileFrames {
        let element = tile.kind.rawValue
        let renderElement = tile.kind == .mirror ? TileKind.floor.rawValue : element

        switch tile.kind {
        case .wall where level.data.type == .dungeon:
            return dungeonWallFrames(
                tile: tile, level: level, room: room, column: column, row: row, prefix: prefix
            )

        case .space, .floor:
            // Base's two sprites, plus the element_modifier child added to \`back\`.
            return TileFrames(
                background: "\(prefix)_\(renderElement)",
                backgroundDetail: "\(prefix)_\(element)_\(tile.modifier)",
                foreground: "\(prefix)_\(renderElement)_fg"
            )

        case .bottomBigPillar:
            // \`default\`: a bottom pillar is "low" unless a top pillar sits directly above it.
            let above = level.tile(x: column, y: row - 1, room: room).kind
            let suffix = above == .topBigPillar ? "" : "_low"
            return TileFrames(
                background: "\(prefix)_\(renderElement)\(suffix)",
                backgroundDetail: nil,
                foreground: "\(prefix)_\(renderElement)_fg\(suffix)"
            )

        default:
            return TileFrames(
                background: "\(prefix)_\(renderElement)",
                backgroundDetail: nil,
                foreground: "\(prefix)_\(renderElement)_fg"
            )
        }
    }

    /// Dungeon walls pick one of 212 pre-drawn frames named for the wall's *shape*, so an edge
    /// knows whether its neighbours are walls:
    ///
    /// ```js
    /// if (this.getTileAt(x - 1, y, id) === TILE_WALL) wallType = "W"; else wallType = "S";
    /// wallType += "W";
    /// if (this.getTileAt(x + 1, y, id) === TILE_WALL) wallType += "W"; else wallType += "S";
    /// tile.front.frameName = wallType + "_" + tileSeed;      // tileSeed = tileNumber + roomId
    /// if (wallType.charAt(2) === "S") {
    ///   tile.back.frameName = tile.key + "_wall_" + t.modifier;
    /// }
    /// ```
    ///
    /// Four shapes (WWW, WWS, SWW, SWS) x 53 seeds = the 212 wall frames in `dungeon.json`.
    ///
    /// **Palaces are different** — the reference builds a colour bitmap from
    /// `wallPattern[roomId]`, which the LCG generates, and adds a `W_<seed>` child. Only the
    /// child is reproduced here; the colour overlay is ARCHITECTURE.md open question 12.
    private static func dungeonWallFrames(
        tile: Tile,
        level: LevelRuntime,
        room: Int,
        column: Int,
        row: Int,
        prefix: String
    ) -> TileFrames {
        let wallToTheLeft = level.tile(x: column - 1, y: row, room: room).kind == .wall
        let wallToTheRight = level.tile(x: column + 1, y: row, room: room).kind == .wall

        var shape = wallToTheLeft ? "W" : "S"
        shape += "W"
        shape += wallToTheRight ? "W" : "S"

        let seed = row * Geometry.roomColumns + column + room
        return TileFrames(
            background: wallToTheRight ? "\(prefix)_\(tile.kind.rawValue)" : "\(prefix)_wall_\(tile.modifier)",
            backgroundDetail: nil,
            foreground: "\(shape)_\(seed)"
        )
    }

    /// `Actor.updateCharPosition`.
    ///
    /// **The art faces left, so facing right is the mirrored case.** `Actor`'s constructor does
    /// `this.scale.x *= -charFace`, which is 1 for a left-facing actor and -1 for a right-facing
    /// one. The port had this the other way round, and a Prince who walks backwards is exactly
    /// what that looks like.
    ///
    /// The mirror is about the sprite's anchor, so the box a right-facing actor occupies is
    /// `[x - width, x]` rather than `[x, x + width]`. That is not an accident to be corrected:
    /// `Fighter.getCharBounds` subtracts `width - 5` when facing right for precisely that reason,
    /// and the port's `charBounds` does the same. Moving the sprite would put the drawing and the
    /// collision out of step.
    ///
    /// ```js
    /// let tempx = this.charX + this.charFdx * this.charFace;
    /// if ((this.charFood && this.faceL()) || (!this.charFood && this.faceR())) tempx += 0.5;
    /// this.x = this.baseX + Utils.convertX(tempx);
    /// this.y = this.baseY + this.charY + this.charFdy;   // baseY carries +3
    /// ```
    public static func describe(_ actor: ActorState) -> [SpriteInstance] {
        var tempx = Double(actor.charX + actor.charFdx * actor.charFace)

        // The half-pixel parity correction from fcheck bit 7. It only ever reaches the
        // renderer — charX itself stays integral.
        let halfPixel = (actor.charFood && actor.charFace == -1)
            || (!actor.charFood && actor.charFace == 1)
        if halfPixel { tempx += 0.5 }

        let x = CoordinateSpace.screenX(fromX: tempx)

        // Fighter.updateBase adds 3 to baseY.
        let y = 3 + actor.charY + actor.charFdy

        var sprites = [SpriteInstance(
            frameName: "\(actor.charName)-\(actor.charFrame)",
            x: x, y: y,
            anchor: .bottomLeft,
            z: actorZ,
            flippedHorizontally: actor.charFace == 1
        )]

        // `Fighter`'s constructor adds the splash as a *child* of the actor, anchored bottom-left
        // like its parent and offset (-6, -15). So it inherits the actor's flip — which is why it
        // is drawn with the same `flippedHorizontally`, and why a mirror-image Prince bleeds on the
        // other side. Its frame comes from the `general` atlas, not the actor's own.
        if actor.isSplashVisible {
            sprites.append(SpriteInstance(
                frameName: Splash.frameName(for: actor),
                x: x + Splash.offsetX,
                y: y + actor.splashOffsetY,
                anchor: .bottomLeft,
                z: actorZ,
                flippedHorizontally: actor.charFace == 1,
                atlas: "general",
                tint: actor.splashTint
            ))
        }

        // `Fighter.updateSwordPosition` — the overlay is its own sprite, drawn just above the
        // actor. Note there is no `swordDrawn` test: whether the frame carries an `fsword` *is*
        // the sword-drawn state, so a frame without one shows no blade however the flag reads.
        if actor.isActive, actor.hasSwordFrame {
            sprites.append(SpriteInstance(
                frameName: "sword\(actor.swordFrame)",
                x: x + actor.swordDx * actor.charFace,
                y: y + actor.swordDy,
                anchor: .bottomLeft,
                z: swordZ,
                flippedHorizontally: actor.charFace == 1
            ))
        }
        return sprites
    }
}
