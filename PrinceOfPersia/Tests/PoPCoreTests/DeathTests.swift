import Testing
@testable import PoPCore

// M6d: what happens after the Prince dies.
//
// The reference has three beats — a pause so the death animation reads, four seconds before the
// message, then a countdown that restarts the game by itself. Any key skips the rest.
//
// None of this existed until it was asked for, which is why the answer to "what key restarts a
// level?" used to be "none".

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

// MARK: - The sequence

@Test func theDeathSequenceHasThreeBeats() {
    var death = DeathSequence()
    #expect(!death.isRunning)
    #expect(!death.showsMessage)
    #expect(!death.acceptsButtonPress)

    death.start()
    #expect(death.phase == .settling, "a beat first, so the death animation is not cut off")

    // The beat.
    for _ in 0..<(DeathSequence.settleTicks - 1) { death.advance() }
    #expect(death.phase == .settling)
    death.advance()
    #expect(death.phase == .waiting)

    // Four seconds of silence. A key press already works — the reference is counting down even
    // though nothing is on screen.
    #expect(death.acceptsButtonPress)
    #expect(!death.showsMessage)
    for _ in 0..<(DeathSequence.messageDelayTicks - 1) { death.advance() }
    #expect(!death.showsMessage)
    death.advance()
    #expect(death.showsMessage, "the message appears four seconds in")
    #expect(death.isMessageVisible)
}

@Test func theWaitEndsInAnAutomaticRestart() {
    var death = DeathSequence()
    death.start()

    var restarts = 0
    var ticks = 0
    while death.isRunning, ticks < 1000 {
        if death.advance() { restarts += 1 }
        ticks += 1
    }
    #expect(restarts == 1)
    #expect(ticks == DeathSequence.settleTicks + DeathSequence.waitTicks)
    // About 22 seconds at the 1/12 s tick, which is the reference’s own ballpark.
    #expect(ticks == 270)
}

@Test func theMessageFlashesOnlyNearTheEnd() {
    var death = DeathSequence()
    death.start()
    for _ in 0..<DeathSequence.settleTicks { death.advance() }

    // Steady while it is the only thing telling the player what to do.
    var steady = true
    for _ in 0..<(DeathSequence.waitTicks - DeathSequence.flashBelowTicks - DeathSequence.messageDelayTicks) {
        death.advance()
        if death.showsMessage, !death.isMessageVisible { steady = false }
    }
    #expect(steady, "no flashing until the last 70 ticks")

    // Then it toggles, and beeps when it comes back on.
    var toggles = 0
    var beeps = 0
    var beepsWhileVisible = true
    while death.isRunning {
        let before = death.isMessageVisible
        death.advance()
        if death.isMessageVisible != before { toggles += 1 }
        if death.shouldBeep {
            beeps += 1
            // Every beep is the text coming back *on*, never going off.
            if !death.isMessageVisible { beepsWhileVisible = false }
        }
    }
    #expect(toggles == 9, "nine flashes in the last 70 ticks, the tenth landing on the restart")
    #expect(beeps == 4, "and only the four that turn the text back on")
    #expect(beepsWhileVisible, "a beep means the text just appeared, not that it just went")
}

@Test func stoppingTheWaitAbandonsItRatherThanPausingIt() {
    var death = DeathSequence()
    death.start()
    for _ in 0..<DeathSequence.settleTicks { death.advance() }
    #expect(death.isRunning)

    death.stop()
    #expect(!death.isRunning)
    #expect(!death.showsMessage)
    #expect(death.advance() == false, "and it stays stopped")
}

// MARK: - A real death

/// A simulation with the Prince about to be impaled: level 1 room 6 is the spike trap.
private func simulationAboutToDie() throws -> Simulation {
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    var prince = simulation.world.actors[0]
    prince.room = 6
    prince.charBlockX = 1
    prince.charBlockY = 0
    prince.charX = CoordinateSpace.x(fromBlockX: 1)
    prince.charY = CoordinateSpace.y(fromBlockY: 0)
    prince.charFace = 1
    simulation.world.actors[0] = prince
    return simulation
}

@Test func dyingStartsTheWait() throws {
    var simulation = try simulationAboutToDie()
    #expect(simulation.death.phase == .none)

    var died = false
    for _ in 0..<30 {
        simulation.tick(intents: [.right])
        if !simulation.world.prince.isAlive { died = true; break }
    }
    #expect(died, "the trap should have killed him")
    #expect(simulation.death.phase != .none, "and that starts the clock on the wait")
}

