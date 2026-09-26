import SpriteKit
import PoPCore

/// Draws a level and drives the simulation.
///
/// The scene owns the *host* half of the boundary: it queries the keyboard, drives the fixed
/// timestep, and turns each `RenderDescription` into nodes. It contains no game rules — the tick
/// itself lives in `PoPCore.Simulation`, so a duel can be run with no window at all.
@MainActor
public final class LevelScene: SKScene {
    /// Where the room's top edge sits in SpriteKit's y-up space.
    ///
    /// The room is 320 x 189 inside a 320 x 200 screen. Anchoring its top at 189 leaves the bottom
    /// 11 px free — the gap ARCHITECTURE.md open question 4 flags for the status bar. The
    /// reference's own y is measured downward from the room's top, so this single constant is the
    /// whole of the flip.
    public static let roomTopY = CGFloat(Geometry.roomHeight)

    private var simulation: Simulation
    private let input: KeyboardInput
    private let background: TextureAtlas

    /// One atlas per `charName`. Every actor's frames are named `<charName>-<frame>` inside an
    /// atlas of the same name, so a guard needs its own sheet loaded on demand.
    private var characterAtlases: [String: TextureAtlas] = [:]

    private var ticker = Ticker()
    private var lastUpdateTime: TimeInterval?

    private let spriteRoot = SKNode()
    private let hudRoot = SKNode()

    /// The status bar's own assets: the life pips and the interface font.
    private let generalAtlas: TextureAtlas?
    private let font: BitmapFont?
    private let fontAtlas: FontAtlas?

    public private(set) var ticksRun = 0

    /// Replaces keyboard sampling when set. Used by headless screenshots and tests so a render is
    /// reproducible without a keyboard.
    public var scriptedIntents: Intents?

    private var sampledIntents: Intents { scriptedIntents ?? input.intents }

    /// Calls out when the Prince climbs an exit. The coordinator loads the next level; the scene
    /// does not know what a "next level" is.
    public var onLevelFinished: ((_ completedLevel: Int, _ health: Int, _ maxHealth: Int) -> Void)?

    /// Every sound the simulation produced this tick, in order. The coordinator plays them.
    ///
    /// The scene deliberately does not hold an audio player: Law 8 makes presentation
    /// disposable, and a scene that owns speakers is a scene that cannot be built in a test.
    public var onSound: ((SoundEffect) -> Void)?

    /// Music the simulation asked for. Kept separate from `onSound` so the host can loop it.
    public var onMusic: ((PoPCore.MusicTrack) -> Void)?

    /// The hourglass ran out. Fires once.
    public var onTimeUp: (() -> Void)?

    /// Fires once, the first time a level's opening cue should play. Levels 2 and up re-use the
    /// Danger theme, so the coordinator needs to know that a level *started*, not just which one.
    public var onLevelStarted: ((_ level: Int, _ danger: Bool) -> Void)?

    private var hasReportedFinish = false
    private var hasReportedStart = false
    /// Set when the hourglass empties. The scene stops ticking — there is nothing left to play.
    private var hasTimedOut = false

    /// Whether the run is over for want of time.
    public var isTimedOut: Bool { hasTimedOut }

    public init(
        level: LevelRuntime,
        input: KeyboardInput,
        seed: Int = 0,
        carriedHealth: Int? = nil,
        carriedMaxHealth: Int? = nil
    ) throws {
        self.simulation = try Simulation(
            level: level, seed: seed,
            princeHealth: carriedHealth, princeMaxHealth: carriedMaxHealth
        )
        self.input = input
        self.background = try TextureAtlas(
            named: level.data.type == .dungeon ? "dungeon" : "palace"
        )

        self.generalAtlas = try? TextureAtlas(named: "general")
        let loadedFont = try? GameData.bitmapFont()
        self.font = loadedFont
        self.fontAtlas = loadedFont.flatMap { try? FontAtlas(font: $0) }

        super.init(size: CGSize(width: Geometry.screenWidth, height: Geometry.screenHeight))

        self.scaleMode = .aspectFit
        self.backgroundColor = SKColor(white: 0, alpha: 1)
        addChild(spriteRoot)

        for actor in simulation.world.actors {
            _ = try? atlas(for: actor.charName)
        }
        // The sword overlay lives in its own atlas, named by the offset table's `id`.
        characterAtlases["sword"] = try? TextureAtlas(named: "sword")

        addChild(hudRoot)
        redraw()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("LevelScene is created in code, never from a nib")
    }

