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
    public static let tileForegroundZ = 30

    /// Tile sprites overhang their grid cell by this much. `addTile`: `y * BLOCK_HEIGHT - 13`.
    public static let tileOverhang = 13

    public static func describe(
        level: LevelRuntime,
        room: Int,
        actors: [ActorState] = []
    ) -> RenderDescription {
        var sprites: [SpriteInstance] = []
        let prefix = level.data.type == .dungeon ? "dungeon" : "palace"

        for row in 0..<Geometry.roomRows {
            for column in 0..<Geometry.roomColumns {
                let tile = level.tile(x: column, y: row, room: room)
                let x = column * Geometry.blockWidth
                let y = row * Geometry.blockHeight - tileOverhang
                let frames = frames(
                    for: tile, level: level, room: room, column: column, row: row, prefix: prefix
                )

                sprites.append(SpriteInstance(
                    frameName: frames.background, x: x, y: y,
                    anchor: .topLeft, z: tileBackgroundZ
                ))
                if let detail = frames.backgroundDetail {
                    sprites.append(SpriteInstance(
                        frameName: detail, x: x, y: y,
                        anchor: .topLeft, z: tileBackgroundDetailZ
                    ))
                }
                sprites.append(SpriteInstance(
                    frameName: frames.foreground, x: x, y: y,
                    anchor: .topLeft, z: tileForegroundZ
                ))
            }
        }

        for actor in actors {
            sprites.append(contentsOf: describe(actor))
        }

        return RenderDescription(room: room, sprites: sprites)
    }

    // MARK: - Frame selection

    /// The three sprite names a tile contributes.
    struct TileFrames: Equatable {
        var background: String
        /// The `<element>_<modifier>` child that space and floor tiles add to their back
        /// sprite. It carries the tile's actual variation.
        var backgroundDetail: String?
        var foreground: String
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

        return [SpriteInstance(
            frameName: "\(actor.charName)-\(actor.charFrame)",
            x: x, y: y,
            anchor: .bottomLeft,
            z: actorZ,
            flippedHorizontally: actor.charFace == -1
        )]
    }
}
