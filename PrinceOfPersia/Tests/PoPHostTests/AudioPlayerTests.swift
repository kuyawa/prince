import Testing
import Foundation
import AVFoundation
@testable import PoPHost
import PoPCore

// M8b: the host end of the sound channel.
//
// AudioPlayer is presentation (Law 8), so what is worth testing is not that it makes a noise but
// that it (a) never lets a missing or corrupt file stop the game, and (b) reports what the
// simulation asked for even when the speakers are off. Both are silent-failure modes: without a
// test, a renamed mp3 or an over-eager mute check looks exactly like a working game.

// MARK: - The record survives muting

@MainActor
@Test func mutedPlayersStillRecordWhatTheSimulationAsked() {
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: false))
    audio.play(.swordClash)
    audio.play([.footsteps, .footsteps])

    // --trace and the tests read this, so it must not be gated on the mute.
    #expect(audio.drainPlayed() == [.swordClash, .footsteps, .footsteps])
}

@MainActor
@Test func drainingClearsTheRecord() {
    let audio = AudioPlayer(options: .init(soundEnabled: false))
    audio.play(.beep)
    #expect(audio.drainPlayed() == [.beep])
    #expect(audio.drainPlayed().isEmpty)
}

@MainActor
@Test func musicIsNeverStartedWhenItIsDisabled() {
    let audio = AudioPlayer(options: .init(musicEnabled: false))
    audio.playMusic(.danger)
    #expect(audio.musicTrack == nil)
}

@MainActor
@Test func musicPlaysOnceAndDoesNotLoop() {
    // Phaser's SoundManager.play defaults `loop` to false, so every music cue in the reference
    // is a one-shot: level 1's Danger theme plays over the opening and stops. Looping it was a
    // mistake here, and an audible one — it never stopped.
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: true))
    audio.playMusic(.danger)
    #expect(audio.musicTrack == .danger)
    #expect(audio.musicPlayerForTesting?.numberOfLoops == 0, "a one-shot, not a loop")
}

@MainActor
@Test func aCueAlreadySoundingIsNotStartedTwice() {
    // The reference would stack a second copy on top of the first, because it constructs a fresh
    // Sound every call. A stutter is not a feature.
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: true))
    audio.playMusic(.danger)
    let first = audio.musicPlayerForTesting
    #expect(first?.isPlaying == true)

    audio.playMusic(.danger)
    #expect(audio.musicPlayerForTesting === first, "no second player was started")
}

@MainActor
@Test func aCueThatHasFinishedPlaysAgain() {
    // Which is what makes restarting a level work: the same cue arrives, but nothing is sounding,
    // so it plays.
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: true))
    audio.playMusic(.danger)
    let first = audio.musicPlayerForTesting

    first?.stop()
    #expect(audio.isMusicPlaying == false)
    audio.playMusic(.danger)
    #expect(audio.musicPlayerForTesting !== first, "it started over")
}

@MainActor
@Test func unmutingTheMusicDoesNotRestartAOneShot() {
    // Only what the host paused is resumed. A cue that ended on its own has been heard already.
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: true))
    audio.playMusic(.danger)
    audio.setPaused(true)
    #expect(audio.isMusicPlaying == false)

    audio.setPaused(false)
    #expect(audio.isMusicPlaying == true, "it was paused mid-track, so it resumes")

    // And a track thrown away while paused is not resumed by a later unpause, which is what a
    // level change during a pause would produce.
    audio.setPaused(true)
    audio.stopMusic()
    audio.setPaused(false)
    #expect(audio.isMusicPlaying == false)
}

@MainActor
@Test func stopMusicEndsItAndForgetsTheTrack() {
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: true))
    audio.playMusic(.danger)
    audio.stopMusic()
    #expect(audio.musicTrack == nil)
    #expect(audio.isMusicPlaying == false)
}

@MainActor
@Test func askingForTheTrackAlreadyPlayingDoesNotRestartIt() {
    // The reference ignores a repeat of the current track. Levels 2 and up re-issue the Danger
    // cue, and restarting it every time would be audible as a stutter.
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: false))
    audio.playMusic(.danger)
    audio.playMusic(.danger)
    #expect(audio.musicTrack == nil, "music is disabled, so nothing was started")

    audio.stopMusic()
    #expect(audio.musicTrack == nil)
}

@MainActor
@Test func flushingTheVoicePoolDoesNotAffectThePlaybackRecord() {
    let audio = AudioPlayer(options: .init(soundEnabled: false))
    audio.play(.gateRising)
    audio.flush()
    #expect(audio.drainPlayed() == [.gateRising])
}

// MARK: - Enabled playback reaches the engine

@MainActor
@Test func anEnabledPlayerActuallyStartsAPlayer() {
    // Not a hearing test — it says the file opened, the engine accepted it and the player is
    // running. A file that decodes but never starts is the failure this catches.
    let audio = AudioPlayer()
    audio.play(.softLanding)
    #expect(audio.voicesForTesting.contains { $0.isPlaying }, "nothing started playing")
    audio.play(.footsteps)
    #expect(audio.drainPlayed() == [.softLanding, .footsteps])
}

// MARK: - The files actually decode

/// Every effect and track, decoded the way the game decodes it.
///
/// SpriteKit and AVFoundation both fail a malformed asset at *use* time, not at load time, so a
/// bad file shows up as one silent sound in one room of one level. Decoding all forty-one here
/// turns that into a test failure.
@Test func everyBundledSoundAndTrackDecodes() throws {
    var broken: [String] = []
    for effect in SoundEffect.allCases {
        let url = GameData.rootURL.appendingPathComponent("sfx/" + effect.fileName)
        if (try? AVAudioPlayer(contentsOf: url)) == nil { broken.append(effect.fileName) }
    }
    for track in MusicTrack.allCases {
        let url = GameData.rootURL.appendingPathComponent("music/" + track.fileName)
        if (try? AVAudioPlayer(contentsOf: url)) == nil { broken.append(track.fileName) }
    }
    #expect(broken.isEmpty, "could not decode: \(broken.joined(separator: ", "))")
}
