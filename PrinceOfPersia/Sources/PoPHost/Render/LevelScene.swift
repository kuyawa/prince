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

    public private(set) var ticksRun = 0

    /// Replaces keyboard sampling when set. Used by headless screenshots and tests so a render is
    /// reproducible without a keyboard.
    public var scriptedIntents: Intents?

    private var sampledIntents: Intents { scriptedIntents ?? input.intents }

    public init(level: LevelRuntime, input: KeyboardInput, seed: Int = 0) throws {
        self.simulation = try Simulation(level: level, seed: seed)
        self.input = input
        self.background = try TextureAtlas(
            named: level.data.type == .dungeon ? "dungeon" : "palace"
        )

        super.init(size: CGSize(width: Geometry.screenWidth, height: Geometry.screenHeight))

        self.scaleMode = .aspectFit
        self.backgroundColor = SKColor(white: 0, alpha: 1)
        addChild(spriteRoot)

        for actor in simulation.world.actors {
            _ = try? atlas(for: actor.charName)
        }
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
    }

    private func makeNode(_ sprite: SpriteInstance) -> SKSpriteNode? {
        let texture = characterTexture(sprite) ?? background.texture(
            sprite.frameName, clipTop: sprite.clipTop
        )
        guard let texture else { return nil }

        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = sprite.anchor == .topLeft
            ? CGPoint(x: 0, y: 1)     // SpriteKit: (0,0) is bottom-left, (1,1) top-right
            : CGPoint(x: 0, y: 0)
        node.position = CGPoint(x: CGFloat(sprite.x), y: Self.roomTopY - CGFloat(sprite.y))
        node.zPosition = CGFloat(sprite.z)
        if sprite.flippedHorizontally { node.xScale = -1 }
        return node
    }

    /// Actor frames live in a per-character atlas; tiles live in the level's own.
    private func characterTexture(_ sprite: SpriteInstance) -> SKTexture? {
        for atlas in characterAtlases.values {
            if let texture = atlas.texture(sprite.frameName, clipTop: sprite.clipTop) {
                return texture
            }
        }
        return nil
    }

    /// Frame names present in no loaded atlas, for diagnostics.
    public func missingFrames() -> [String] {
        let world = simulation.world
        let visible = world.actors.filter { $0.room == world.prince.room && $0.isVisible }
        let description = RoomRenderer.describe(
            world: world, room: world.prince.room, actors: visible
        )
        return description.sprites
            .map(\.frameName)
            .filter { characterTexture(SpriteInstance(
                frameName: $0, x: 0, y: 0, anchor: .topLeft, z: 0
            )) == nil && background.texture($0) == nil }
    }
}
