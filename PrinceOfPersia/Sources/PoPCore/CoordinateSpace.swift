/// The engine's coordinate conversions.
///
/// Port source: `reference/PrinceJS/src/Utils.js` (`convertX`, `convertXtoBlockX`,
/// `convertYtoBlockY`, `convertBlockXtoX`, `convertBlockYtoY`).
///
/// **The horizontal and vertical axes use different units** — the single most
/// surprising thing in the engine, and the reason this file exists.
///
/// | Axis | Unit | Per tile | Per room |
/// |---|---|---|---|
/// | `charX` | x-units | 14 | 140 |
/// | `charY` | pixels | 63 | 189 |
///
/// So `charX` is **not** a pixel. A room is 140 x-units wide and 189 pixels tall;
/// the renderer scales x by 320/140 to reach the 320 px screen. Every horizontal
/// offset in the animation data — `CMD_CHX`, `charFdx`, `charFfoot` — is in x-units.
///
/// All values are integers. `updateVelocity` adds integer velocities and
/// `updateAcceleration` adds an integer `GRAVITY` of 3, so nothing here ever needs
/// a fractional type. The single `+0.5` in the engine is a *render-time* parity
/// correction in `Actor.updateCharPosition` — see `screenX(fromX:)`.
public enum CoordinateSpace {
    /// Horizontal engine units per tile column.
    public static let xUnitsPerTileColumn = 14

    /// Horizontal engine units across a room. 10 columns x 14 = 140.
    public static let xUnitsPerRoom = roomColumns * xUnitsPerTileColumn

    public static let roomColumns = Geometry.roomColumns

    /// `Utils.convertXtoBlockX` — `floor((x - 7) / 14)`.
    public static func blockX(fromX x: Int) -> Int {
        floorDivide(x - 7, by: xUnitsPerTileColumn)
    }

    /// `Utils.convertYtoBlockY` — `floor(y / 63)`.
    public static func blockY(fromY y: Int) -> Int {
        floorDivide(y, by: Geometry.blockHeight)
    }

    /// `Utils.convertBlockXtoX` — `block * 14 + 7`. Column centres sit 7 units in.
    public static func x(fromBlockX block: Int) -> Int {
        block * xUnitsPerTileColumn + 7
    }

    /// `Utils.convertBlockYtoY` — `(block + 1) * 63 - 10`.
    ///
    /// Row 0 is the top of the room: rows yield 53, 116 and 179.
    public static func y(fromBlockY block: Int) -> Int {
        (block + 1) * Geometry.blockHeight - 10
    }

    /// `Utils.convertX` — engine x-units to screen pixels, `floor(x * 320 / 140)`.
    ///
    /// Takes a `Double` because the caller may already have applied the half-unit
    /// parity correction from `FrameCheck.isHalfPixelOffset`.
    public static func screenX(fromX x: Double) -> Int {
        Int((x * 320.0 / 140.0).rounded(.down))
    }

    /// Integer floor division.
    ///
    /// JavaScript's `Math.floor` rounds toward negative infinity; Swift's `/`
    /// truncates toward zero. They disagree for negative numerators, which happens
    /// whenever an actor walks off the left edge of a room, so the difference is
    /// not academic.
    public static func floorDivide(_ numerator: Int, by denominator: Int) -> Int {
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        guard remainder != 0, (remainder < 0) != (denominator < 0) else { return quotient }
        return quotient - 1
    }
}
