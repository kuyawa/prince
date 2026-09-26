import Foundation

/// Loads the bundled game data.
///
/// This lives in `PoPCore` rather than `PoPHost` deliberately: the data model is part
/// of the faithful port and must be exercisable headlessly, with no window and no
/// SpriteKit. The resources ship in this target's bundle so `PoPCoreTests` can reach
/// them through the same code path the game uses.
public enum GameData {
    public enum LoadError: Error, CustomStringConvertible {
        case missingResource(String)

        public var description: String {
            switch self {
            case let .missingResource(name):
                return "Missing bundled game resource: \(name)"
            }
        }
    }

    /// Levels shipped with the original game.
    public static let levelNumbers = 1...14

    /// Animation tables available in `anims/`.
    ///
    /// `sword` is deliberately absent: `sword.json` holds a `swordtab` offset list, not
    /// a `sequence`/`framedef` pair. Load it with `swordOffsetTable()`.
    public static let actorAnimationNames = [
        "kid", "fighter", "shadow", "vizier", "princess", "mouse",
    ]

    /// Root of the bundled `Resources` directory.
    public static var rootURL: URL {
        guard let url = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            fatalError("Resources directory is missing from the PoPCore bundle")
        }
        return url
    }

    public static func level(_ number: Int) throws -> LevelData {
        let level = try decode(LevelData.self, from: "maps/level\(number).json")
        try level.validate()
        return level
    }

    public static func animationTable(named name: String) throws -> AnimationTable {
        try decode(AnimationTable.self, from: "anims/\(name).json")
    }

    /// The sword overlay offsets from `anims/sword.json`, which uses a different
    /// schema from the animation tables.
    public static func swordOffsetTable() throws -> SwordOffsetTable {
        try decode(SwordOffsetTable.self, from: "anims/sword.json")
    }

    /// The interface's bitmap font, from `font/prince.fnt`.
    public static func bitmapFont() throws -> BitmapFont {
        let url = rootURL.appendingPathComponent("font/prince.fnt")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.missingResource("font/prince.fnt")
        }
        return try BitmapFont.parse(String(contentsOf: url, encoding: .utf8))
    }

    /// The frame names an atlas declares, without loading its image.
    ///
    /// Lets `PoPCoreTests` verify that every sprite the renderer asks for actually exists —
    /// a check that otherwise only shows up as a silently missing tile on screen.
    public static func atlasFrameNames(named name: String) throws -> Set<String> {
        struct Sheet: Decodable {
            let frames: [String: Entry]
            struct Entry: Decodable {}
        }
        let sheet = try decode(Sheet.self, from: "gfx/\(name).json")
        return Set(sheet.frames.keys)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from relativePath: String) throws -> T {
        let url = rootURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.missingResource(relativePath)
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
