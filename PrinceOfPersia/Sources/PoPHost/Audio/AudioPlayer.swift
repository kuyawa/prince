import AVFoundation
import PoPCore

/// Plays the game’s sounds and music.
///
/// This is the only file in the project that imports AVFoundation, and it is the whole of the
/// host’s audio policy: **the simulation decides *what* sound happens and *when*; this decides
/// how it comes out of the speakers.** Nothing here feeds anything back into PoPCore.
///
/// Design notes:
///
/// * **Voices, not one player.** AVAudioPlayer is single-shot: calling play() on a player that is
///   already playing restarts it. Footsteps land two or three ticks apart and a sword clash
///   overlaps the stab that follows it, so each effect gets a small round-robin pool. Three voices
///   is enough for every overlap the game can produce and costs nothing until used.
///
/// * **Loaded lazily.** Level 1 needs eight of the thirty-three effects. Decoding the other
///   twenty-five at launch would put an audible stall in front of the first frame for no gain.
///
/// * **Failing is silent.** A missing or undecodable file disables that one effect and logs once.
///   Audio is presentation (Law 8): it must never be able to stop the game running.
@MainActor
public final class AudioPlayer {
    /// Voices per effect. Overlaps beyond this restart the oldest, which is what the ear expects.
    public static let voicesPerEffect = 3

    public struct Options: Sendable {
        public var soundEnabled: Bool
        public var musicEnabled: Bool
        /// 0…1, applied on top of the per-effect volumes.
        public var volume: Float

        public init(soundEnabled: Bool = true, musicEnabled: Bool = true, volume: Float = 1) {
            self.soundEnabled = soundEnabled
            self.musicEnabled = musicEnabled
            self.volume = volume
        }
    }

    /// Preloader sets the effects loud and the music underneath them.
    public static let soundVolume: Float = 0.7
    public static let musicVolume: Float = 0.45

    private let root: URL
    private var options: Options

    private var voices: [SoundEffect: [AVAudioPlayer]] = [:]
    private var cursor: [SoundEffect: Int] = [:]
    private var failed: Set<SoundEffect> = []

    private var musicPlayer: AVAudioPlayer?
    private var currentTrack: PoPCore.MusicTrack?

    /// Whether the music is stopped because the host asked, rather than because it ended.
    private var isPausedByHost = false

    /// Every effect played since the last drain, in order. For tests and --trace.
    public private(set) var played: [SoundEffect] = []

    public init(root: URL = GameData.rootURL, options: Options = Options()) {
        self.root = root
        self.options = options
    }

    // MARK: - Effects

    public func play(_ effect: SoundEffect) {
        // Recorded before the mute check, so --trace and the tests see what the simulation asked
        // for and not merely what the speakers were allowed to do.
        played.append(effect)
        guard options.soundEnabled else { return }
        guard let voice = nextVoice(for: effect) else { return }
        voice.volume = Self.soundVolume * options.volume
        voice.currentTime = 0
        voice.play()
    }

    /// Plays a batch of effects in the order the simulation produced them.
    public func play(_ effects: [SoundEffect]) {
        for effect in effects { play(effect) }
    }

    private func nextVoice(for effect: SoundEffect) -> AVAudioPlayer? {
        if let pool = voices[effect], !pool.isEmpty {
            // Prefer a voice that has finished, so a slow-decaying sound is not cut off.
            if let free = pool.firstIndex(where: { !$0.isPlaying }) { return pool[free] }
            let index = (cursor[effect] ?? 0) % pool.count
            cursor[effect] = index + 1
            return pool[index]
        }

        guard let player = load(effect) else { return nil }
        var pool = [player]
        // Fill the rest of the pool up front so the next two calls cannot stall.
        for _ in 1..<Self.voicesPerEffect {
            if let extra = load(effect) { pool.append(extra) }
        }
        voices[effect] = pool
        cursor[effect] = 1
        return player
    }

    private func load(_ effect: SoundEffect) -> AVAudioPlayer? {
        if failed.contains(effect) { return nil }
        let url = root.appendingPathComponent("sfx/" + effect.fileName)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            failed.insert(effect)
            log("could not load " + effect.fileName + ": " + error.localizedDescription)
            return nil
        }
    }

    // MARK: - Music

    /// Starts a track. **Once** — the music in this game never loops.
    ///
    /// Phaser’s `SoundManager.play` passes `loop` straight through and defaults it to false, so
    /// every music cue in the reference is a one-shot: level 1’s Danger theme plays over the
    /// opening and stops, and the Victory fanfare on taking the sword plays once. Looping them
    /// was a mistake here, and an audible one.
    ///
    /// **A re-issued cue that has already finished plays again**, which is what makes restarting
    /// a level work. Only a cue for the track that is *still sounding* is ignored — the reference
    /// would stack a second copy on top of the first, and a stutter is not a feature.
    public func playMusic(_ track: PoPCore.MusicTrack) {
        guard options.musicEnabled else { return }
        guard !(currentTrack == track && musicPlayer?.isPlaying == true) else { return }

        let url = root.appendingPathComponent("music/" + track.fileName)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = Self.musicVolume * options.volume
            player.prepareToPlay()
            player.play()
            musicPlayer?.stop()
            musicPlayer = player
            currentTrack = track
        } catch {
            log("could not load " + track.fileName + ": " + error.localizedDescription)
        }
    }

    public func stopMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        currentTrack = nil
        // Otherwise a later unpause would resume a track that has been thrown away.
        isPausedByHost = false
    }

    public var musicTrack: PoPCore.MusicTrack? { currentTrack }

    /// Whether a track is sounding right now. A one-shot ends on its own, so this goes false
    /// without anybody asking it to.
    public var isMusicPlaying: Bool { musicPlayer?.isPlaying ?? false }

    /// The music player, for tests. Reading its numberOfLoops is how a test checks that a cue is
    /// a one-shot rather than a loop, and its identity is how a test checks that a repeat did not
    /// start a second copy.
    public var musicPlayerForTesting: AVAudioPlayer? { musicPlayer }

    /// Pauses or resumes the music, for a pause menu or for losing focus.
    ///
    /// Only resumes what it paused. Without the flag, unpausing after a one-shot had finished on
    /// its own would start it over — a cue the player has already heard, playing again for no
    /// reason.
    public func setPaused(_ paused: Bool) {
        if paused {
            guard musicPlayer?.isPlaying == true else { return }
            musicPlayer?.pause()
            isPausedByHost = true
        } else if isPausedByHost {
            // `isPausedByHost` is the whole test. A paused player cannot progress, so if we
            // paused it, it is still where we left it; and a cue that ended on its own never
            // set the flag, so it is not resumed. Checking `currentTime` instead would break
            // the pause-immediately-after-start case, where it is still zero.
            musicPlayer?.play()
            isPausedByHost = false
        }
    }

    // MARK: - Housekeeping

    public func drainPlayed() -> [SoundEffect] {
        defer { played.removeAll(keepingCapacity: true) }
        return played
    }

    /// The decoded voices, for tests. Reading them is how a host test checks that a sound
    /// actually started rather than merely decoded.
    public var voicesForTesting: [AVAudioPlayer] {
        voices.values.flatMap { $0 }
    }
    /// Drops every decoded voice. Called when a level change would otherwise leave a roomful of
    /// boards and gates resident.
    public func flush() {
        voices.removeAll()
        cursor.removeAll()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data(("[Prince/audio] " + message + "\n").utf8))
    }
}
