import CoreGraphics
import Testing
@testable import PoPHost
import PoPCore

// Where the room sits in the window.
//
// One constant does the whole of the flip: a room's y counts downward from its top, so a sprite
// lands at SpriteKit y `roomTopY - sprite.y`. Getting that constant wrong by the height of the
// status bar is not obvious in a still — it just slides everything down, puts a black band across
// the top, and buries the bottom row under the bar.

@MainActor
@Test func theRoomFillsTheWholeScreenAboveTheStatusBar() throws {
    let level = try LevelRuntime(try GameData.level(1))
    let scene = try LevelScene(level: level, input: KeyboardInput())

    #expect(scene.size == CGSize(width: Geometry.screenWidth, height: Geometry.screenHeight))
    #expect(LevelScene.roomTopY == CGFloat(Geometry.screenHeight))
}

@MainActor
@Test func theBottomRowLandsOnTheRowAboveTheStatusBar() {
    // A tile cel is 79 px tall against a 63 px cell, so the art starts 13 px above its cell
    // (`addTile`: `y * BLOCK_HEIGHT - 13`) and ends 3 px below it. The bottom row's last pixel
    // therefore lands on screen row 191 — the row immediately above the 8 px bar — and the top
    // row's art starts on screen row 3 instead of 14.
    let lastRowOfTheBottomRow = 2 * Geometry.blockHeight - Geometry.tileOverhang + 78
    let onScreen = Geometry.screenHeight
        - (Int(LevelScene.roomTopY) - lastRowOfTheBottomRow)

    #expect(lastRowOfTheBottomRow == 191)
    #expect(onScreen == 191)
    #expect(onScreen == HudRenderer.barTop - 1)

    // Anchoring at the room's own height instead — its 189 px grid fitted into the 200 px screen
    // — would drop that same row to 202, under the bar.
    let anchoredAtTheRoomHeight = Geometry.screenHeight - (Geometry.roomHeight - lastRowOfTheBottomRow)
    #expect(anchoredAtTheRoomHeight == 202)
    #expect(anchoredAtTheRoomHeight > HudRenderer.barTop)
}

@MainActor
@Test func theTopRowIsClippedByTheOverhangAndNotByTheStatusBar() {
    // The top row's cell sits 13 px above the screen, which is the whole reason a tile is drawn
    // 13 px higher than its cell. Anchoring to the room's height would leave only 2 px clipped.
    let topRowTop = 0 * Geometry.blockHeight - Geometry.tileOverhang
    let clipped = Int(LevelScene.roomTopY) - topRowTop - Geometry.screenHeight

    #expect(clipped == Geometry.tileOverhang)
    #expect(clipped != Geometry.tileOverhang - Geometry.uiHeight)
    #expect(Geometry.uiHeight == 8)
}
