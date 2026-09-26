import Testing
@testable import PoPCore

// M8a: the hourglass, the interface font, and the status bar.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

// MARK: - The clock

@Test func theClockStartsAtSixtyMinutes() {
    let clock = GameClock()
    #expect(clock.remainingMinutes == 60)
    #expect(clock.totalSeconds == 3600)
    #expect(!clock.hasExpired)
}

@Test func elapsedTimeIsDerivedFromTicksNotAccumulated() {
    // Twelve ticks a second, so a minute is 720 ticks.
    var clock = GameClock()
    for _ in 0..<719 { clock.advance() }
    #expect(clock.remainingMinutes == 60, "one tick short of a minute")

    clock.advance()
    #expect(clock.remainingMinutes == 59)
}

@Test func theTwoReadoutsAreNotTheSameQuantity() {
    // `getRemainingMinutes` counts whole minutes elapsed; `getRemainingSeconds` clamps to 60, so
    // it only ever counts down the final minute. That is why the bar jumps from "5 MINUTES" to
    // "59 SECONDS" and never shows anything in between.
    var clock = GameClock()
    for _ in 0..<720 { clock.advance() }          // one minute in
    #expect(clock.remainingMinutes == 59)
    #expect(clock.remainingSeconds == 60, "the seconds field rolled over to zero")

    for _ in 0..<360 { clock.advance() }          // thirty *seconds* later
    #expect(clock.remainingSeconds == 30)

    for _ in 0..<(59 * 720 - 360) { clock.advance() }  // 60 minutes in
    #expect(clock.remainingMinutes == 0)
    #expect(clock.hasExpired)
}

@Test func theReadoutMatchesTheInterfacesThreeCases() {
    var clock = GameClock()

    // The level's name is up first, so the clock says nothing.
    #expect(clock.readout == .none)

    // Four minutes in: the last whole-minute mark was five, but the seconds have not rolled over
    // to a multiple of sixty *at this instant*, so nothing shows.
    for _ in 0..<(4 * 720) { clock.advance() }
    #expect(clock.remainingMinutes == 56)

    // At exactly five minutes the bar reports it.
    for _ in 0..<(1 * 720) { clock.advance() }
    #expect(clock.remainingMinutes == 55)
    #expect(clock.readout == .minutes(55))

    // The final minute switches to seconds.
    for _ in 0..<(54 * 720) { clock.advance() }
    #expect(clock.remainingMinutes == 1)
    if case let .seconds(value) = clock.readout {
        #expect(value <= 60)
    } else {
        Issue.record("expected a seconds readout, got \(clock.readout)")
    }

    // A further minute empties the hourglass.
    for _ in 0..<720 { clock.advance() }
    #expect(clock.remainingMinutes == 0)
    if case .timeUp = clock.readout {} else {
        Issue.record("expected timeUp, got \(clock.readout)")
    }
}

@Test func anExpiredClockStopsAdvancing() {
    var clock = GameClock()
    for _ in 0..<(61 * 720) { clock.advance() }
    #expect(clock.hasExpired)
    let frozen = clock.elapsedTicks
    clock.advance()
    #expect(clock.elapsedTicks == frozen)
}

// MARK: - The font

@Test func theInterfaceFontParses() throws {
    let font = try GameData.bitmapFont()
    #expect(font.lineHeight == 13)
    #expect(font.pageFile == "prince_0.png")
    #expect(font.glyphCount == 96)
}

@Test func theFontCoversEverythingTheStatusBarSays() throws {
    // The bar only ever prints these, but a missing glyph would silently drop a character.
    let font = try GameData.bitmapFont()
    for character in "LEVEL0123456789MINUTESECONDLEFT " {
        #expect(font.glyph(for: character) != nil, "no glyph for '\(character)'")
    }
}

@Test func thePenAdvancesByXAdvanceNotGlyphWidth() throws {
    // A space is a 1x1 glyph with an advance of four, so it must move the pen without drawing.
    let font = try GameData.bitmapFont()
    let glyphs = font.layout("A A", x: 0, y: 0)
    #expect(glyphs.count == 2, "the space draws nothing")
    #expect(font.width(of: "A A") > font.width(of: "AA"))

    let space = try #require(font.glyph(for: " "))
    #expect(space.width == 1)
    #expect(space.xAdvance == 4)
    #expect(glyphs[1].x > glyphs[0].x, "the second A is past the space")
}

