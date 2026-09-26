import AppKit
import SpriteKit
import PoPCore
import PoPHost

// Entry point.
//
//   swift run Prince                      the game, at the default scale
//   swift run Prince --scale 4            1280 x 800
//   swift run Prince --screenshot out.png render one frame headlessly and exit
//   swift run Prince --no-audio             run silently
//   swift run Prince --trace --ticks 40     print the simulation, tick by tick
//
// The window scale is a launch option and a menu command, never a compile-time decision,
// and nothing in PoPCore can see it.

/// Top-level code in `main.swift` is `@MainActor`, but a declared function is not, so the
/// isolation has to be spelled out here.
@MainActor
func buildScene(
    levelNumber: Int,
    hold: Intents?,
    seed: Int,
    room override: Int? = nil,
    location overrideLocation: Int? = nil
) throws -> LevelScene {
    var level = try GameData.level(levelNumber)

    // A room or location override moves the Prince's spawn, which is what `--room` and
    // `--location` are for. The guards and their positions stay as the level defines them.
    if override != nil || overrideLocation != nil {
        let prince = level.prince
        let moved = PrinceSpawn(
            location: overrideLocation ?? prince.location,
            room: override ?? prince.room,
            direction: prince.direction,
            offset: prince.offset,
            turn: prince.turn,
            cameraRoom: prince.cameraRoom,
            bias: prince.bias,
            reverse: prince.reverse,
            sword: prince.sword,
            danger: prince.danger,
            specialEvents: prince.specialEvents
        )
        level = level.replacingPrince(moved)
    }

    let scene = try LevelScene(
        level: try LevelRuntime(level), input: KeyboardInput(), seed: seed
    )
    scene.scriptedIntents = hold
    return scene
}

func value(for flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

/// Intents from a flag value. Comma-separated, so `--hold down,action` means both at once —
/// which is what drinking a potion or taking the sword actually needs.
func intents(named name: String) -> Intents {
    var result: Intents = []
    for part in name.split(separator: ",") {
        switch part.trimmingCharacters(in: .whitespaces) {
        case "left": result.insert(.left)
        case "right": result.insert(.right)
        case "up": result.insert(.up)
        case "down": result.insert(.down)
        case "action": result.insert(.action)
        default: break
        }
    }
    return result
}

let arguments = CommandLine.arguments
let scale = WindowScale.scale(from: arguments)
let levelNumber = value(for: "--level", in: arguments).flatMap(Int.init) ?? 1

// A screenshot holds one direction for the whole run so the frame is reproducible.
let hold: Intents? = value(for: "--hold", in: arguments).map(intents(named:))
let seedValue = value(for: "--seed", in: arguments).flatMap(Int.init) ?? 0

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let scene: LevelScene
do {
    scene = try buildScene(
        levelNumber: levelNumber,
        hold: hold,
        seed: seedValue,
        room: value(for: "--room", in: arguments).flatMap(Int.init),
        location: value(for: "--location", in: arguments).flatMap(Int.init)
    )
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
    let ticks = value(for: "--ticks", in: arguments).flatMap(Int.init) ?? 30
    var sounds: [SoundEffect] = []
    var music: [PoPCore.MusicTrack] = []
    scene.onSound = { sounds.append($0) }
    scene.onMusic = { music.append($0) }
    print("tick  actor        action           frame   x    y  bx by  hp  op")
    for tick in 1...ticks {
        scene.step()
        let world = scene.currentWorld
        for (index, a) in world.actors.enumerated() {
            let opponent = index == 0
                ? scene.opponentDescription()
                : "prince"
            print(String(format: "%4d  %-11@  %-16@ %5d %4d %4d %2d %2d %3d  %@",
                         tick, a.charName as NSString, a.action as NSString,
                         a.charFrame, a.charX, a.charY, a.charBlockX, a.charBlockY,
                         a.health, opponent as NSString))
        }
        // Sounds are labelled, never positional: a bare array in a trace invites the reader to
        // guess which entry is which.
        if !sounds.isEmpty {
            print("      sound: " + sounds.map(\.fileName).joined(separator: ", "))
            sounds.removeAll(keepingCapacity: true)
        }
        if !music.isEmpty {
            print("      music: " + music.map(\.fileName).joined(separator: ", "))
            music.removeAll(keepingCapacity: true)
        }
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
    let input = KeyboardInput()
    let view = SKView()
    let muted = arguments.contains("--mute") || arguments.contains("--no-audio")
    let music = !arguments.contains("--no-music") && !arguments.contains("--no-audio")
    let coordinator = try! GameCoordinator(
        view: view, level: levelNumber, seed: seedValue, input: input,
        audio: AudioPlayer(options: .init(
            soundEnabled: !muted, musicEnabled: music,
            volume: value(for: "--volume", in: arguments).flatMap(Float.init) ?? 1
        ))
    )
    let controller = WindowController(
        initialScale: scale, view: view, scene: coordinator.scene
    )
    app.mainMenu = MainMenu.build(controller: controller)
    controller.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}
