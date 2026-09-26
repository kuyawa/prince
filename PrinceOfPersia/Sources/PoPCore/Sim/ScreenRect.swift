/// Screen-space rectangles, and the actor and tile collisions built from them.
///
/// Port source: `reference/PrinceJS/src/Fighter.js#getCharBounds`, `Kid.js#getCharBoundsAbs`,
/// `tiles/Base.js#getBounds`/`#getBoundsAbs`, and `Phaser.Rectangle.intersects`.
///
/// ## Why this exists at all
///
/// This is open question 11, and it stayed open for most of the port because it looked
/// unanswerable: `Base.getBounds` computes `x = roomX * 32 + 40`, mixing a cell index with a screen
/// pixel offset, and `getCharBounds` reads the live Phaser sprite’s size. Neither has an obvious
/// engine-unit equivalent.

///
/// It is answerable, and `SpriteMetrics` is what answers it. A Phaser sprite is as wide and tall as
/// its current cel, and the cels are in the atlas JSON. So the collision is genuinely screen-space
/// geometry over measured cel sizes — not a physics model to be re-derived, just arithmetic to be
/// transcribed.
///
/// ## The one thing that is not transcription
///
/// `roomIndex * 320` appears in both the tile’s `x` and the actor’s `baseX`, and cancels. Every
/// rectangle here is therefore **room-local**, which is the same convention the rest of the port
/// uses and the only one that means anything when the camera can be in one room at a time.
public struct ScreenRect: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var right: Int { x + width }
    public var bottom: Int { y + height }

    /// `Phaser.Rectangle.intersects`.
    ///
    /// ```js
    /// if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0) { return false; }
    /// return !(a.right < b.x || a.bottom < b.y || a.x > b.right || a.y > b.bottom);
    /// ```
    ///
    /// Two notes that matter, and the second is the counter-intuitive one.
    ///
    /// A rectangle with no area **never** intersects anything — which is how a tile whose cel is
    /// missing from the atlas stops colliding instead of colliding with the whole room.
    ///
    /// And because the four comparisons are strict, two rectangles that merely **share an edge are
    /// not separated**, so they intersect: an equal `right` and `x` still counts. Reading it the
    /// other way moves every wall contact by a pixel.
    public func intersects(_ other: ScreenRect) -> Bool {
        guard width > 0, height > 0, other.width > 0, other.height > 0 else { return false }
        return !(right < other.x || bottom < other.y || x > other.right || y > other.bottom)
    }
}

// MARK: - Tiles

public extension Tile {
    /// The cel a tile draws its back sprite from, which is what decides its collision width.
    ///
    /// `Tile.Mirror` hands `TILE_FLOOR` to `Base`, so a mirror is as wide as a floor tile — there
    /// is no `dungeon_13` cel at all. Everything else uses its own element.
    var collisionElement: Int { kind == .mirror ? TileKind.floor.rawValue : kind.rawValue }

    /// `Tile.Base.getBounds` — `Rectangle(roomX * 32 + 40, roomY * 63, 4, 63)`.
    ///
    /// Four pixels wide, forty into the cell — which is eight pixels *past* a 32-pixel cell, in
    /// the next one. That is not a typo in the reference and it is not one here. It is the
    /// rectangle that catches an actor walking into a wall from the left.
    func screenBounds(column: Int, row: Int) -> ScreenRect {
        ScreenRect(
            x: column * Geometry.blockWidth + 40,
            y: row * Geometry.blockHeight,
            width: 4,
            height: Geometry.blockHeight
        )
    }

    /// `Tile.Base.getBoundsAbs` — `Rectangle(tile.x, tile.y, this.width, 63)`.
    ///
    /// Note it disagrees with `screenBounds` on purpose: this one uses the tile’s own origin,
    /// which carries the 13-pixel overhang, and the full cel width. Its height is a flat 63, not
    /// the cel height.
    func screenBoundsAbs(column: Int, row: Int, atlas: String) -> ScreenRect {
        ScreenRect(
            x: column * Geometry.blockWidth,
            y: row * Geometry.blockHeight - Geometry.tileOverhang,
            width: SpriteMetrics.width(
                atlas: atlas, frame: "\(atlas)_\(collisionElement)"
            ) ?? 0,
            height: Geometry.blockHeight
        )
    }
}

