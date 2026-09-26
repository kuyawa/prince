import AppKit
import SpriteKit
import PoPCore

/// Owns the run: which level is loaded, and what carries between levels.
///
/// Deliberately thin. The scene knows how to draw and tick one level; this knows how to replace
/// it. `CMD_NEXTLEVEL` fires an effect, the scene turns it into a callback, and this loads the
/// next level — nothing in `PoPCore` has to know that levels are numbered.
@MainActor
public final class GameCoordinator {
    private let view: SKView
    private let input: KeyboardInput
    private let seed: Int

    public private(set) var levelNumber: Int
    public private(set) var scene: LevelScene

    /// Carried across a level change. `CMD_NEXTLEVEL` does `PrinceJS.maxHealth = this.maxHealth`
    /// and passes the current health onward.
    private var health: Int?
    private var maxHealth: Int?

    /// The last level. Finishing it ends the run rather than loading a nonexistent 15.
    public nonisolated static let finalLevel = 14

    /// Which level follows `completed`, or `nil` if the run is over.
    ///
    /// Pulled out as a pure function so the decision can be tested without a window — the rest of
    /// this class is SpriteKit plumbing.
    public nonisolated static func nextLevel(after completed: Int) -> Int? {
        let next = completed + 1
        return next <= finalLevel ? next : nil
    }

    public init(view: SKView, level: Int, seed: Int, input: KeyboardInput) throws {
        self.view = view
        self.input = input
        self.seed = seed
        self.levelNumber = level
        self.scene = try GameCoordinator.makeScene(
            level: level, seed: seed, input: input, health: nil, maxHealth: nil
        )
        wire()
    }

    private static func makeScene(
        level: Int, seed: Int, input: KeyboardInput, health: Int?, maxHealth: Int?
    ) throws -> LevelScene {
        let scene = try LevelScene(
            level: try LevelRuntime(try GameData.level(level)),
            input: input, seed: seed,
            carriedHealth: health, carriedMaxHealth: maxHealth
        )
        return scene
    }

    private func wire() {
        scene.onLevelFinished = { [weak self] completed, health, maxHealth in
            self?.levelFinished(completed, health: health, maxHealth: maxHealth)
        }
    }

    /// Presents the level and hands the scene back to the caller to put in a window.
    public func present() {
        view.presentScene(scene)
    }

    private func levelFinished(_ completed: Int, health: Int, maxHealth: Int) {
        self.health = health
        self.maxHealth = maxHealth

        guard let next = Self.nextLevel(after: completed) else {
            // The Princess is rescued; there is nowhere further to go.
            print("[Prince] level \(completed) complete — the game is finished")
            fflush(stdout)
            return
        }

        do {
            let nextScene = try GameCoordinator.makeScene(
                level: next, seed: seed, input: input, health: health, maxHealth: maxHealth
            )
            scene = nextScene
            levelNumber = next
            wire()
            view.presentScene(nextScene, transition: SKTransition.fade(withDuration: 0.6))
            print("[Prince] level \(completed) complete -> level \(next)"
                  + "  health \(health)/\(maxHealth)")
            fflush(stdout)
        } catch {
            FileHandle.standardError.write(
                Data("Could not load level \(next): \(error)\n".utf8)
            )
        }
    }
}
