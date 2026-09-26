import Testing
@testable import PoPCore

// M6d: the death splash, the hourglass running out, and the medium landing it turned out to fix.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

private func kid(_ action: String = "stand") -> ActorState {
    var state = ActorState(location: 0, room: 1, face: 1, action: action, charName: "kid")
    state.isAlive = true
    return state
}

// MARK: - The splash

@Test func aHitShowsTheSplashForTwoTicks() {
    var state = kid()
    #expect(!state.isSplashVisible)
    #expect(state.splashOffsetY == Splash.restingOffsetY)

    Splash.show(&state)
    #expect(state.isSplashVisible)
    #expect(state.splashTimer == Splash.ticks)

    Splash.update(&state)
    #expect(state.isSplashVisible, "still up after one tick")
    Splash.update(&state)
    #expect(!state.isSplashVisible, "and gone after two")
    #expect(state.splashOffsetY == Splash.restingOffsetY)
}

@Test func theFourSelfBloodyingDeathsShowNoSplash() {
    // `dropdead`, `falldead`, `impale` and `halve` are drawn with their own gore; a pool under
    // them would be wrong. So a *death* shows no splash unless the blow that caused it started
    // from some other action.
    for action in Splash.selfBloodying {
        var state = kid(action)
        Splash.show(&state)
        #expect(!state.isSplashVisible, "\(action) draws its own")
    }

    // But an ordinary action does show one, including the one a death is about to replace.
    var standing = kid("engarde")
    Splash.show(&standing)
    #expect(standing.isSplashVisible)
}

@Test func theOrderOfShowAndBeginActionMatters() {
    // `damageLife` calls `showSplash` *before* it touches the action. Reverse the two and the
    // last hit of a fight — the one that sets `dropdead` — loses its splash entirely.
    var state = kid("engarde")
    state.health = 1
    var effects: [ActorEffect] = []
    Combat.damageLife(&state, effects: &effects)

    #expect(!state.isAlive)
    #expect(state.action == "dropdead")
    #expect(state.isSplashVisible, "shown before the death animation took over")
}

@Test func aSkeletonHasNoBlood() {
    var state = ActorState(location: 0, room: 1, face: 1, action: "stand", charName: "skeleton")
    Splash.show(&state)
    #expect(!state.isSplashVisible)
    Splash.tint(&state, colour: 0xff0000)
    #expect(state.splashTint == nil)
}

@Test func aCrouchingHitDrawsThePoolHigher() {
    var state = kid("medland")
    Splash.show(&state, crouching: true)
    #expect(state.splashOffsetY == Splash.crouchingOffsetY)

    // And it goes back to resting height once it fades.
    Splash.update(&state)
    Splash.update(&state)
    #expect(state.splashOffsetY == Splash.restingOffsetY)
}

@Test func theSplashComesFromTheBaseCharactersSheet() {
    // There is no per-colour splash art: a `guard-3` draws `guard-splash`, which is why the frame
    // name is built from `baseCharName`. Same trick the life pips use.
    var guardState = ActorState(
        location: 0, room: 1, face: 1, action: "stand", charName: "guard-3"
    )
    guardState.baseCharName = "guard"
    #expect(Splash.frameName(for: guardState) == "guard-splash")
    #expect(Splash.frameName(for: kid()) == "kid-splash")
}

@Test func guardsAreTintedFromTheirColour() throws {
    let level = try LevelRuntime(try GameData.level(1))
    var world = World(level)
    // `guard` is a Swift keyword, so the loop variable cannot be called that.
    let foes = world.actors.dropFirst()
    #expect(!foes.isEmpty, "level 1 has guards")
    for foe in foes {
        #expect(foe.splashTint != nil, "\(foe.charName) should be tinted")
    }
    #expect(world.actors[0].splashTint == nil, "the Prince is not")
}

