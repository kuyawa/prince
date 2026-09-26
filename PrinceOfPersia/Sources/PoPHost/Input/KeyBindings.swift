import AppKit
import PoPCore

/// Which physical keys do what, and where the player can change them.
///
/// The original shipped a key-configuration screen; this is the same idea done the way a modern
/// Mac game does it — a JSON file the player can edit, with the built-in defaults used when it is
/// absent or unreadable.
///
/// ## Why this is a value type with a pure method
///
/// `intents(pressed:shiftHeld:)` takes the raw inputs and returns `Intents`, with no AppKit in
/// sight. That is what makes rebinding testable: a test can hand it a set of key codes and assert
/// what the simulation would see, without a window or an event loop.
public struct KeyBindings: Sendable, Equatable, Codable {
    /// ← → ↓ ↑, from `Carbon.HIToolbox` `kVK_*`.
    public var left: UInt16
    public var right: UInt16
    public var down: UInt16
    public var up: UInt16

    /// The action key — pick up, drink a potion, strike, grab a ledge. **Shift**, as in the
    /// original, which is why the modifier fallback below exists: Shift is a modifier, and a
    /// modifier does not arrive as a key-down in a local monitor.
    public var action: UInt16

    /// Whether holding Shift also counts as the action key.
    ///
    /// On by default, because that is the original game’s binding and because a player who holds
    /// Shift expects it to work. Turn it off to bind the action to a letter key and nothing else.
    public var shiftIsAction: Bool

    /// `kVK_LeftArrow` and friends, and left Shift.
    public static let standard = KeyBindings(
        left: 123, right: 124, down: 125, up: 126, action: 56, shiftIsAction: true
    )

    public init(
        left: UInt16, right: UInt16, down: UInt16, up: UInt16,
        action: UInt16, shiftIsAction: Bool = true
    ) {
        self.left = left
        self.right = right
        self.down = down
        self.up = up
        self.action = action
        self.shiftIsAction = shiftIsAction
    }

    /// The intents a set of pressed keys amounts to.
    ///
    /// Pure, and the whole of the input policy: the simulation never sees a key code.
    public func intents(pressed: Set<UInt16>, shiftHeld: Bool) -> Intents {
        var intents: Intents = []
        if pressed.contains(left) { intents.insert(.left) }
        if pressed.contains(right) { intents.insert(.right) }
        if pressed.contains(up) { intents.insert(.up) }
        if pressed.contains(down) { intents.insert(.down) }
        if pressed.contains(action) || (shiftIsAction && shiftHeld) { intents.insert(.action) }
        return intents
    }

    /// The key codes the monitor should swallow, so AppKit does not beep at them.
    public var reservedKeyCodes: Set<UInt16> { [left, right, up, down, action] }

    // MARK: - Loading

    /// Where a player’s bindings live.
    ///
    /// `Application Support`, not the bundle: a `.app` is code-signed and read-only, and the
    /// whole point of the file is that it can be edited.
    public static var fileURL: URL {
        AppSupport.directory.appendingPathComponent("keys.json")
    }

    /// Reads the player’s bindings, falling back to the standard set.
    ///
    /// **Never throws.** A game that refuses to start because a configuration file has a typo in it
    /// is worse than one running with the defaults, and the whole file is optional.
    public static func load(from url: URL = KeyBindings.fileURL) -> KeyBindings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(KeyBindings.self, from: data)
        else { return .standard }
        return decoded
    }

    /// Writes a template the player can edit, if there is not one already.
    @discardableResult
    public static func writeTemplateIfMissing(to url: URL = KeyBindings.fileURL) -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        return write(standard, to: url)
    }

    @discardableResult
    public static func write(_ bindings: KeyBindings, to url: URL = KeyBindings.fileURL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(bindings) else { return false }
        AppSupport.createDirectory(at: url.deletingLastPathComponent())
        return (try? data.write(to: url)) != nil
    }
}
