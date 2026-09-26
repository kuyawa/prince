import Foundation

/// The pixel size of a cel in a texture atlas.
///
/// ## Why the simulation needs this
///
/// Two pieces of the reference measure from **Phaser sprite centres**, and a Phaser sprite is as
/// wide as its current frame:
///
/// ```js
/// // phaser.js, PIXI.Sprite
/// Object.defineProperty(PIXI.Sprite.prototype, "width", {
///   get: function () { return this.scale.x * this.texture.frame.width; }
/// });
/// ```
///
/// So `tile.centerX` and `this.centerX` are not constants. A tile cel is a constant 60 px wide, but
/// the Prince’s cels run from 11 px (standing) to 49 px (mid-strike), and `chopDistance` is
/// `tile.centerX - this.centerX - 16`, tested against a 6-pixel window. Half the actor’s width
/// moves that window by more than the window is wide.
///
/// This is the same problem that blocks `checkBarrier` (open question 11), whose
/// `intersectsAbs` builds its rectangle from `x, width, 63`. One table unblocks both.
///
/// ## Why a table and not the live sprite
///
/// `PoPCore` has no sprite. The atlas JSON already ships in the bundle and `GameData` already
/// reads it for the frame-existence tests, so the numbers are the same ones the host will load —
/// they are just available earlier, and to a headless test.
public enum SpriteMetrics {
    public struct Size: Sendable, Equatable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// The level’s tile cel size. Every dungeon tile cel is 60 x 79, so a tile overhangs its
    /// 32 x 63 grid cell by 13 above and 3 below — the `- 13` in `addTile`.
    public static let dungeonTileSize = Size(width: 60, height: 79)

    /// What to assume when a cel is unknown. The kid’s median, and only ever a fallback for a
    /// frame name that is not in any atlas — which is a missing sprite, not a rounded number.
    public static let nominalActorSize = Size(width: 21, height: 38)

    private struct Sheet: Decodable {
        let frames: [String: Entry]

        struct Entry: Decodable {
            let frame: Rect
            struct Rect: Decodable {
                let w: Int
                let h: Int
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [String: Size]] = [:]

    /// The cel size of one frame, or `nil` if the sheet or the frame is unknown.
    public static func size(atlas: String, frame: String) -> Size? {
        table(atlas)?[frame]
    }

    /// The cel width of one frame.
    public static func width(atlas: String, frame: String) -> Int? {
        size(atlas: atlas, frame: frame)?.width
    }

    /// The cel width of an actor’s current frame, falling back to a nominal width.
    ///
    /// The fallback is not a fudge: it fires only for a frame name no atlas declares, which is
    /// already a bug somewhere else.
    public static func actorWidth(charName: String, frame: Int) -> Int {
        width(atlas: charName, frame: "\(charName)-\(frame)") ?? nominalActorSize.width
    }

    /// Reads a sheet, memoised. A sheet that fails to load is cached as empty so a missing atlas
    /// does not mean a file read per tick.
    private static func table(_ atlas: String) -> [String: Size]? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[atlas] { return cached.isEmpty ? nil : cached }

        guard let sheet = try? GameData.decode(Sheet.self, from: "gfx/\(atlas).json") else {
            cache[atlas] = [:]
            return nil
        }
        let made = sheet.frames.mapValues { Size(width: $0.frame.w, height: $0.frame.h) }
        cache[atlas] = made
        return made
    }
}
