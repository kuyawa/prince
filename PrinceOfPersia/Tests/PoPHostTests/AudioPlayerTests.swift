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
@Test func musicStartsAndSurvivesARepeatRequest() {
    // The only cue the port has on a level start is level 1's Danger theme, so this is the path
    // that actually runs in the game. Music off is tested above; music on has to reach the engine.
    let audio = AudioPlayer(options: .init(soundEnabled: false, musicEnabled: true))
    audio.playMusic(.danger)
    #expect(audio.musicTrack == .danger)

    // A second request for the track already playing is ignored, so the theme is not restarted
    // every time a level re-issues the cue.
    audio.playMusic(.danger)
    #expect(audio.musicTrack == .danger)

    audio.stopMusic()
    #expect(audio.musicTrack == nil)
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