    // MARK: - State

    public var currentWorld: World { simulation.world }
    public var currentActor: ActorState { simulation.world.prince }
    public var currentRoom: Int { simulation.world.prince.room }
    public var currentAction: String { simulation.world.prince.action }
    public var currentFrame: Int { simulation.world.prince.charFrame }
    public var actorCount: Int { simulation.world.actors.count }
    public var clock: GameClock { simulation.clock }
    public var hudText: String { font.map { simulation.hud(font: $0).text } ?? "" }

    /// A one-line description of who the Prince is fighting, for the trace output.
    public func opponentDescription() -> String {
        guard let index = simulation.opponentIndex(for: 0) else { return "-" }
        let opponent = simulation.world.actors[index]
        let distance = Combat.opponentDistance(
            simulation.world.prince, opponent, world: simulation.world
        )
        return "\(opponent.charName) d=\(distance)"
    }

    private func atlas(for charName: String) throws -> TextureAtlas {
        if let existing = characterAtlases[charName] { return existing }
        let loaded = try TextureAtlas(named: ActorKind.atlasName(for: charName))
        characterAtlases[charName] = loaded
        return loaded
    }

    // MARK: - Time

    public override func update(_ currentTime: TimeInterval) {
        guard !hasTimedOut else { return }

        let elapsed = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime

        // Law 4: fixed timestep, clamped catch-up. Never a tick per rendered frame.
        for _ in 0..<ticker.ticks(forElapsed: elapsed) {
            step()
        }
        redraw()
    }

    /// Advances the simulation by exactly one tick.
    public func step() {
        simulation.tick(intents: sampledIntents)
        ticksRun += 1

        // `CMD_NEXTLEVEL` fires `onLevelFinished`, then `onNextLevel` after a delay that exists
        // purely to let the "Prince" theme finish — 13 seconds, or 9 on level 4 for the shadow.
        // With no audio yet, that wait is dead time and the hand-off is immediate.
        if !hasReportedFinish, simulation.effects.contains(.advanceToNextLevel) {
            hasReportedFinish = true
            let prince = simulation.world.prince
            onLevelFinished?(simulation.world.level.data.number, prince.health, prince.maxHealth)
        }

        // Sounds last, so anything a level-finished callback starts is not immediately buried.
        for effect in simulation.effects {
            switch effect {
            case let .sound(sound): onSound?(sound)
            case let .music(track): onMusic?(track)
            case .timeUp:
                guard !hasTimedOut else { break }
                hasTimedOut = true
                onTimeUp?()
            default: break
            }
        }

        // `Game.update`'s first tick: level 1 plays the Danger theme once, if the map allows it.
        if !hasReportedStart {
            hasReportedStart = true
            let data = simulation.world.level.data
            onLevelStarted?(data.number, data.prince.danger != false)
        }
    }

    /// Runs a fixed number of ticks, for headless screenshots and tests.
    public func advance(ticks: Int) {
        simulation.run(ticks, intents: sampledIntents)
        ticksRun += ticks
        redraw()
    }

    // MARK: - Drawing

    private func redraw() {
        spriteRoot.removeAllChildren()

        let world = simulation.world
        let room = world.prince.room
        let visible = world.actors.filter { $0.room == room && $0.isVisible }

        let description = RoomRenderer.describe(world: world, room: room, actors: visible)
        for sprite in description.sprites.sorted(by: { $0.z < $1.z }) {
            guard let node = makeNode(sprite) else { continue }
            spriteRoot.addChild(node)
        }

        redrawHud()
    }

