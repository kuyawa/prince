/// What the simulation hands to the renderer.
///
/// ARCHITECTURE.md §7.9: this is the boundary that makes everything else testable. `PoPCore`
/// produces one of these per tick and knows nothing about SpriteKit; `PoPHost` draws it.
/// If a change to the renderer ever requires a change here, the boundary has been crossed.
///
/// ## Coordinate space
///
/// Positions are **room-local, y-down, in original pixels** — the engine's own space, not the
/// screen's. A room is 320 x 189. SpriteKit's y axis points up, so the host flips; the
/// simulation never has to know that.
///
/// The y-down choice matches the reference exactly:
/// ```js
/// // Level.js#addTile
/// tile.x = rooms[room].x * ROOM_WIDTH  + x * BLOCK_WIDTH;
/// tile.y = rooms[room].y * ROOM_HEIGHT + y * BLOCK_HEIGHT - 13;
/// ```
/// Note the `- 13`: tile sprites are 60 x 79, not 32 x 63, and overhang their grid cell by 13
/// pixels above and 3 below.
public struct RenderDescription: Sendable, Equatable {
    public var room: Int
    public var sprites: [SpriteInstance]

    public init(room: Int, sprites: [SpriteInstance]) {
        self.room = room
        self.sprites = sprites
    }
}

/// One sprite to draw.
public struct SpriteInstance: Sendable, Equatable {
    /// The atlas frame key, e.g. `"dungeon_20"`, `"SWS_9"` or `"kid-15"`.
    public var frameName: String

    /// Room-local pixel position of the sprite's anchor point.
    public var x: Int
    public var y: Int

    /// Which corner of the sprite `x`/`y` refers to.
    public var anchor: SpriteAnchor

    /// Draw order. Lower is further back.
    public var z: Int

    /// Actors are mirrored by negating `charFace`; the host flips the texture.
    public var flippedHorizontally: Bool

    /// How many pixels to cut from the TOP of the sprite.
    ///
    /// This is a rising gate. The reference crops the texture —
    /// `crop(new Rectangle(0, -posY, width, height + posY))` — which both removes the top
    /// `-posY` rows and slides the remaining art upward, since Phaser draws a cropped sprite at
    /// its unslid origin. A sub-texture at the same position reproduces it exactly.
    ///
    /// The host resolves this, because only the host knows the frame's pixel height.
    public var clipTop: Int

    public init(
        frameName: String,
        x: Int,
        y: Int,
        anchor: SpriteAnchor,
        z: Int,
        flippedHorizontally: Bool = false,
        clipTop: Int = 0
    ) {
        self.frameName = frameName
        self.x = x
        self.y = y
        self.anchor = anchor
        self.z = z
        self.flippedHorizontally = flippedHorizontally
        self.clipTop = clipTop
    }
}

public enum SpriteAnchor: Sendable, Equatable {
    /// Tiles. The reference anchors these at `(0, 0)` in Phaser, which is top-left.
    case topLeft

    /// Actors. `Actor`'s constructor does `this.anchor.setTo(0, 1)` — bottom-left, so a
    /// character stands *on* its position rather than hanging below it.
    case bottomLeft
}
