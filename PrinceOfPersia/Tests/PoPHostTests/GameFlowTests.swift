import CoreGraphics
import Testing
@testable import PoPHost
import PoPCore

// Host-side policy that is worth testing without a window.

@Test func aLevelIsFollowedByTheNextOne() {
    #expect(GameCoordinator.nextLevel(after: 1) == 2)
    #expect(GameCoordinator.nextLevel(after: 12) == 13)
    #expect(GameCoordinator.nextLevel(after: 13) == 14)
}

@Test func finishingTheLastLevelEndsTheRun() {
    // There is no level 15; the Princess is rescued and the run stops.
    #expect(GameCoordinator.nextLevel(after: 14) == nil)
    #expect(GameCoordinator.nextLevel(after: 20) == nil)
}

@Test func everyLevelInTheChainExists() throws {
    // Walk the whole chain the way the coordinator does, so a gap in the numbering cannot
    // surface as a crash after an hour of play.
    var level = 1
    var visited: [Int] = []
    while let next = GameCoordinator.nextLevel(after: level) {
        visited.append(level)
        level = next
    }
    visited.append(level)

    #expect(visited == Array(1...14))
    for number in visited {
        #expect(throws: Never.self) { try GameData.level(number) }
    }
}

@MainActor
@Test func theWindowScaleSwitchCannotAffectTheSimulation() throws {
    // Law 8, checked rather than asserted: the scene is always the native playfield, and the
    // window is always an integer multiple of it.
    let level = try LevelRuntime(try GameData.level(1))
    let scene = try LevelScene(level: level, input: KeyboardInput())

    for scale in WindowScale.absoluteRange {
        let size = WindowScale.windowSize(for: scale)
        #expect(Int(size.width) == Geometry.screenWidth * scale)
        #expect(Int(size.height) == Geometry.screenHeight * scale)
    }
    #expect(scene.size.width == CGFloat(Geometry.screenWidth))
    #expect(scene.size.height == CGFloat(Geometry.screenHeight))
    #expect(scene.actorCount == 3, "the Prince and level 1's two guards")
}
