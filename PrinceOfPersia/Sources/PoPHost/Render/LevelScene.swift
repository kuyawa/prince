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

    private let level: LevelRuntime
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
        self.level = level
        self.actor = actor
        self.input = input
        self.interpreter = SequenceInterpreter(
            table: try GameData.animationTable(named: actor.charName),
            actorClass: .kid
        )
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

        Behaviour.update(&actor, intents: sampledIntents, world: level)
        try? interpreter.step(&actor, world: level, effects: &effects)

        Physics.accelerate(&actor)
        Physics.move(&actor)

        // `checkFloor` in full: the standing branch can start a fall, the falling branch
        // can end one. The two are mutually exclusive by action code.
        try? FallCycle.checkFloorStanding(
            &actor, world: level, interpreter: interpreter, effects: &effects
        )
        if actor.actionCode == 3 || actor.actionCode == 4 {
            try? FallCycle.checkFall(
                &actor, world: level, interpreter: interpreter, effects: &effects
            )
        }
        FallCycle.checkRoomChange(&actor, world: level)

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

        let description = RoomRenderer.describe(level: level, room: actor.room, actors: [actor])
        for sprite in description.sprites.sorted(by: { $0.z < $1.z }) {
            guard let node = makeNode(sprite) else { continue }
            spriteRoot.addChild(node)
        }
    }

    private func makeNode(_ sprite: SpriteInstance) -> SKSpriteNode? {
        // Wall-shape frames ("SWS_9") carry no prefix of their own, so the atlas is
        // resolved by lookup rather than by parsing the name.
        let texture = characters.texture(sprite.frameName) ?? background.texture(sprite.frameName)
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
        let description = RoomRenderer.describe(level: level, room: actor.room, actors: [actor])
        return description.sprites
            .map(\.frameName)
            .filter { characters.texture($0) == nil && background.texture($0) == nil }
    }
}
