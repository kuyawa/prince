import Foundation
import PoPCore

/// What the player last chose for the window.
///
/// The window scale is the one setting in the project that is genuinely free to change — Law 8
/// keeps it out of the simulation entirely, so remembering it cannot affect a single frame of
/// gameplay. It is still worth remembering: the switch exists to be used, and a switch that resets
/// itself every launch is one the player stops touching.
///
/// ## Why this is not part of `Progress`
///
/// They are different kinds of thing. `Progress` is a *save*: it exists to be thrown away by
/// `--new-game`, and forgetting it costs a player nothing but time. This is a *preference* — it has
/// to outlive `--new-game`, and a bad value in it must not be able to do anything worse than open
/// the window at the default size. Two files, two failure modes, neither able to break the other.
public struct WindowSettings: Sendable, Equatable, Codable {
    /// The window scale the player last chose, as an integer multiple of 320 x 200.
    public var scale: Int

    public init(scale: Int) {
        self.scale = scale
    }

    public static var fileURL: URL {
        AppSupport.directory.appendingPathComponent("window.json")
    }

    /// Reads the remembered scale, or `nil` if there is not a usable one.
    ///
    /// **Never throws, and never returns nonsense.** A missing file, an unreadable one, a typo in
    /// the JSON and a scale outside `WindowScale.absoluteRange` all mean the same thing to the
    /// caller: open at the default. This is Application Support, which people do edit by hand.
    public static func load(from url: URL = WindowSettings.fileURL) -> WindowSettings? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WindowSettings.self, from: data),
              WindowScale.absoluteRange.contains(decoded.scale)
        else { return nil }
        return decoded
    }

    /// Writes the scale, creating the directory if it is not there.
    @discardableResult
    public static func save(scale: Int, to url: URL = WindowSettings.fileURL) -> Bool {
        guard WindowScale.absoluteRange.contains(scale) else { return false }
        guard AppSupport.createDirectory(at: url.deletingLastPathComponent()) else { return false }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(WindowSettings(scale: scale)) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// The scale to open at, given what the player asked for on the command line.
    ///
    /// An explicit `--scale` wins, then what the player last chose from the menu, then
    /// `WindowScale.standard`. Either way the answer goes through `fitted`, so a remembered 8 on a
    /// laptop screen opens at the largest scale that fits rather than off the bottom of the display.
    ///
    /// **`--scale` is an override for one launch, not a new preference.** It is a diagnostic and a
    /// one-off, in the same family as `--level`, and quietly rewriting the player's menu setting
    /// because a screenshot command passed a flag would be a surprise. Only the View menu saves.
    public static func startingScale(
        requested: Int?,
        stored: WindowSettings? = WindowSettings.load()
    ) -> Int {
        if let requested { return WindowScale.fitted(requested) }
        guard let stored else { return WindowScale.standard }
        return WindowScale.fitted(stored.scale)
    }
}
