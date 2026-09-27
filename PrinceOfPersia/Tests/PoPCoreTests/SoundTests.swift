import Testing
import Foundation
@testable import PoPCore

// M8b: the sounds the simulation asks for, and the files that answer them.
//
// Two jobs. First, that every case in SoundEffect/MusicTrack names a file that is actually in the
// bundle — a renamed mp3 would otherwise fail silently at runtime and only be noticed by a player
// who knew the game. Second, that the effect channel carries sound to the host at the moments the
// reference plays it.
//
// The reference calls game.sound.play(...) as a global side effect, so there is no trace to diff
// against. These tests establish the contract from the port source line by line instead, and pin
// the timings the game actually exhibits.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }

private func soundRoot() -> URL { GameData.rootURL }

// MARK: - The files exist

@Test func everySoundEffectNamesAFileThatIsOnDisk() throws {
    var missing: [String] = []
    for effect in SoundEffect.allCases {
        let url = soundRoot().appendingPathComponent("sfx/" + effect.fileName)
        if !FileManager.default.fileExists(atPath: url.path) { missing.append(effect.fileName) }
    }
    #expect(missing.isEmpty, "missing sound files: \(missing.joined(separator: ", "))")
    #expect(SoundEffect.allCases.count == 33, "Preloader registers thirty-three effects")
}

@Test func everyMusicTrackNamesAFileThatIsOnDisk() throws {
    var missing: [String] = []
    for track in MusicTrack.allCases {
        let url = soundRoot().appendingPathComponent("music/" + track.fileName)
        if !FileManager.default.fileExists(atPath: url.path) { missing.append(track.fileName) }
    }
    #expect(missing.isEmpty, "missing music files: \(missing.joined(separator: ", "))")
    // Preloader loads eight of the twenty-two files in music/; the rest belong to cutscenes.
    #expect(MusicTrack.allCases.count == 8)
}

@Test func noTwoEffectsShareAFile() {
    // A copy-paste in the mapping would make two different events sound identical, which is
    // exactly the kind of bug a listening test catches and a unit test does not.
    let names = SoundEffect.allCases.map(\.fileName)
    #expect(Set(names).count == names.count)
    let tracks = MusicTrack.allCases.map(\.fileName)
    #expect(Set(tracks).count == tracks.count)
}

@Test func theLooseFloorsThreeShakeVariantsAreDistinct() {
    // Loose.update picks one of three with Utils.random(3). They must be three different
    // sounds, or the choice the simulation makes is meaningless.
    let variants = SoundEffect.looseFloorShakeVariants
    #expect(variants.count == 3)
    #expect(Set(variants.map(\.fileName)).count == 3)
}

@Test func rawValuesMatchTheNamesTheReferenceUses() {
    // The raw values are the reference names, so a typo is visible rather than silent.
    #expect(SoundEffect.footsteps.rawValue == "Footsteps")
    #expect(SoundEffect.gateRising.rawValue == "GateRising")
    #expect(SoundEffect.floorButton.rawValue == "FloorButton")
    #expect(SoundEffect(rawValue: "GateRising") == .gateRising)
    #expect(MusicTrack.danger.rawValue == "Danger")
}

// MARK: - The simulation emits them

/// Every sound the run produced, in order.
private func sounds(
    of simulation: inout Simulation, ticks: Int, intents: Intents = []
) -> [SoundEffect] {
    var heard: [SoundEffect] = []
    for _ in 0..<ticks {
        simulation.tick(intents: intents)
        for effect in simulation.effects {
            if case let .sound(sound) = effect { heard.append(sound) }
        }
    }
    return heard
}

/// `#expect`'s message is a `Comment`, not a `String`, so build one rather than a literal.
private func names(_ heard: [SoundEffect]) -> Comment {
    Comment(rawValue: heard.map(\.fileName).joined(separator: ", "))
}

@Test func thePrinceLandsOnHisFirstTicksInTheCell() throws {
    // He spawns at location 1, which is on the loose board in room 1, and the first few ticks
    // settle him onto it. Fighter.land plays a soft landing for a drop of one floor or none.
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    let heard = sounds(of: &simulation, ticks: 10)
    #expect(heard.contains(.softLanding), "expected a landing, heard \(names(heard))")
}

@Test func walkingPlaysFootsteps() throws {
    // Kid.TAP(1) and Enemy.TAP(1). The Prince must cross the loose board to get out, so a few
    // seconds of held-right is a walk rather than a wall bump.
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    let heard = sounds(of: &simulation, ticks: 120, intents: [.right])
    #expect(heard.contains(.footsteps), "expected footsteps, heard \(names(heard))")
}

@Test func runningOntoTheLooseBoardShakesIt() throws {
    // The board at room 1 (6,2) is the only way out of the cell. Standing on it shakes it, which
    // Loose.update reports on frames 0, 3 and 7 as one of the three shake variants.
    var simulation = try Simulation(level: try levelOne(), seed: 1)
    let heard = sounds(of: &simulation, ticks: 200, intents: [.right])
    let shakes = heard.filter { SoundEffect.looseFloorShakeVariants.contains($0) }
    #expect(!shakes.isEmpty, "expected the board to shake, heard \(names(heard))")
}

@Test func aRaisedGateReportsItsOwnSound() throws {
    // Mechanisms are not actors, so their sound travels the tile path: LevelState.update returns
    // what the gates and boards made, and World.update(effects:) forwards it.
    var world = World(try levelOne())
    world.pressButton(at: TileRef(room: 5, x: 4, y: 0))

    var heard: [SoundEffect] = []
    for _ in 0..<10 {
        var effects: [ActorEffect] = []
        world.update(effects: &effects)
        for effect in effects {
            if case let .sound(sound) = effect { heard.append(sound) }
        }
    }
    #expect(heard.contains(.gateRising), "heard \(names(heard))")
    // Gate.update only plays on even positions, so two gates rising for ten ticks cannot
    // produce a wall of sound.
    #expect(heard.count <= 12, "ten ticks produced \(heard.count) sounds")
}

@Test func anUntouchedLevelsMechanismsMakeNoNoise() throws {
    var world = World(try levelOne())
    var effects: [ActorEffect] = []
    for _ in 0..<20 {
        effects.removeAll()
        world.update(effects: &effects)
        #expect(effects.isEmpty, "an untouched mechanism made noise")
    }
}

@Test func aFallingActorCountsTheFloorsAsItDrops() throws {
    // Fighter.updateFallingBlocks plays FallingFloorLands when fallingBlocks === 5, and only
    // for the kid. It is a cry, not a landing: it happens in mid-air, five floors down. The
    // count is what the interpreter watches for.
    var state = ActorState.prince(from: try GameData.level(1).prince, levelNumber: 1)
    state.isInFallDown = true
    state.charBlockY = 2

    var drops: [Int] = []
    for _ in 0..<3 {
        state.charBlockY -= 1
        drops.append(state.updateBlockPosition())
    }
    #expect(drops == [1, 2, 3])

    // Rows clamp at zero, so a further step is not a drop and reports nothing.
    state.charBlockY = 0
    #expect(state.updateBlockPosition() == 0)
}