@Test func theSplashReachesTheRenderer() {
    var state = kid("engarde")
    var sprites = RoomRenderer.describe(state)
    #expect(!sprites.contains { $0.frameName.hasSuffix("-splash") })

    Splash.show(&state)
    sprites = RoomRenderer.describe(state)
    let splash = sprites.first { $0.frameName.hasSuffix("-splash") }
    #expect(splash != nil)
    #expect(splash?.atlas == "general", "the splash lives in the general atlas")
    #expect(splash?.anchor == .bottomLeft)
    #expect(splash?.x == sprites[0].x + Splash.offsetX)
    #expect(splash?.y == sprites[0].y + Splash.restingOffsetY)
}

// MARK: - The medium landing

@Test func aMediumLandingAtOneHealthIsFatal() throws {
    // `Kid.land` calls `damageLife(true)` for a two-floor drop, and `damageLife` calls `die` at
    // one health. Inlining a bare `health -= 1` left a Prince at zero health and still alive.
    var state = kid("freefall")
    state.health = 1
    state.charBlockY = 1
    state.charY = CoordinateSpace.y(fromBlockY: 1)
    state.fallingBlocks = 2
    state.isInFallDown = true

    let world = World(try levelOne())
    let interpreter = makeKidInterpreter()
    var effects: [ActorEffect] = []
    try FallCycle.land(&state, world: world, interpreter: interpreter, effects: &effects)

    #expect(!state.isAlive, "one health and a two-floor drop is the end of him")
    #expect(state.health == 0)
    #expect(state.action == "dropdead")
    #expect(effects.contains(.sound(.mediumLandingOof)))
    #expect(state.isSplashVisible, "and he went down on one knee")
    #expect(state.splashOffsetY == Splash.crouchingOffsetY)
}

@Test func aMediumLandingAtFullHealthOnlyWounds() throws {
    var state = kid("freefall")
    state.health = 3
    state.charBlockY = 1
    state.charY = CoordinateSpace.y(fromBlockY: 1)
    state.fallingBlocks = 2
    state.isInFallDown = true

    let world = World(try levelOne())
    var effects: [ActorEffect] = []
    try FallCycle.land(
        &state, world: world, interpreter: makeKidInterpreter(), effects: &effects
    )
    #expect(state.isAlive)
    #expect(state.health == 2)
    #expect(state.action == "medland")
}

// MARK: - The hourglass

@Test func theCountdownRunsForAnHourOfTicks() {
    // The unit matters: sixty minutes is 43,200 ticks of 1/12 s, not 3,600. Getting that wrong
    // makes the hourglass expire after five minutes of play, which is the kind of thing that
    // reads as "the clock is too fast" rather than as an arithmetic error.
    var clock = GameClock()
    #expect(!clock.hasExpired)
    #expect(clock.remainingMinutes == 60)

    let ticksInAnHour = Int(Double(GameClock.startingMinutes * 60) / Ticker.normalTickDuration)
    #expect(ticksInAnHour == 43_200)

    for _ in 0..<(ticksInAnHour - 1) { clock.advance() }
    #expect(!clock.hasExpired, "one tick short of the hour")
    // The final minute reads *1*, not 0: the countdown reaches zero only as the hourglass empties,
    // and that is the same tick that raises timeUp. So the seconds readout is what the last minute
    // shows, which is the whole reason the bar switches format.
    #expect(clock.remainingMinutes == 1)
    #expect(clock.readout == .seconds(clock.remainingSeconds))

    clock.advance()
    #expect(clock.hasExpired)
    #expect(clock.readout == .timeUp(clock.remainingSeconds))
}

@Test func timeUpIsEmittedOnTheTickTheHourglassEmpties() throws {
    // Wind the clock to one tick short, then let the simulation run the last one. The hourglass
    // is a *mechanic*, not decoration: the run genuinely ends when it empties.
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    let ticksInAnHour = try #require(
        Int(exactly: Double(GameClock.startingMinutes * 60) / Ticker.normalTickDuration)
    )
    simulation.advanceClock(ticks: ticksInAnHour - 1)
    #expect(!simulation.clock.hasExpired)

    simulation.tick(intents: [])
    #expect(simulation.clock.hasExpired)
    #expect(simulation.effects.contains(.timeUp))

    // And only once: a second tick does not raise it again.
    simulation.tick(intents: [])
    #expect(!simulation.effects.contains(.timeUp))
}
