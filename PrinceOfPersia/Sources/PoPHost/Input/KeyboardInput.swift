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

    /// The event-monitor token. `deinit` is nonisolated even on a `@MainActor` class, so the
    /// token has to be reachable from there; it is written once during `init` and read once
    /// during teardown, both on the main thread.
    nonisolated(unsafe) private var monitor: Any?

    /// Virtual key codes, from `Carbon.HIToolbox` `kVK_*`.
    private enum Key {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    public init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                self.pressedKeyCodes.insert(event.keyCode)
            } else {
                self.pressedKeyCodes.remove(event.keyCode)
            }
            // Swallow the arrow keys so AppKit does not beep at an unhandled key.
            switch event.keyCode {
            case Key.left, Key.right, Key.up, Key.down: return nil
            default: return event
            }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// The current input, read fresh each tick.
    ///
    /// Shift is a modifier rather than a key, so it is sampled from the global modifier
    /// state instead of from a key press — that way it stays correct across focus changes.
    public var intents: Intents {
        var intents: Intents = []
        if pressedKeyCodes.contains(Key.left) { intents.insert(.left) }
        if pressedKeyCodes.contains(Key.right) { intents.insert(.right) }
        if pressedKeyCodes.contains(Key.up) { intents.insert(.up) }
        if pressedKeyCodes.contains(Key.down) { intents.insert(.down) }
        if NSEvent.modifierFlags.contains(.shift) { intents.insert(.action) }
        return intents
    }

    public func releaseAll() {
        pressedKeyCodes.removeAll()
    }
}