@Test func aKeyPressDuringTheWaitRestartsTheLevel() throws {
    var simulation = try simulationAboutToDie()
    for _ in 0..<30 {
        simulation.tick(intents: [.right])
        if !simulation.world.prince.isAlive { break }
    }
    // Past the beat, and a key. Any intent counts — the reference listens for any key at all.
    for _ in 0..<DeathSequence.settleTicks { simulation.tick(intents: []) }
    #expect(simulation.death.acceptsButtonPress)

    simulation.tick(intents: [.left])
    #expect(simulation.effects.contains(.restartLevel))
    #expect(!simulation.death.isRunning, "and the wait is over")
}

@Test func aHeldKeyIsNotAPress() throws {
    // The reference listens on Phaser's `onDownCallback` — a key going *down*, not a key being
    // held. It matters because a player killed while running right is still holding right, and
    // treating that as a press restarts the level a fifth of a second after the death animation
    // starts. He has to let go and press again.
    var simulation = try simulationAboutToDie()
    for _ in 0..<30 {
        simulation.tick(intents: [.right])
        if !simulation.world.prince.isAlive { break }
    }
    for _ in 0..<DeathSequence.settleTicks { simulation.tick(intents: [.right]) }

    #expect(simulation.death.acceptsButtonPress)
    #expect(!simulation.effects.contains(.restartLevel), "right was already down before he died")

    // Releasing and pressing again is a press.
    simulation.tick(intents: [])
    simulation.tick(intents: [.right])
    #expect(simulation.effects.contains(.restartLevel))
}

@Test func waitingItOutRestartsTheLevelByItself() throws {
    var simulation = try simulationAboutToDie()
    for _ in 0..<30 {
        simulation.tick(intents: [.right])
        if !simulation.world.prince.isAlive { break }
    }

    var restarted = false
    for _ in 0..<(DeathSequence.settleTicks + DeathSequence.waitTicks + 2) {
        simulation.tick(intents: [])
        if simulation.effects.contains(.restartLevel) { restarted = true; break }
    }
    #expect(restarted, "no key needed — it gives up and reloads")
}

@Test func theRestartIsAskedForOnceAndNotEveryTick() throws {
    // A headless run keeps the same simulation, where the host would have built a fresh one.
    var simulation = try simulationAboutToDie()
    for _ in 0..<30 {
        simulation.tick(intents: [.right])
        if !simulation.world.prince.isAlive { break }
    }
    // The effect list is drained every tick, so it has to be read inside the loop rather than
    // after it — which is exactly the mistake that made this test pass for the wrong reason.
    var asked = 0
    for _ in 0..<(DeathSequence.settleTicks + DeathSequence.waitTicks + 1) {
        simulation.tick(intents: [])
        if simulation.effects.contains(.restartLevel) { asked += 1 }
    }
    #expect(asked == 1, "asked for exactly once")

    for _ in 0..<10 { simulation.tick(intents: []) }
    #expect(!simulation.effects.contains(.restartLevel), "and it does not keep asking")
}

// MARK: - The message

@Test func theMessageReachesTheStatusBar() throws {
    let world = World(try levelOne())
    let font = try GameData.bitmapFont()

    func text(death: DeathSequence) -> String {
        HudRenderer.describe(
            world: world, clock: GameClock(), ticksInLevel: 100, death: death, font: font
        ).text
    }

    #expect(text(death: DeathSequence()) != DeathSequence.message, "nothing before he dies")

    var death = DeathSequence()
    death.start()
    for _ in 0..<DeathSequence.settleTicks { death.advance() }
    #expect(text(death: death) == "", "the beat and the four seconds are silent")

    for _ in 0..<DeathSequence.messageDelayTicks { death.advance() }
    #expect(text(death: death) == DeathSequence.message)
    #expect(DeathSequence.message == "Press Button to Continue")

    // And a glyph for every character, or it would draw holes.
    let glyphs = font.layoutCentred(
        DeathSequence.message, centreX: Geometry.screenWidth / 2, y: 0
    )
    // Spaces advance the pen but are not drawn, so the glyph count is the non-space characters.
    let drawn = DeathSequence.message.filter { $0 != " " }.count
    #expect(glyphs.count == drawn, "a glyph for every character that is not a space")
}
