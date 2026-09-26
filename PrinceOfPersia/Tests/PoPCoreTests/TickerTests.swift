import Testing
@testable import PoPCore

// M3: the fixed-timestep clock.

@Test func ratesComeFromTheReference() {
    #expect(Ticker.normalTickDuration == 1.0 / 12.0)
    #expect(Ticker.combatTickDuration == 1.0 / 10.0)
    #expect(Ticker.maximumCatchUpTicks == 5)
    #expect(Ticker().tickDuration == Ticker.normalTickDuration)
}

@Test func twelveHertzProducesOneTickPerFrame() {
    var ticker = Ticker()
    var total = 0
    // 120 frames at 60 Hz is two seconds: exactly 24 ticks at 12 Hz.
    for _ in 0..<120 { total += ticker.ticks(forElapsed: 1.0 / 60.0) }
    #expect(total == 24)
}

@Test func oneHundredTwentyHertzDoesNotRunTenTimesFast() {
    // The whole point of Law 4. A ProMotion display delivering 240 frames over two
    // seconds must still produce 24 ticks, not 240.
    var ticker = Ticker()
    var total = 0
    for _ in 0..<240 { total += ticker.ticks(forElapsed: 1.0 / 120.0) }
    #expect(total == 24)
}

@Test func combatChangesTheRateGlobally() {
    var ticker = Ticker()
    ticker.isFighting = true
    #expect(ticker.tickDuration == Ticker.combatTickDuration)
    var total = 0
    // Two seconds at 10 Hz is 20 ticks.
    for _ in 0..<120 { total += ticker.ticks(forElapsed: 1.0 / 60.0) }
    #expect(total == 20)
}

@Test func aLongHitchIsCappedRatherThanSpiralling() {
    var ticker = Ticker()
    // A five-second stall would be 60 ticks at 12 Hz.
    let ticks = ticker.ticks(forElapsed: 5.0)
    #expect(ticks == Ticker.maximumCatchUpTicks)
}

@Test func excessiveTimeIsDiscardedNotBanked() {
    var ticker = Ticker()
    _ = ticker.ticks(forElapsed: 5.0)
    // The backlog must be gone: the next ordinary frame yields at most one tick.
    let next = ticker.ticks(forElapsed: 1.0 / 60.0)
    #expect(next <= 1)
}

@Test func nonsenseDeltasAreIgnored() {
    var ticker = Ticker()
    #expect(ticker.ticks(forElapsed: 0) == 0)
    #expect(ticker.ticks(forElapsed: -1) == 0)
    #expect(ticker.ticks(forElapsed: .nan) == 0)
    #expect(ticker.ticks(forElapsed: .infinity) == 0)
}

@Test func interpolationReportsProgressTowardTheNextTick() {
    var ticker = Ticker()
    #expect(ticker.interpolation == 0)
    _ = ticker.ticks(forElapsed: Ticker.normalTickDuration / 2)
    #expect(abs(ticker.interpolation - 0.5) < 0.0001)
}
