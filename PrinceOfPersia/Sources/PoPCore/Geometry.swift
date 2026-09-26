// Geometry constants — the game's coordinate system.
//
// Transcribed from reference/PrinceJS/src/Boot.js. These are the numbers the
// original engine is built on; do not "round" them into something tidier.
//
// Port source: PrinceJS (public domain). SDLPoP was not consulted for these.

/// The fixed pixel geometry of the 1989 game.
public enum Geometry {
    /// One tile is 32 px wide...
    public static let blockWidth = 32

    /// ...and 63 px tall. Tiles are NOT square. This is the single most common
    /// early bug in a Prince of Persia port.
    public static let blockHeight = 63

    /// The original playfield is 320 x 200.
    public static let screenWidth = 320
    public static let screenHeight = 200

    /// Status bar height. See ARCHITECTURE.md open question 4 — how this
    /// reconciles with a 189 px room inside a 200 px screen is unresolved.
    public static let uiHeight = 8

    /// A room is 10 tiles wide by 3 tiles tall.
    public static let roomColumns = 10
    public static let roomRows = 3

    /// A room occupies the full screen width: 10 x 32 = 320.
    public static let roomWidth = roomColumns * blockWidth

    /// ...but only 3 x 63 = 189 px tall, leaving 11 px unaccounted for.
    public static let roomHeight = roomRows * blockHeight

    /// Every room in every level holds exactly this many tiles, row-major.
    public static let tilesPerRoom = roomColumns * roomRows

    /// The original renders at 2x. Used for the default window size.
    public static let scaleFactor = 2

    /// Tile sprites overhang their grid cell by this much above. `addTile`:
    /// `y * BLOCK_HEIGHT - 13`, because a dungeon cel is 79 tall against a 63-pixel row.
    public static let tileOverhang = 13
}
