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
func driveBehaviour(
    _ state: inout ActorState,
    intents: Intents,
    world: any TileWorld
) {
    var ignored: [ActorEffect] = []
    try? Behaviour.update(
        &state, intents: intents, world: world,
        interpreter: makeKidInterpreter(), effects: &ignored
    )
}
