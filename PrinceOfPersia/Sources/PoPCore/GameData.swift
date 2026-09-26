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

    /// The SwiftPM resource bundle, looked for only where it can actually be.
    /// **`Bundle.module` is deliberately not used.** SwiftPM generates an accessor that bakes an
    /// absolute path into the binary at compile time:
    ///
    /// ```swift
    /// let mainPath = Bundle.main.bundleURL.appendingPathComponent("PrinceOfPersia_PoPCore.bundle")
    /// let buildPath = "/Users/you/Documents/.../.build/release/PrinceOfPersia_PoPCore.bundle"
    /// let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath)
    /// ```
    ///
    /// Two things are wrong with that, and both bite.
    ///
    /// The first candidate is `Bundle.main.bundleURL` plus the bundle name, which inside an `.app`
    /// is the app *itself* rather than `Contents/Resources` — so it misses every time.
    ///
    /// The fallback is an absolute path into the source tree of whoever compiled it. On macOS that
    /// tree is almost always under `~/Documents`, which is **TCC-protected**, so the game asks the
    /// player for permission to read their Documents folder on launch — to find a resource bundle
    /// that is already inside the app. It also means a shipped `.app` would work on the build
    /// machine and `fatalError` on any other.
    ///
    /// So the search is done here, over directories that belong to the app.
    static let resourceBundleName = "PrinceOfPersia_PoPCore.bundle"

    /// Where the resource bundle might be, in order, and nowhere else.
    static var resourceBundleDirectories: [URL] {
        let container = Bundle.main.bundleURL

        // An app bundle. `Contents/Resources` and nothing else: looking beside the `.app` would
        // mean reading the directory it was built in, which is the TCC problem above.
        if container.pathExtension == "app" {
            return [Bundle.main.resourceURL].compactMap { $0 }
        }

        // A bare executable, which is `swift run` and `swift build` output: the bundle sits either
        // beside the binary or one level up from it. A test bundle is `.xctest/Contents/MacOS/x`,
        // so one level up from the container is `.build/<config>`.
        var directories: [URL] = []
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            directories.append(executable)
        }
        directories.append(container)
        directories.append(container.deletingLastPathComponent())
        return directories
    }

    static var resourceBundle: Bundle? {
        for directory in resourceBundleDirectories {
            let candidate = directory.appendingPathComponent(resourceBundleName)
            if let bundle = Bundle(url: candidate) { return bundle }
        }

        // Only now, and only for `swift test`. SwiftPM runs the suite under its own helper
        // binary inside the Xcode toolchain, so `Bundle.main` is that helper and every path
        // derived from it is wrong — the real bundle sits beside the `.xctest` in `.build`.
        // `Bundle.module` knows that path because it was baked in at compile time, which is
        // exactly what makes it unsafe as a *primary* source: it reads into the source tree,
        // and on macOS that means `~/Documents`.
        //
        // Reaching it here is harmless, because a test only ever runs on the machine that built
        // it. A launched `.app` finds its own bundle above and never evaluates this at all —
        // `Bundle.module` is a lazy `static let`, so an unread property is an unread path.
        return Bundle.module
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
