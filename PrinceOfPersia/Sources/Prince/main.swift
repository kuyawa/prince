import AppKit
import SpriteKit
import PoPCore
import PoPHost

// Entry point.
//
//   swift run Prince                      the game, at the default scale
//   swift run Prince --scale 4            1280 x 800
//   swift run Prince --screenshot out.png render one frame headlessly and exit
//
// The window scale is a launch option and a menu command, never a compile-time decision,
// and nothing in PoPCore can see it.

/// Top-level code in `main.swift` is `@MainActor`, but a declared function is not, so the
/// isolation has to be spelled out here.
@MainActor
func buildScene(levelNumber: Int, hold: Intents?) throws -> LevelScene {
    let level = try LevelRuntime(try GameData.level(levelNumber))
    let prince = level.data.prince

    // Game.js: `let turn = json.prince.turn !== false`, and when turning the Prince starts
    // facing the wrong way and turns into the correct one.
    var actor = ActorState(
        location: prince.location,
        room: prince.room,
        face: prince.effectiveDirection,
        action: prince.shouldTurn ? "turn" : "stand",
        charName: "kid"
    )
    if prince.shouldTurn { actor.charX += 7 }

    let scene = try LevelScene(level: level, actor: actor, input: KeyboardInput())
    scene.scriptedIntents = hold
    return scene
}

func value(for flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func intents(named name: String) -> Intents {
    switch name {
    case "left": [.left]
    case "right": [.right]
    case "up": [.up]
    case "down": [.down]
    case "right-run": [.right]
    default: []
    }
}

let arguments = CommandLine.arguments
let scale = WindowScale.scale(from: arguments)
let levelNumber = value(for: "--level", in: arguments).flatMap(Int.init) ?? 1

// A screenshot holds one direction for the whole run so the frame is reproducible.
let hold: Intents? = value(for: "--hold", in: arguments).map(intents(named:))

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let scene: LevelScene
do {
    scene = try buildScene(levelNumber: levelNumber, hold: hold)
} catch {
    FileHandle.standardError.write(Data("Failed to build the level: \(error)\n".utf8))
    exit(1)
}

// Diagnostic: render a single atlas frame at 1:1 so the slice can be compared against
// the source image directly. Used while bringing up the renderer.
if let frameName = value(for: "--dump-frame", in: arguments),
   let path = value(for: "--screenshot", in: arguments) {
    do {
        let atlas = try TextureAtlas(named: value(for: "--atlas", in: arguments) ?? "dungeon")
        guard let texture = atlas.texture(frameName) else {
            FileHandle.standardError.write(Data("No such frame: \(frameName)\n".utf8))
            exit(1)
        }
        let size = texture.size()
        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = .zero
        node.position = .zero
        let dump = SKScene(size: size)
        dump.backgroundColor = SKColor(red: 1, green: 0, blue: 1, alpha: 1)
        dump.addChild(node)
        let view = SKView(frame: NSRect(origin: .zero, size: size))
        view.presentScene(dump)
        DispatchQueue.main.async {
            if let rendered = view.texture(from: dump) {
                let rep = NSBitmapImageRep(cgImage: rendered.cgImage())
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
                print("dumped \(frameName) \(Int(size.width))x\(Int(size.height)) -> \(path)")
            }
            NSApp.terminate(nil)
        }
        app.run()
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

if arguments.contains("--trace") {
    print("tick action           frame  x   y   bx by code fcheck food")
    for tick in 1...30 {
        scene.step()
        let a = scene.currentActor
        print(String(format: "%4d %-16@ %5d %3d %3d %2d %2d %4d %6d %5d",
                     tick, a.action as NSString, a.charFrame, a.charX, a.charY,
                     a.charBlockX, a.charBlockY, a.actionCode,
                     a.charFcheck ? 1 : 0, a.charFood ? 1 : 0))
    }
    fflush(stdout)
    exit(0)
}

if let path = value(for: "--screenshot", in: arguments) {
    let ticks = value(for: "--ticks", in: arguments).flatMap(Int.init) ?? 1
    scene.advance(ticks: ticks)

    if !scene.missingFrames().isEmpty {
        let names = Set(scene.missingFrames()).sorted()
        FileHandle.standardError.write(Data("Missing atlas frames: \(names.joined(separator: ", "))\n".utf8))
    }

    let view = SKView(frame: NSRect(
        x: 0, y: 0,
        width: CGFloat(Geometry.screenWidth * scale),
        height: CGFloat(Geometry.screenHeight * scale)
    ))
    view.presentScene(scene)

    // Give SpriteKit one runloop turn to realise the node tree before capturing.
    DispatchQueue.main.async {
        if let texture = view.texture(from: scene) {
            let rep = NSBitmapImageRep(cgImage: texture.cgImage())
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                print("wrote \(path)  \(Int(texture.size().width))x\(Int(texture.size().height))"
                      + "  room \(scene.currentRoom)  action \(scene.currentAction)"
                      + "  frame \(scene.currentFrame)  ticks \(scene.ticksRun)")
                fflush(stdout)
            } else {
                FileHandle.standardError.write(Data("Could not encode PNG\n".utf8))
            }
        } else {
            FileHandle.standardError.write(Data("Could not render the scene to a texture\n".utf8))
        }
        NSApp.terminate(nil)
    }
    app.run()
} else {
    let controller = WindowController(initialScale: scale, scene: scene)
    app.mainMenu = MainMenu.build(controller: controller)
    controller.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}
