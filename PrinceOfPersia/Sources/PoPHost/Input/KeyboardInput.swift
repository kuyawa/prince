import AppKit
import PoPCore

/// Samples the keyboard into `Intents`.
///
/// ARCHITECTURE.md Law 6: the simulation never reads the keyboard. This is the only place
/// that does, and it produces a value the simulation can be handed in a test.
///
/// Port source: `Kid.js#keyL`/`keyR`/`keyU`/`keyD`/`keyS`. The reference ORs a cursor key
/// with a touch pointer and a gamepad button; only the keyboard is wired here.
///
/// ## There is exactly one of these, and it matters
///
/// A local event monitor that returns `nil` **ends the chain**, so no monitor added after it
/// ever sees that event — and this one returns `nil` for every key it is bound to, to stop
/// AppKit beeping at an unhandled arrow. A second `KeyboardInput` therefore does not merely
/// duplicate the work: it silently takes the arrows away from the first one.
///
/// That is exactly what happened. `main.swift` built a throwaway scene for the headless
/// `--trace` and `--screenshot` paths before it built the real one, and each made its own
/// input. In a debug build the throwaway stayed alive and swallowed everything, so the game
/// received no arrows at all; in a release build it was dropped early and the keys worked.
/// Both instances were always created, and whether the game answered depended on the build
/// configuration. One `KeyboardInput` is now created once, in `main.swift`, and shared.
@MainActor
public final class KeyboardInput {
    private var pressedKeyCodes: Set<UInt16> = []

    /// Which keys mean what. Loaded once at construction, from
    /// `~/Library/Application Support/PrinceOfPersia/keys.json` when it exists.
    public let bindings: KeyBindings

    /// The event-monitor token. `deinit` is nonisolated even on a `@MainActor` class, so the
    /// token has to be reachable from there; it is written once during `init` and read once
    /// during teardown, both on the main thread.
    nonisolated(unsafe) private var monitor: Any?

    /// Forget every held key when the app stops being the active one.
    ///
    /// A `keyUp` follows the *active* app, so a key held while the player switches away never
    /// reports its release and stays down for ever. SpriteKit stops ticking while the app is in
    /// the background, which hides the damage until the player comes back — and then the Prince
    /// walks off on his own. There is no `keyUp` to wait for, so the whole set goes.
    nonisolated(unsafe) private var resignObserver: Any?

    /// How many instances are currently listening.
    ///
    /// Swallowing a key is a *global* act — it ends the monitor chain — so an instance that does
    /// it while another one is listening takes that key away from the other. Swallowing is only a
    /// courtesy, to stop AppKit beeping at an unhandled arrow; being heard is not a courtesy. So
    /// it is dropped the moment it could cost somebody else a key.
    nonisolated(unsafe) private static var listening = 0

    public init(bindings: KeyBindings = KeyBindings.load()) {
        self.bindings = bindings

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                self.pressedKeyCodes.insert(event.keyCode)
            } else {
                self.pressedKeyCodes.remove(event.keyCode)
            }
            // Swallow the bound keys so AppKit does not beep at an unhandled key. This is why the
            // bindings own `reservedKeyCodes` rather than the monitor hard-coding the arrows.
            if Self.listening == 1,
               self.bindings.reservedKeyCodes.contains(event.keyCode) { return nil }
            return event
        }
        Self.listening += 1

        // `queue: .main` is what makes the `assumeIsolated` below a statement of fact rather
        // than a hope.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        Self.listening -= 1
    }

    /// The current input, read fresh each tick.
    ///
    /// Shift is a modifier rather than a key, so it is sampled from the global modifier state
    /// instead of from a key press — that way it stays correct across focus changes. Everything
    /// else comes from the monitor’s own key set, and the decision itself lives in
    /// `KeyBindings.intents`, where it can be tested.
    public var intents: Intents {
        bindings.intents(
            pressed: pressedKeyCodes,
            shiftHeld: NSEvent.modifierFlags.contains(.shift)
        )
    }

    public func releaseAll() {
        pressedKeyCodes.removeAll()
    }
}
