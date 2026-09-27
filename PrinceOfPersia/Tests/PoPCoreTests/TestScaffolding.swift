import Foundation
@testable import PoPCore

// Shared test scaffolding.

/// A kid interpreter, for tests that drive a behaviour verb directly.
///
/// `Behaviour.update` needs one because two of its verbs — `step` into a mirror, and `step` into a
/// gate — call `setBump`, which finishes the tick with `processCommand`.
func makeKidInterpreter() -> SequenceInterpreter {
    SequenceInterpreter(
        table: try! GameData.animationTable(named: "kid"),
        actorClass: .kid,
        swordOffsets: try? GameData.swordOffsetTable()
    )
}

/// Runs `Behaviour.update` for its side effects on the actor, discarding any effects it emits.
///
/// Most behaviour tests are about where the Prince ends up, not about what he said on the way.
/// An inout optional, because that is the shape `Behaviour.update` takes: `Kid.fastsheathe` is
/// the one verb that writes to the opponent. Pass a real one to test the combat arms; `nil` is
/// "nobody to fight", which is what every movement test wants.
func driveBehaviour(
    _ state: inout ActorState,
    intents: Intents,
    world: any TileWorld,
    opponent: ActorState? = nil
) {
    var ignored: [ActorEffect] = []
    var foe = opponent
    try? Behaviour.update(
        &state, intents: intents, world: world,
        interpreter: makeKidInterpreter(), opponent: &foe, effects: &ignored
    )
}