public extension Tile {
    /// `Tile.Base.centerX` — the centre of the tile's *cel*, not of its 32-pixel cell.
    ///
    /// For a dungeon tile that is `column * 32 + 30`, because the cel is 60 wide and packed at the
    /// cell origin. It is 14 pixels right of where the cell looks like it ends, and `chopDistance`
    /// and `checkBarrier` both compare against it.
    func centerX(column: Int, atlas: String) -> Int {
        let width = SpriteMetrics.width(
            atlas: atlas, frame: "\(atlas)_\(collisionElement)"
        ) ?? 0
        return column * Geometry.blockWidth + width / 2
    }
}

// MARK: - Actors

public extension ActorState {
    /// The actor’s cel size for the frame it is on now.
    func celSize() -> SpriteMetrics.Size {
        SpriteMetrics.size(atlas: charName, frame: "\(charName)-\(charFrame)")
            ?? SpriteMetrics.nominalActorSize
    }

    /// `Fighter.getCharBounds`.
    ///
    /// ```js
    /// let x = Utils.convertX(this.charX + this.charFdx * this.charFace);
    /// let y = this.charY + this.charFdy - f.height;
    /// if (this.faceR()) { x -= f.width - 5; }
    /// if ((this.charFood && this.faceL()) || (!this.charFood && this.faceR())) { x += 1; }
    /// ```
    ///
    /// Facing right, the sprite is shifted left by all but five pixels of its width — the body is
    /// drawn to the *left* of the actor’s origin when walking right, and to the right of it when
    /// walking left. The `+ 1` is the same parity correction `updateCharPosition` applies, but
    /// applied to this rectangle instead of the sprite.
    ///
    /// **No half-pixel here.** `updateCharPosition` adds 0.5 to the sprite x for the parity case;
    /// `getCharBounds` does not, so the collision rectangle is up to a pixel off the sprite. That
    /// is the reference’s, and reproducing it costs nothing.
    func charBounds() -> ScreenRect {
        let cel = celSize()
        var x = CoordinateSpace.screenX(fromX: Double(charX + charFdx * charFace))
        let y = charY + charFdy - cel.height
        var width = cel.width

        if charFace == 1 { x -= cel.width - 5 }
        if (charFood && charFace == -1) || (!charFood && charFace == 1) { x += 1 }
        if action == "runturn" { width += 2 }
        if charFrame == 38 { width += 5 }

        return ScreenRect(x: x, y: y, width: width, height: cel.height)
    }

    /// `Actor.centerX` — the *sprite's* middle, half-pixel correction included.
    func centerX() -> Int {
        let cel = celSize()
        var tempx = Double(charX + charFdx * charFace)
        if (charFood && charFace == -1) || (!charFood && charFace == 1) { tempx += 0.5 }
        return CoordinateSpace.screenX(fromX: tempx) + cel.width / 2
    }

    /// `Kid.getCharBoundsAbs` — `Rectangle(this.x, this.y - this.height, this.width, this.height)`,
    /// against the *live sprite* rather than the frame data.
    ///
    /// The difference from `charBounds` is the point: this one uses the sprite’s own position,
    /// half-pixel correction and all, and the drawn cel size. The two rectangles disagree by a few
    /// pixels, and `checkBarrier` asks for one or the other depending on whether the sword is out.
    func charBoundsAbs() -> ScreenRect {
        let cel = celSize()
        var tempx = Double(charX + charFdx * charFace)
        if (charFood && charFace == -1) || (!charFood && charFace == 1) { tempx += 0.5 }

        // `Fighter.updateBase` puts baseY at `roomY * 189 + 3`; room-local, that is the 3.
        let spriteY = 3 + charY + charFdy
        return ScreenRect(
            x: CoordinateSpace.screenX(fromX: tempx),
            y: spriteY - cel.height,
            width: cel.width,
            height: cel.height
        )
    }
}