@Test func centredTextIsActuallyCentred() throws {
    let font = try GameData.bitmapFont()
    let glyphs = font.layoutCentred("LEVEL 1", centreX: 160, y: 0)
    let left = try #require(glyphs.first).x
    let right = (try #require(glyphs.last)).x + (try #require(glyphs.last)).width
    // Within a pixel either way, since the width may be odd.
    #expect(abs((left + right) / 2 - 160) <= 1)
}

// MARK: - The status bar

@Test func theBarSitsOnTheElevenPixelGapBelowTheRoom() {
    // The room is 189 tall inside a 200-pixel screen; the bottom 11 are the interface.
    #expect(HudRenderer.barHeight == 8)
    #expect(HudRenderer.barTop == 192)
    #expect(Geometry.screenHeight - Geometry.roomHeight == 11)
}

@Test func thePrincesLivesRunAlongTheLeft() throws {
    let world = World(try levelOne())
    let font = try GameData.bitmapFont()
    var clock = GameClock()
    let hud = HudRenderer.describe(world: world, clock: clock, ticksInLevel: 0, font: font)

    let lives = hud.pips.filter { $0.frameName.hasSuffix("-live") || $0.frameName.hasSuffix("emptylive") }
    #expect(lives.count == 3, "three lives at the start")
    #expect(lives.allSatisfy { $0.frameName == "kid-live" })
    #expect(lives.map(\.x) == [0, 7, 14])
    #expect(lives.allSatisfy { $0.y == HudRenderer.barTop + 2 })
    _ = clock
}

@Test func aWoundedPrinceShowsEmptyPips() throws {
    var world = World(try levelOne())
    world.actors[0].health = 1
    let font = try GameData.bitmapFont()
    let hud = HudRenderer.describe(world: world, clock: GameClock(), ticksInLevel: 0, font: font)
    let lives = hud.pips.map(\.frameName)
    #expect(lives.filter { $0 == "kid-live" }.count == 1)
    #expect(lives.filter { $0 == "kid-emptylive" }.count == 2)
}

@Test func theOpponentsPipsRunAlongTheRight() throws {
    var world = World(try levelOne())
    // Put the Prince in the first guard's room so the bar knows who he is fighting.
    world.actors[0].room = 21
    let font = try GameData.bitmapFont()
    let hud = HudRenderer.describe(world: world, clock: GameClock(), ticksInLevel: 0, font: font)

    let opponentPips = hud.pips.filter { $0.frameName == "guard-live" }
    #expect(opponentPips.count == 3)
    // Right-aligned: 320 - i * 7 + 1.
    #expect(opponentPips.map(\.x) == [300, 307, 314])
    // Level 1's guards carry colour 2, which is the second entry of Enemy.COLOR.
    #expect(opponentPips.allSatisfy { $0.tint == HudRenderer.guardColors[1] })
}

@Test func theBarShowsTheLevelNameThenTheClock() throws {
    let world = World(try levelOne())
    let font = try GameData.bitmapFont()

    let opening = HudRenderer.describe(
        world: world, clock: GameClock(), ticksInLevel: 0, font: font
    )
    #expect(opening.text == "LEVEL 1")
    #expect(!opening.glyphs.isEmpty, "and it is positioned for drawing")

    // Past the title, with an hour still on the clock, there is nothing to say.
    let quiet = HudRenderer.describe(
        world: world, clock: GameClock(), ticksInLevel: 30, font: font
    )
    #expect(quiet.text.isEmpty)
    #expect(quiet.glyphs.isEmpty)

    // Five minutes in, it reports.
    var clock = GameClock()
    for _ in 0..<(5 * 720) { clock.advance() }
    let report = HudRenderer.describe(
        world: world, clock: clock, ticksInLevel: 4000, font: font
    )
    #expect(report.text == "55 MINUTES LEFT")
}

@Test func theFinalMinuteCountsSeconds() throws {
    let world = World(try levelOne())
    let font = try GameData.bitmapFont()
    var clock = GameClock()

    // 59 minutes and 30 seconds in: one minute left, thirty seconds of it.
    for _ in 0..<(59 * 720 + 360) { clock.advance() }
    #expect(clock.remainingMinutes == 1)
    #expect(clock.remainingSeconds == 30)

    let hud = HudRenderer.describe(
        world: world, clock: clock, ticksInLevel: 50000, font: font
    )
    #expect(hud.text == "30 SECONDS LEFT")
}

@Test func theSimulationAdvancesTheClock() throws {
    var simulation = try Simulation(level: try levelOne())
    #expect(simulation.clock.remainingMinutes == 60)
    #expect(simulation.ticksInLevel == 0)

    simulation.run(720)
    #expect(simulation.clock.remainingMinutes == 59)
    #expect(simulation.ticksInLevel == 720)
}