    /// The status bar: a black strip at the bottom, the life pips, and the interface text.
    ///
    /// Everything is in SpriteKit's y-up space, so the bar's top is `screenHeight - barTop` and
    /// each element's y counts down from there.
    private func redrawHud() {
        hudRoot.removeAllChildren()
        guard let font else { return }

        let barHeight = CGFloat(HudRenderer.barHeight)
        let barTop = CGFloat(Geometry.screenHeight - HudRenderer.barTop)

        let bar = SKSpriteNode(
            color: .black,
            size: CGSize(width: CGFloat(Geometry.screenWidth), height: barHeight)
        )
        bar.anchorPoint = CGPoint(x: 0, y: 1)
        bar.position = CGPoint(x: 0, y: barTop)
        bar.zPosition = 100
        hudRoot.addChild(bar)

        let hud = simulation.hud(font: font)

        for pip in hud.pips {
            guard let texture = generalAtlas?.texture(pip.frameName) else { continue }
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = CGPoint(x: 0, y: 1)
            node.position = CGPoint(
                x: CGFloat(pip.x),
                y: barTop - CGFloat(pip.y - HudRenderer.barTop)
            )
            node.zPosition = 101
            if let tint = pip.tint {
                node.color = SKColor(
                    red: CGFloat((tint >> 16) & 0xff) / 255,
                    green: CGFloat((tint >> 8) & 0xff) / 255,
                    blue: CGFloat(tint & 0xff) / 255,
                    alpha: 1
                )
                node.colorBlendFactor = 1
            }
            hudRoot.addChild(node)
        }

        for glyph in hud.glyphs {
            guard let texture = fontAtlas?.texture(glyph) else { continue }
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = CGPoint(x: 0, y: 1)
            node.position = CGPoint(
                x: CGFloat(glyph.x),
                y: barTop - CGFloat(glyph.y - HudRenderer.barTop)
            )
            node.zPosition = 102
            hudRoot.addChild(node)
        }
    }

    private func makeNode(_ sprite: SpriteInstance) -> SKSpriteNode? {
        let texture = texture(for: sprite)
        guard let texture else { return nil }

        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = sprite.anchor == .topLeft
            ? CGPoint(x: 0, y: 1)     // SpriteKit: (0,0) is bottom-left, (1,1) top-right
            : CGPoint(x: 0, y: 0)
        node.position = CGPoint(x: CGFloat(sprite.x), y: Self.roomTopY - CGFloat(sprite.y))
        node.zPosition = CGFloat(sprite.z)
        if sprite.flippedHorizontally { node.xScale = -1 }
        if let tint = sprite.tint {
            node.color = SKColor(
                red: CGFloat((tint >> 16) & 0xff) / 255,
                green: CGFloat((tint >> 8) & 0xff) / 255,
                blue: CGFloat(tint & 0xff) / 255,
                alpha: 1
            )
            node.colorBlendFactor = 1
        }
        return node
    }

    /// Resolves a sprite to a texture.
    ///
    /// A tile draws from the level's own atlas and an actor from an atlas named for its
    /// `charName`, so most sprites resolve by convention. An explicit `atlas` wins when the
    /// description names one — the potion bubbles live in `general`, which belongs to neither.
    private func texture(for sprite: SpriteInstance) -> SKTexture? {
        if let name = sprite.atlas {
            guard let sheet = characterAtlases[name] ?? (try? TextureAtlas(named: name)) else {
                return nil
            }
            characterAtlases[name] = sheet
            return sheet.texture(sprite.frameName, clipTop: sprite.clipTop)
        }
        for atlas in characterAtlases.values {
            if let texture = atlas.texture(sprite.frameName, clipTop: sprite.clipTop) {
                return texture
            }
        }
        return background.texture(sprite.frameName, clipTop: sprite.clipTop)
    }

    /// Frame names present in no loaded atlas, for diagnostics.
    ///
    /// This is the check that catches a frame the renderer asks for and the atlas does not have:
    /// a miss draws nothing at all, which on screen looks exactly like a tile that is meant to
    /// be empty.
    public func missingFrames() -> [String] {
        let world = simulation.world
        let visible = world.actors.filter { $0.room == world.prince.room && $0.isVisible }
        let description = RoomRenderer.describe(
            world: world, room: world.prince.room, actors: visible
        )
        return description.sprites
            .filter { texture(for: $0) == nil }
            .map(\.frameName)
    }
}
