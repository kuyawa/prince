import Testing
@testable import PoPCore

// M7: the interactive-tile layer — gates, buttons and events.
//
// Level 1's room 5 is a complete puzzle in one room, and it is the fixture throughout:
//
//   x=2  DROP_BUTTON  modifier 11  -> events[11]  gate at (9,0), which starts OPEN
//   x=4  RAISE_BUTTON modifier  9  -> events[9]   gate at (9,0), then CHAINS via next=1
//                                                  to events[10], the gate at (5,0)
//   x=6  RAISE_BUTTON modifier  8  -> events[8]   gate at (9,0)
//   x=5  GATE  modifier 0  (closed)
//   x=9  GATE  modifier 1  (already open)
//
// The button's modifier is a 0-based INDEX into the events array — not the entry's `number`
// field. All three modifiers land on events in room 5, which is where the gates are.

private func levelOne() throws -> LevelRuntime { try LevelRuntime(try GameData.level(1)) }
private func worldOne() throws -> World { World(try levelOne()) }

private func ref(_ x: Int, _ y: Int) -> TileRef { TileRef(room: 5, x: x, y: y) }

// MARK: - Discovery

@Test func levelOneRoomFiveHasTwoGatesAndThreeButtons() throws {
    let world = try worldOne()
    let roomFive = world.state.gates.keys.filter { $0.room == 5 }
    #expect(roomFive.count == 2)
    let buttons = world.state.buttons.keys.filter { $0.room == 5 }
    #expect(buttons.count == 3)
}

@Test func aGateStartsOpenOrClosedAccordingToItsModifier() throws {
    let world = try worldOne()

    // Gate.STATE_* is seeded straight from the modifier: 0 is closed, 1 is open. The position is
    // -modifier * 46, so a modifier of 1 starts the gate 46 of its 47 pixels up.
    let closed = try #require(world.gate(at: ref(5, 0)))
    #expect(closed.phase == .closed)
    #expect(closed.position == 0)

    let open = try #require(world.gate(at: ref(9, 0)))
    #expect(open.phase == .open)
    #expect(open.position == -46)
}

@Test func canCrossIsAPureHeightComparison() {
    #expect(!Gate(modifier: 0).canCross(height: 40))
    #expect(Gate(modifier: 1).canCross(height: 40), "46 up, and the actor is 40 tall")

    var gate = Gate(modifier: 0)
    gate.position = -41
    #expect(gate.canCross(height: 40))
    gate.position = -40
    #expect(!gate.canCross(height: 40), "exactly the actor's height is not enough")
}

@Test func gateBlocksFollowsTheGateState() throws {
    let world = try worldOne()
    // Standing room 5, looking right at each gate.
    #expect(world.gateBlocks(x: 5, y: 0, room: 5), "the closed gate blocks")
    #expect(!world.gateBlocks(x: 9, y: 0, room: 5), "the open gate does not")
}

// MARK: - Buttons and events

@Test func pressingTheRaiseButtonRaisesTheGateAndChainsToTheNextEvent() throws {
    var world = try worldOne()

    // The gate at (5,0) is shut; the one at (9,0) is open.
    #expect(world.gate(at: ref(5, 0))?.phase == .closed)

    world.pressButton(at: ref(4, 0))

    // events[9] raises the gate at (9,0), then next=1 chains to events[10] — the gate at (5,0).
    // Both must be raising.
    #expect(world.gate(at: ref(9, 0))?.phase == .raising)
    #expect(world.gate(at: ref(5, 0))?.phase == .raising, "the chained event reached the second gate")
}

@Test func anEventWithoutNextDoesNotChain() throws {
    var world = try worldOne()
    // events[8] has next=0 and targets only the gate at (9,0).
    world.fire(8, kind: .raiseButton)
    #expect(world.gate(at: ref(9, 0))?.phase == .raising)
    #expect(world.gate(at: ref(5, 0))?.phase == .closed, "nothing chained")
}

