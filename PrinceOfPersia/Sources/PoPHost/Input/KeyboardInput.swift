import AppKit
import PoPCore

/// Samples the keyboard into `Intents`.
///
/// ARCHITECTURE.md Law 6: the simulation never reads the keyboard. This is the only place
/// that does, and it produces a value the simulation can be handed in a test.
///
/// Port source: `Kid.js#keyL`/`keyR`/`keyU`/`keyD`/`keyS`. The reference ORs a cursor key
/// with a touch pointer and a gamepad button; only the keyboard is wired here.
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
            if self.bindings.reservedKeyCodes.contains(event.keyCode) { return nil }
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
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
