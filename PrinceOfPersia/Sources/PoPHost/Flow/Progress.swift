import Foundation
import PoPCore

/// The one thing this port remembers between runs: which level you were on.
///
/// ## This is an addition, not a port
///
/// **Neither the 1989 original nor PrinceJS saves anything.** `Boot.js` hardcodes
/// `PrinceJS.currentLevel = 1`, there is no `localStorage`, and the game was designed to be played
/// in one sitting against a sixty-minute hourglass. So a save is a modern affordance bolted onto a
/// 1989 game, and it is labelled as one rather than presented as fidelity.
///
/// What it deliberately does *not* remember: health, the hourglass, or anything about the world.
/// Resuming on a level loads that level **from the top** — full health, a fresh hourglass, the
/// boards whole and the gates shut — which is exactly what dying already does. Saving a half-broken
/// level would mean serialising the whole simulation, and would also let a player bank a lucky
/// position, which is the opposite of what the game is about.
public struct Progress: Sendable, Equatable, Codable {
    /// The level to resume on. Always within the shipped levels.
    public var level: Int

    public init(level: Int) {
        self.level = level
    }

    public static var fileURL: URL {
        AppSupport.directory.appendingPathComponent("progress.json")
    }

    /// Reads the saved level, or `nil` if there is not one.
    ///
    /// **Never throws, and never returns nonsense.** A missing file, an unreadable one, a typo in
    /// the JSON or a level number that no longer exists all mean the same thing to the caller:
    /// start at the beginning. A game that refuses to launch because its save file went bad is
    /// worse than one that forgets.
    public static func load(from url: URL = Progress.fileURL) -> Progress? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Progress.self, from: data),
              GameData.levelNumbers.contains(decoded.level)
        else { return nil }
        return decoded
    }

    /// Writes the level, creating the directory if it is not there.
    @discardableResult
    public static func save(level: Int, to url: URL = Progress.fileURL) -> Bool {
        guard GameData.levelNumbers.contains(level) else { return false }
        guard AppSupport.createDirectory(at: url.deletingLastPathComponent()) else { return false }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Progress(level: level)) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Forgets the save, so the next launch starts at level 1.
    public static func clear(at url: URL = Progress.fileURL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// The level to open on, given what the player asked for on the command line.
    ///
    /// An explicit `--level` wins; otherwise the save; otherwise the beginning.
    public static func startingLevel(requested: Int?, newGame: Bool = false) -> Int {
        if let requested, GameData.levelNumbers.contains(requested) { return requested }
        if newGame { return GameData.levelNumbers.lowerBound }
        return load()?.level ?? GameData.levelNumbers.lowerBound
    }
}