@Test func theDropButtonSendsItsGateDownFast() throws {
    var world = try worldOne()
    world.pressButton(at: ref(2, 0))
    let gate = try #require(world.gate(at: ref(9, 0)))
    #expect(gate.phase == .fastDropping)
    #expect(gate.closedFast, "a fast drop is what makes a held button unable to re-raise it")
}

@Test func aHoleInTheEventsArrayIsNotAnError() throws {
    var world = try worldOne()
    // Level 6 has holes; level 1 does not. Firing a nonexistent index must simply do nothing.
    world.fire(999, kind: .raiseButton)
    #expect(world.gate(at: ref(5, 0))?.phase == .closed)
}

// MARK: - Gate motion

@Test func raisingTakesFortySevenStepsThenWaits() throws {
    var gate = Gate(modifier: 0)
    gate.raise(stuck: false)
    #expect(gate.phase == .raising)

    // 47 decrements reach -47, then one more tick flips it to waiting.
    for _ in 0..<47 { gate.update() }
    #expect(gate.position == -47)
    #expect(gate.phase == .raising)

    gate.update()
    #expect(gate.phase == .waiting)
    #expect(gate.position == -47)
}

@Test func aRaisedGateWaitsFiftyTicksThenStartsClosing() throws {
    var gate = Gate(modifier: 0)
    gate.raise(stuck: false)
    for _ in 0..<48 { gate.update() }     // up to waiting
    for _ in 0..<49 { gate.update() }
    #expect(gate.phase == .waiting, "one tick short")

    gate.update()
    #expect(gate.phase == .dropping)
}

@Test func aClosingGateDropsOnePixelEveryFourthTick() throws {
    var gate = Gate(modifier: 0)
    gate.phase = .dropping
    gate.position = -47
    gate.step = 0

    // Four ticks advance the gate by one pixel.
    for _ in 0..<4 { gate.update() }
    #expect(gate.position == -46)
    for _ in 0..<4 { gate.update() }
    #expect(gate.position == -45)
}

@Test func aFastDroppingGateClosesInFiveTicks() throws {
    var gate = Gate(modifier: 0)
    gate.position = -47
    gate.drop()

    var ticks = 0
    while gate.phase != .closed && ticks < 20 {
        gate.update()
        ticks += 1
    }
    #expect(gate.phase == .closed)
    #expect(gate.position == 0)
    #expect(ticks == 5, "ten pixels a tick from -47")
}

@Test func aSlammedGateIgnoresAHeldButtonButNotAFreshPress() {
    var gate = Gate(modifier: 0)
    gate.position = -47
    gate.drop()
    for _ in 0..<5 { gate.update() }
    #expect(gate.phase == .closed)

    // A button still being held re-fires with stuck = true, and a gate that slammed shut stays
    // shut. This is the whole reason `closedFast` exists.
    gate.raise(stuck: true)
    #expect(gate.phase == .closed)

    // A fresh press — the player stepping off and back on — does open it again.
    gate.raise(stuck: false)
    #expect(gate.phase == .raising)
}

@Test func raisingWhileAlreadyFallingDoesNotCancelTheSlam() {
    // The reference's guard excludes STATE_FAST_DROPPING, so a press mid-slam changes nothing;
    // the gate completes its drop first. Reproduced rather than tidied.
    var gate = Gate(modifier: 0)
    gate.drop()
    gate.raise(stuck: false)
    #expect(gate.phase == .fastDropping)
}

@Test func theWorldAdvancesItsGatesOncePerTick() throws {
    var world = try worldOne()
    world.pressButton(at: ref(4, 0))
    world.update()
    #expect(world.gate(at: ref(5, 0))?.position == -1)
    world.update()
    #expect(world.gate(at: ref(5, 0))?.position == -2)
}

// MARK: - The actor pressing a button by standing on it

