/// The 33 tile kinds of the original game.
///
/// Transcribed from `reference/PrinceJS/src/Level.js`, where they are
/// `PrinceJS.Level.TILE_*`. The numbering is the DOS engine's and is not
/// arbitrary — `element` values in the level data index straight into it.
///
/// Only `0...29` appear in the fourteen shipped levels. `stuckButton` (5),
/// `torchWithDebris` (30), `debrisOnly` (31) and `null` (32) are defined by the
/// engine but unused by the original level set — `stuckButton` is an SDLPoP-era
/// addition. They are modelled anyway so the type is total.
public enum TileKind: Int, Sendable, Hashable, CaseIterable, Codable {
    case space = 0
    case floor = 1
    case spikes = 2
    case pillar = 3
    case gate = 4
    case stuckButton = 5
    case dropButton = 6
    case tapestry = 7
    case bottomBigPillar = 8
    case topBigPillar = 9
    case potion = 10
    case looseBoard = 11
    case tapestryTop = 12
    case mirror = 13
    case debris = 14
    case raiseButton = 15
    case exitLeft = 16
    case exitRight = 17
    case chopper = 18
    case torch = 19
    case wall = 20
    case skeleton = 21
    case sword = 22
    case balconyLeft = 23
    case balconyRight = 24
    case latticePillar = 25
    case latticeSupport = 26
    case smallLattice = 27
    case latticeLeft = 28
    case latticeRight = 29
    case torchWithDebris = 30
    case debrisOnly = 31
    case null = 32
}
