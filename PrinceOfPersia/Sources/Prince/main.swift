import AppKit
import SpriteKit
import PoPCore
import PoPHost

// M0 entry point: open a window at an integer multiple of the original
// 320 x 200 playfield and present the placeholder scene.
//
// ARCHITECTURE.md Law 4: the simulation is driven by a fixed timestep, never by
// vsync. There is no simulation yet — when there is, it will be stepped from
// SKScene.update(_:) with an accumulator, not from a display link.

let scale = CGFloat(Geometry.scaleFactor)
let playfield = CGSize(width: CGFloat(Geometry.screenWidth),
                       height: CGFloat(Geometry.screenHeight))
let windowSize = CGSize(width: playfield.width * scale,
                        height: playfield.height * scale)

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: windowSize),
    styleMask: [.titled, .closable, .miniaturizable],
    backing: .buffered,
    defer: false
)
window.title = "Prince of Persia"

let view = SKView(frame: NSRect(origin: .zero, size: windowSize))
view.preferredFramesPerSecond = 60
view.ignoresSiblingOrder = true

let scene = GameScene(size: playfield)
view.presentScene(scene)

window.contentView = view
window.center()
window.makeKeyAndOrderFront(nil)

app.activate(ignoringOtherApps: true)
app.run()
