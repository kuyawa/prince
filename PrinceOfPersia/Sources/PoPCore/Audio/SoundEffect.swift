/// Every sound the game can make.
///
/// Port source: `reference/PrinceJS/src/Preloader.js`, which registers each of these by name
/// against an mp3 in `assets/sfx/`. The names are the reference's own, and the enum's raw values
/// are those names so a mismatch is visible rather than silent.
///
/// Three of the effects are *variants* rather than distinct sounds — the loose floor's three
/// shakes are picked at random by `Utils.random(3)` in the reference. Making them an explicit
/// list keeps that choice on the simulation side, where the generator lives.
public enum SoundEffect: String, Sendable, CaseIterable {
    case freeFallLand = "FreeFallLand"
    case looseFloorLands = "LooseFloorLands"
    case looseFloorShakes1 = "LooseFloorShakes1"
    case gateComingDownSlow = "GateComingDownSlow"
    case gateRising = "GateRising"
    case gateReachesBottomClang = "GateReachesBottomClang"
    case gateStopsAtTop = "GateStopsAtTop"
    case bumpIntoWallSoft = "BumpIntoWallSoft"
    case bumpIntoWallHard = "BumpIntoWallHard"
    case swordClash = "SwordClash"
    case stabAir = "StabAir"
    case stabOpponent = "StabOpponent"
    case stabbedByOpponent = "StabbedByOpponent"
    case mediumLandingOof = "MediumLandingOof"
    case softLanding = "SoftLanding"
    case unsheatheSword = "UnsheatheSword"
    case looseFloorShakes3 = "LooseFloorShakes3"
    case looseFloorShakes2 = "LooseFloorShakes2"
    case floorButton = "FloorButton"
    case footsteps = "Footsteps"
    case bonesLeapToLife = "BonesLeapToLife"
    case mirror = "Mirror"
    case halvedByChopper = "HalvedByChopper"
    case slicerBladesClash = "SlicerBladesClash"
    case hardLandingSplat = "HardLandingSplat"
    case impaledBySpikes = "ImpaledBySpikes"
    case doorSqueak = "DoorSqueak"
    case fallingFloorLands = "FallingFloorLands"
    case entranceDoorCloses = "EntranceDoorCloses"
    case exitDoorOpening = "ExitDoorOpening"
    case drinkPotionGlugGlug = "DrinkPotionGlugGlug"
    case beep = "Beep"
    case spikedBySpikes = "SpikedBySpikes"

    /// The mp3 this effect is loaded from, exactly as `Preloader` names it.
    public var fileName: String {
        switch self {
        case .freeFallLand: "01_Free_fall_land.mp3"
        case .looseFloorLands: "02_Loose_floor_lands.mp3"
        case .looseFloorShakes1: "03_Loose_floor_shakes.mp3"
        case .gateComingDownSlow: "04_Gate_coming_down_slow.mp3"
        case .gateRising: "05_Gate_rising.mp3"
        case .gateReachesBottomClang: "06_Gate_reaches_bottom_clang.mp3"
        case .gateStopsAtTop: "07_Gate_stops_at_top.mp3"
        case .bumpIntoWallSoft: "08_Bump_into_wall_soft.mp3"
        case .bumpIntoWallHard: "09_Bump_into_wall_hard.mp3"
        case .swordClash: "10_Sword_clash.mp3"
        case .stabAir: "11_Stab_air.mp3"
        case .stabOpponent: "12_Stab_opponent.mp3"
        case .stabbedByOpponent: "13_Stabbed_by_opponent.mp3"
        case .mediumLandingOof: "14_Medium_landing_oof.mp3"
        case .softLanding: "15_Soft_landing.mp3"
        case .unsheatheSword: "16_Unsheathe_sword.mp3"
        case .looseFloorShakes3: "17_Loose_floor_shakes_3.mp3"
        case .looseFloorShakes2: "18_Loose_floor_shakes_2.mp3"
        case .floorButton: "19_Floor_button.mp3"
        case .footsteps: "20_Footsteps.mp3"
        case .bonesLeapToLife: "21_Bones_leap_to_life.mp3"
        case .mirror: "22_Mirror.mp3"
        case .halvedByChopper: "23_Halved_by_chopper.mp3"
        case .slicerBladesClash: "24_Slicer_blades_clash.mp3"
        case .hardLandingSplat: "25_Hard_landing_splat.mp3"
        case .impaledBySpikes: "26_Impaled_by_spikes.mp3"
        case .doorSqueak: "27_Door_squeak.mp3"
        case .fallingFloorLands: "28_Falling_floor_lands.mp3"
        case .entranceDoorCloses: "29_Entrance_door_closes.mp3"
        case .exitDoorOpening: "30_Exit_door_opening.mp3"
        case .drinkPotionGlugGlug: "31_Drink_potion_glug_glug.mp3"
        case .beep: "32_Beep.mp3"
        case .spikedBySpikes: "33_Spiked_by_spikes.mp3"
        }
    }

    /// `Loose.shake` picks one of three at random. Kept here so the choice can be made against a
    /// seeded generator rather than by the host.
    public static let looseFloorShakeVariants: [SoundEffect] = [
        .looseFloorShakes1, .looseFloorShakes2, .looseFloorShakes3,
    ]
}

/// The music.
///
/// `Preloader` loads only these eight of the twenty-two files in `music/`; the rest are used by
/// the cutscenes, which are not ported.
public enum MusicTrack: String, Sendable, CaseIterable {
    case prologueA = "PrologueA"
    case prologueB = "PrologueB"
    case danger = "Danger"
    case accident = "Accident"
    case potion1 = "Potion1"
    case victory = "Victory"
    case prince = "Prince"
    case potion2 = "Potion2"

    public var fileName: String {
        switch self {
        case .prologueA: "01_Prologue_A.mp3"
        case .prologueB: "02_Prologue_B.mp3"
        case .danger: "06_Danger.mp3"
        case .accident: "07_Accident.mp3"
        case .potion1: "08_Potion_1.mp3"
        case .victory: "09_Victory.mp3"
        case .prince: "11_Prince.mp3"
        case .potion2: "14_Potion_2.mp3"
        }
    }
}
