import AppKit
import SpriteKit
import PoPCore

/// Owns the window and the `SKView`, and exposes the scale switch.
///
/// Note what this class does *not* do: it never touches the simulation. It only
/// decides how many screen points one game pixel is worth.
@MainActor
public final class WindowController: NSWindowController {
    public private(set) var scale: Int

    private let scene: SKScene
    private let skView: SKView

    /// Takes the view rather than making one, so a level coordinator can present replacement
    /// scenes into the same view as the run progresses.
    public init(initialScale: Int, view: SKView, scene: SKScene) {
        let normalized = WindowScale.fitted(initialScale)
        let size = WindowScale.windowSize(for: normalized)

        view.frame = NSRect(origin: .zero, size: size)
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.scale = normalized
        self.skView = view
        // The scene is ALWAYS the native playfield, at every window scale. Window scale
        // is applied by the view, so nothing here can change the simulation.
        self.scene = scene

        super.init(window: window)

        window.title = "Prince of Persia"
        window.contentView = view
        window.contentMinSize = WindowScale.windowSize(for: WindowScale.absoluteRange.lowerBound)
        scene.size = WindowScale.playfieldSize
        view.presentScene(scene)
        window.center()
        report()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WindowController is created in code, never from a nib")
    }

    /// The switch. Resizes the window only; the scene and any future simulation
    /// are untouched.
    public func setScale(_ requested: Int) {
        let normalized = WindowScale.fitted(requested)
        guard normalized != scale else { return }
        scale = normalized
        window?.setContentSize(WindowScale.windowSize(for: normalized))
        window?.center()
        report()
    }

    @objc public func selectScale(_ sender: NSMenuItem) {
        setScale(sender.tag)
    }

    // MARK: - Key bindings

    /// Opens the bindings file in whichever editor owns JSON.
    ///
    /// Written first if it is not there, so the menu item always has something to open rather
    /// than silently doing nothing the first time it is used.
    @objc public func revealKeyBindings(_ sender: Any?) {
        KeyBindings.writeTemplateIfMissing()
        NSWorkspace.shared.open(KeyBindings.fileURL)
    }

    /// Puts the standard bindings back, over whatever the player had.
    @objc public func resetKeyBindings(_ sender: Any?) {
        KeyBindings.write(.standard)
    }

    private func report() {
        let size = WindowScale.windowSize(for: scale)
        print("[Prince] window \(Int(size.width))x\(Int(size.height))"
              + "  scene \(Int(WindowScale.playfieldSize.width))x\(Int(WindowScale.playfieldSize.height))"
              + "  scale \(scale)x")
        // stdout is block-buffered when piped; make the line visible immediately.
        fflush(stdout)
    }
}

extension WindowController: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectScale(_:)) {
            menuItem.state = (menuItem.tag == scale) ? .on : .off
        }
        return true
    }
}
