import SpriteKit
import PoPCore

/// Draws a level and steps the simulation.
///
/// The scene owns the *host* half of the boundary: it queries the keyboard, drives the
/// fixed timestep, and turns each `RenderDescription` into nodes. It contains no game rules —
/// even the choice of which frame a wall draws is in `PoPCore.RoomRenderer`.
@MainActor
public final class LevelScene: SKScene {
    /// Where the room's top edge sits in SpriteKit's y-up space.
    ///
    /// The room is 320 x 189 inside a 320 x 200 screen. Anchoring its top at 189 leaves the
    /// bottom 11 px free — the same gap ARCHITECTURE.md open question 4 flags for the status
    /// bar. The reference's own y is measured downward from the room's top, so this single
    /// constant is the whole of the flip.
    public static let roomTopY = CGFloat(Geometry.roomHeight)

    private var world: World
    private let interpreter: SequenceInterpreter
    private let input: KeyboardInput
    private let background: TextureAtlas
    private let characters: TextureAtlas

    private var actor: ActorState
    private var effects: [ActorEffect] = []
    private var ticker = Ticker()
    private var lastUpdateTime: TimeInterval?

    private let spriteRoot = SKNode()

    public private(set) var ticksRun = 0

    /// Replaces keyboard sampling when set. Used by headless screenshots and tests so a
    /// render is reproducible without a keyboard.
    public var scriptedIntents: Intents?

    private var sampledIntents: Intents { scriptedIntents ?? input.intents }

    public init(level: LevelRuntime, actor: ActorState, input: KeyboardInput) throws {
        self.world = World(level)
        self.actor = actor
        self.input = input
        self.interpreter = SequenceInterpreter(
            table: try GameData.animationTable(named: actor.charName),
            actorClass: .kid
        )
        let level = world.level
        self.background = try TextureAtlas(
            named: level.data.type == .dungeon ? "dungeon" : "palace"
        )
        self.characters = try TextureAtlas(named: actor.charName)

        super.init(size: CGSize(width: Geometry.screenWidth, height: Geometry.screenHeight))

        self.scaleMode = .aspectFit
        self.backgroundColor = SKColor(white: 0, alpha: 1)
        addChild(spriteRoot)
        redraw()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("LevelScene is created in code, never from a nib")
    }

    /// The simulated actor. Exposed read-only for diagnostics and tests.
    public var currentActor: ActorState { actor }

    /// The world, including gate and button state.
    public var currentWorld: World { world }

    public var currentRoom: Int { actor.room }
    public var currentAction: String { actor.action }
    public var currentFrame: Int { actor.charFrame }

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

    /// Advances the simulation by exactly one tick — `Kid.updateActor`'s order.
    ///
    /// ```
    /// updateBehaviour -> processCommand -> updateAcceleration -> updateVelocity
    ///   -> ... -> checkFloor -> checkRoomChange -> updateCharPosition
    /// ```
    ///
    /// `checkBarrier`, `checkButton`, `checkSpikes` and `checkChoppers` are absent because
    /// they are not ported yet (PROMPT.md M3c).
    public func step() {
        effects.removeAll(keepingCapacity: true)

        // `Kid.updateActor`'s order, as far as it is ported:
        //   updateBehaviour, processCommand, updateAcceleration, updateVelocity,
        //   ... checkButton, checkFloor, checkRoomChange
        Behaviour.update(&actor, intents: sampledIntents, world: world, effects: &effects)
        world.apply(effects)
        try? interpreter.step(&actor, world: world, effects: &effects)
        world.apply(effects)

        Physics.accelerate(&actor)
        Physics.move(&actor)

        TileChecks.checkButton(&actor, world: &world)

        // `checkFloor` in full: the standing branch can start a fall, the falling branch can end
        // one. The two are mutually exclusive by action code.
        try? FallCycle.checkFloorStanding(
            &actor, world: world, interpreter: interpreter, effects: &effects
        )
        if actor.actionCode == 3 || actor.actionCode == 4 {
            try? FallCycle.checkFall(
                &actor, world: world, interpreter: interpreter, effects: &effects
            )
        }
        // The Prince uses Kid's threshold (189), not the Fighter's (192).
        FallCycle.checkRoomChange(&actor, world: world)

        // Gates and buttons advance once per simulation tick.
        world.update()

        ticksRun += 1
    }

    /// Runs a fixed number of ticks, for headless screenshots and tests.
    public func advance(ticks: Int) {
        for _ in 0..<ticks { step() }
        redraw()
    }

    // MARK: - Drawing

    private func redraw() {
        spriteRoot.removeAllChildren()

        let description = RoomRenderer.describe(world: world, room: actor.room, actors: [actor])
        for sprite in description.sprites.sorted(by: { $0.z < $1.z }) {
            guard let node = makeNode(sprite) else { continue }
            spriteRoot.addChild(node)
        }
    }

    private func makeNode(_ sprite: SpriteInstance) -> SKSpriteNode? {
        // Wall-shape frames ("SWS_9") carry no prefix of their own, so the atlas is
        // resolved by lookup rather than by parsing the name.
        let texture = characters.texture(sprite.frameName, clipTop: sprite.clipTop)
            ?? background.texture(sprite.frameName, clipTop: sprite.clipTop)
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

    /// Frame names present in neither atlas, for diagnostics.
    public func missingFrames() -> [String] {
        let description = RoomRenderer.describe(world: world, room: actor.room, actors: [actor])
        return description.sprites
            .map(\.frameName)
            .filter { characters.texture($0) == nil && background.texture($0) == nil }
    }
}
