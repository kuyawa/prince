import AppKit
import PoPCore
import PoPHost

// Entry point.
//
// The window scale is a launch option and a menu command, never a compile-time
// decision: `swift run Prince --scale 4` gives a 1280 x 800 window.
//
// ARCHITECTURE.md Law 4: the simulation will be driven by a fixed timestep from
// SKScene.update(_:) with an accumulator, never by vsync. There is no simulation
// yet; when there is, the window scale will not be visible to it.

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let controller = WindowController(initialScale: WindowScale.scale(from: CommandLine.arguments))
app.mainMenu = MainMenu.build(controller: controller)

controller.showWindow(nil)
app.activate(ignoringOtherApps: true)
app.run()