@Test func standingOnAButtonPressesIt() throws {
    var world = try worldOne()
    // Room 5 row 0 is [PILLAR, TORCH, DROP_BUTTON, TORCH, RAISE_BUTTON, GATE, RAISE_BUTTON, ...].
    var actor = ActorState(location: 4, room: 5, face: 1, action: "stand")
    actor.actionCode = 1          // running — one of the codes that presses
    actor.charFcheck = true       // the frame's check bit must be set
    actor.updateBlockPosition(world: world)
    #expect(actor.charBlockX == 4)

    let pressed = TileChecks.checkButton(&actor, world: &world)
    #expect(pressed == ref(4, 0))
    #expect(world.gate(at: ref(5, 0))?.phase == .raising, "the chained gate moved")
}

@Test func aFallingActorDoesNotPressButtons() throws {
    var world = try worldOne()
    var actor = ActorState(location: 4, room: 5, face: 1, action: "stepfall")
    actor.actionCode = 3          // falling is deliberately absent from the reference's switch
    actor.charFcheck = true
    actor.updateBlockPosition(world: world)
    #expect(TileChecks.checkButton(&actor, world: &world) == nil)
    #expect(world.gate(at: ref(5, 0))?.phase == .closed)
}

@Test func aFrameWithoutTheCheckBitDoesNotPressButtons() throws {
    var world = try worldOne()
    var actor = ActorState(location: 4, room: 5, face: 1, action: "stand")
    actor.actionCode = 1
    actor.charFcheck = false
    actor.updateBlockPosition(world: world)
    #expect(TileChecks.checkButton(&actor, world: &world) == nil)
}

// MARK: - Rendering

@Test func aGateDrawsFourSpritesAndSlidesItsPanel() throws {
    let world = try worldOne()
    let description = RoomRenderer.describe(world: world, room: 5)

    // Gate.js puts the moving front panel at (32, 16) within the tile, so it is not at the
    // tile origin — matching on the frame name is the only reliable way to find it.
    let columnFive = 5 * Geometry.blockWidth
    let rowZero = -RoomRenderer.tileOverhang

    let closedGate = description.sprites.filter { $0.frameName.hasSuffix("_gate") }
    #expect(closedGate.count == 2, "one per gate in room 5")
    #expect(closedGate.allSatisfy { $0.frameName == "dungeon_gate" })

    let closedPanels = description.sprites.filter { $0.frameName == "dungeon_gate" }
    let atColumnFive = try #require(closedPanels.first { $0.x == columnFive })
    #expect(atColumnFive.clipTop == 0, "a closed gate shows its whole panel")
    #expect(atColumnFive.y == rowZero)

    #expect(description.sprites.contains { $0.frameName == "dungeon_4" })
    #expect(description.sprites.contains { $0.frameName == "dungeon_4_fg" })

    // Column 9: the gate that starts open, 46 of its 47 pixels raised.
    let columnNine = 9 * Geometry.blockWidth
    let openPanel = try #require(closedPanels.first { $0.x == columnNine })
    #expect(openPanel.clipTop == 46)

    let frontPanels = description.sprites.filter { $0.frameName == "dungeon_gate_fg" }
    let openFront = try #require(frontPanels.first { $0.x == columnNine + 32 })
    #expect(openFront.clipTop == 46)
    #expect(openFront.y == rowZero + 16, "Gate.js: make.sprite(32, 16, ...)")
    #expect(frontPanels.count == 2)
}

@Test(arguments: GameData.levelNumbers)
func everyGateFrameExistsInTheAtlas(number: Int) throws {
    // The exhaustive M4 test builds descriptions without a world, so gate parts are excluded
    // there. This one supplies a world, which is what emits them.
    let world = World(try LevelRuntime(try GameData.level(number)))
    let background = try GameData.atlasFrameNames(
        named: world.level.data.type == .dungeon ? "dungeon" : "palace"
    )
    var missing: Set<String> = []
    for room in world.level.roomNumbers {
        for sprite in RoomRenderer.describe(world: world, room: room).sprites
        where !background.contains(sprite.frameName) {
            missing.insert(sprite.frameName)
        }
    }
    #expect(missing.isEmpty, "level \(number) needs frames the atlas lacks: \(missing.sorted())")
}
