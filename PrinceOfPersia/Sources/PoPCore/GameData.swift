import Foundation

// `dladdr`, for finding the running image without a compile-time path.
#if canImport(Darwin)
import Darwin
#endif

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
    /// The SwiftPM resource bundle, found without a single absolute path.
    ///
    /// **`Bundle.module` is not used at all.** SwiftPM generates an accessor with the builder's
    /// own build directory baked in as a string literal:
    ///
    /// ```swift
    /// let mainPath = Bundle.main.bundleURL.appendingPathComponent("PrinceOfPersia_PoPCore.bundle")
    /// let buildPath = "<the machine that compiled this>/…/PrinceOfPersia_PoPCore.bundle"
    /// let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath)
    /// ```
    ///
    /// Three things are wrong with that. The first candidate is `Bundle.main.bundleURL` plus the
    /// bundle name, which inside an `.app` is the app *itself* rather than `Contents/Resources`, so
    /// it misses every time. The fallback is a path into the builder's source tree, which on macOS
    /// is usually under TCC-protected `~/Documents` — so the game asked for Documents access on
    /// launch, and only ran on the machine that compiled it. And an absolute path at all means the
    /// `.app` could not be moved or copied anywhere.
    ///
    /// So the bundle is looked for at *run* time, in directories that belong to whatever is
    /// running. Nothing here is a path of our own.
    static let resourceBundleName = "PrinceOfPersia_PoPCore.bundle"

    /// The directory holding the running image, asked of the dynamic loader.
    ///
    /// `Bundle.main` answers a different question and gives a different answer under `swift test`,
    /// where the main bundle is SwiftPM's helper binary inside the Xcode toolchain rather than
    /// anything to do with this package. `dladdr` asks about the image that contains *this* code,
    /// at run time, and returns whatever path the loader actually used — which is correct in an
    /// `.app`, in `.build` and in a test bundle alike.
    static var imageDirectory: URL? {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let name = info.dli_fname else { return nil }
        return URL(fileURLWithPath: String(cString: name)).deletingLastPathComponent()
    }

    /// Where the resource bundle might be, in order, and nowhere else.
    static var resourceBundleDirectories: [URL] {
        // Inside an `.app`: `Contents/Resources` and nowhere else. Walking above the `.app` would
        // read whatever folder it happens to be sitting in, which is how the Documents prompt
        // happened in the first place.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return [Bundle.main.resourceURL].compactMap { $0 }
        }

        // Everywhere else: beside the running image and up from it, which covers `swift run`
        // (`.build/<config>/Prince`, bundle alongside) and the test bundle
        // (`….xctest/Contents/MacOS/…`, bundle three levels up).
        var directories: [URL] = []
        var directory = imageDirectory ?? Bundle.main.bundleURL
        for _ in 0..<5 {
            directories.append(directory)
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return directories
    }

    static var resourceBundle: Bundle? {
        for directory in resourceBundleDirectories {
            let candidate = directory.appendingPathComponent(resourceBundleName)
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return nil
    }

    /// Root of the bundled `Resources` directory.
    public static var rootURL: URL {
        guard let bundle = resourceBundle,
              let url = bundle.url(forResource: "Resources", withExtension: nil)
        else {
            let looked = resourceBundleDirectories
                .map { $0.appendingPathComponent(resourceBundleName).path }
                .joined(separator: "\n    ")
            fatalError("""
                Could not find \(resourceBundleName). Looked in:
                    \(looked)
                """)
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
