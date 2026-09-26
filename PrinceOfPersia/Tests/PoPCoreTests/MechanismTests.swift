import Testing
@testable import PoPCore

// M7b: loose boards and the exit door.
//
// Level 1's first puzzle is a loose board: room 1's row 2 is
//   [WALL WALL WALL WALL DEBRIS PILLAR LOOSE FLOOR FLOOR WALL]
// so the board at column 6 is the way out of the Prince's cell.
//
// The exit is in room 9, at row 1 columns 3 and 4 (EXIT_LEFT then EXIT_RIGHT), opened by the
// raise button at (0,0) whose modifier 3 indexes events[3] — room 9, location 14.

private func worldOne() throws -> World {
    World(try LevelRuntime(try GameData.level(1)))
}

private func boardRef() -> TileRef { TileRef(room: 1, x: 6, y: 2) }

// MARK: - Loose boards

@Test func aLooseBoardShakesForEightFramesThenGivesWay() throws {
    var board = LooseBoard()
    #expect(board.phase == .inactive)

    board.shake(fall: true)
    #expect(board.phase == .shaking)
    #expect(board.step == 0)

    // Eight increments of the shake, then one more to tip it over.
    for _ in 0..<8 { board.update() }
    #expect(board.phase == .shaking)
    #expect(board.step == LooseBoard.shakeFrames)

    board.update()
    #expect(board.phase == .falling)
}

@Test func aBoardThatWasOnlyNudgedSettlesBack() {
    // Shaken without being stood on, it resets at frame 3 instead of collapsing. That
    // distinction is the entire reason `shake(fall:)` takes a flag.
    var board = LooseBoard()
    board.shake(fall: false)
    for _ in 0..<4 { board.update() }
    #expect(board.phase == .inactive, "settled at frame 3 rather than falling")
}

@Test func fallStartedOnlyReportsTheTippingFrame() {
    var board = LooseBoard()
    board.shake(fall: true)
    for _ in 0..<8 { board.update() }
    #expect(board.fallStarted)
    board.update()
    #expect(!board.fallStarted, "already falling")
}

@Test func aCollapsedBoardLeavesAHoleInTheFloor() throws {
    // Level.floorStartFall replaces the tile with TILE_SPACE outright. The hole *is* the
    // mechanism — nothing tells the Prince to fall.
    var world = try worldOne()
    #expect(world.tile(x: 6, y: 2, room: 1).kind == .looseBoard)
    #expect(world.state.trob(at: boardRef())?.looseBoard != nil)

    world.shakeLooseBoard(at: boardRef())
    for _ in 0..<9 { world.update() }

    #expect(world.tile(x: 6, y: 2, room: 1).kind == .space, "the board is gone")
    #expect(world.state.override(at: boardRef())?.kind == .space)
}

@Test func thePrinceFallsThroughACollapsingBoard() throws {
    var world = try worldOne()
    // blockX comes from the FOOT, and the offset that puts it there arrives with the frame
    // definition when the sequence runs — not at construction. Column 7's centre puts the foot
    // on column 6 once frame 15 is applied, so the assertion is on the outcome, not the setup.
    var actor = ActorState(location: 27, room: 1, face: 1, action: "stand")
    actor.actionCode = 1          // running — the standing branch that probes the floor
    actor.charFcheck = true
    actor.updateBlockPosition(world: world)

    let level = world.level
    let interpreter = SequenceInterpreter(
        table: try GameData.animationTable(named: "kid"), actorClass: .kid
    )
    var effects: [ActorEffect] = []

    var fellOnTick = 0
    for tick in 1...30 {
        effects.removeAll()
        try? Behaviour.update(&actor, intents: .none, world: world, interpreter: makeKidInterpreter(), effects: &effects)
        world.apply(effects)
        try interpreter.step(&actor, world: world, effects: &effects)
        world.apply(effects)
        try FallCycle.checkFloorStanding(
            &actor, world: world, interpreter: interpreter, effects: &effects
        )
        world.apply(effects)
        world.update()
        if actor.action == "stepfall" { fellOnTick = tick; break }
    }

    // Nine ticks for the board to collapse, then the floor probe finds space under his foot.
    #expect(fellOnTick == 10, "started falling on tick \(fellOnTick)")
    #expect(world.tile(x: 6, y: 2, room: 1).kind == .space, "the board is gone")
    _ = level
}

// MARK: - Exit doors

@Test func anExitDoorRaisesUntilOnlyAStubRemains() throws {
    let door = ExitDoor(modifier: 0, isPalace: false, startsOpen: false)
    #expect(door.phase == .closed)
    #expect(door.visibleHeight == 51)
    #expect(door.openHeight == 8)
    #expect(!door.isOpen)

    var raising = door
    raising.raise()
    // 43 pixels to remove, then one more tick to declare it open.
    for _ in 0..<43 { raising.update() }
    #expect(raising.visibleHeight == 8)
    #expect(raising.phase == .raising)

    raising.update()
    #expect(raising.phase == .open)
    #expect(raising.isOpen)
    #expect(raising.clipTop == 43)
}

@Test func anExitDoorDropsFifteenPixelsATick() {
    var door = ExitDoor(modifier: 0, isPalace: false, startsOpen: true)
    #expect(door.phase == .open)
    door.drop()
    #expect(door.phase == .dropping)
    door.update()
    #expect(door.visibleHeight == 23, "8 + 15")
    for _ in 0..<3 { door.update() }
    #expect(door.phase == .closed)
    #expect(door.visibleHeight == 51)
}

@Test func aPalaceDoorOpensOnePixelWider() {
    // `heightOpen = 8 + type`.
    #expect(ExitDoor(modifier: 0, isPalace: false, startsOpen: false).openHeight == 8)
    #expect(ExitDoor(modifier: 0, isPalace: true, startsOpen: false).openHeight == 9)
}

@Test func roomNinesRaiseButtonOpensTheExit() throws {
    var world = try worldOne()
    let exit = TileRef(room: 9, x: 4, y: 1)
    #expect(world.state.trob(at: exit)?.exitDoor?.phase == .closed)

    // The button at (0,0) carries modifier 3, which indexes events[3] — room 9, location 14.
    // That resolves to the EXIT_LEFT at column 3, which fireEvent redirects to column 4.
    world.pressButton(at: TileRef(room: 9, x: 0, y: 0))

    #expect(world.state.trob(at: exit)?.exitDoor?.phase == .raising)
    #expect(world.state.isExitDoorOpen)
}

// MARK: - Climbing out

@Test func jumpingOnAnOpenExitClimbsTheStairs() throws {
    var world = try worldOne()
    let exit = TileRef(room: 9, x: 4, y: 1)
    world.pressButton(at: TileRef(room: 9, x: 0, y: 0))
    for _ in 0..<44 { world.update() }
    #expect(world.state.trob(at: exit)?.exitDoor?.isOpen == true)

    // The Prince stands on the right half of the door, facing right.
    var actor = ActorState(location: 14, room: 9, face: 1, action: "stand")
    actor.updateBlockPosition(world: world)
    #expect(actor.charBlockX == 4)

    var effects: [ActorEffect] = []
    Behaviour.jump(&actor, world: world, effects: &effects)

    #expect(actor.action == "climbstairs")
    #expect(actor.charFace == -1, "he turns to face the stairs")
    #expect(actor.charBlockX == 3, "climbstairs steps onto the left half")
    #expect(effects.contains(.leavingLevel))
    #expect(effects.contains(.maskedExitDoor(TileRef(room: 9, x: 3, y: 1))))
}

@Test func jumpingOnAClosedExitDoesNothingSpecial() throws {
    let world = try worldOne()
    var actor = ActorState(location: 14, room: 9, face: 1, action: "stand")
    actor.updateBlockPosition(world: world)

    var effects: [ActorEffect] = []
    Behaviour.jump(&actor, world: world, effects: &effects)
    #expect(actor.action != "climbstairs")
    #expect(!effects.contains(.leavingLevel))
}

// MARK: - The jump decision tree

@Test func jumpingUnderOpenSpaceHighJumps() throws {
    let world = try worldOne()
    // Room 1 row 1 column 0 is a torch; row 0 column 0 is space. Space above, nothing
    // climbable in front -> highjump.
    var actor = ActorState(location: 10, room: 1, face: 1, action: "stand")
    actor.updateBlockPosition(world: world)
    #expect(actor.charBlockX == 0)

    var effects: [ActorEffect] = []
    Behaviour.jump(&actor, world: world, effects: &effects)
    #expect(actor.action == "highjump")
}

@Test func jumpingUnderASolidCeilingJustJumps() throws {
    let world = try worldOne()
    // Room 1 row 0 column 3 is floor with the room's edge above it — nothing to hang from.
    var actor = ActorState(location: 3, room: 1, face: 1, action: "stand")
    actor.updateBlockPosition(world: world)
    #expect(actor.charBlockX == 3)

    var effects: [ActorEffect] = []
    Behaviour.jump(&actor, world: world, effects: &effects)
    #expect(actor.action == "jumpup")
    #expect(actor.isInJumpUp)
}

@Test func jumpingUnderGrabableSpaceHangsLong() throws {
    let world = try worldOne()
    // Room 1: standing at (2,1) with space above at (2,0) and floor beyond it at (3,0).
    // Jump space overhead plus something climbable in front is the `jumphanglong` branch.
    var actor = ActorState(location: 12, room: 1, face: 1, action: "stand")
    actor.charBlockX = 2
    actor.charBlockY = 1
    actor.charX = CoordinateSpace.x(fromBlockX: 2)
    actor.charFdx = 0
    actor.charFfoot = 0
    #expect(world.tile(x: 2, y: 0, room: 1).kind == .space)
    #expect(world.tile(x: 3, y: 0, room: 1).kind == .floor)

    var effects: [ActorEffect] = []
    Behaviour.jump(&actor, world: world, effects: &effects)
    #expect(actor.action == "jumphanglong")
    #expect(actor.charX == CoordinateSpace.x(fromBlockX: 2) + 12, "facing right: +12")
}

// MARK: - Rendering

@Test func anExitDoorDrawsItsPanelAtTenTwelve() throws {
    let world = try worldOne()
    let description = RoomRenderer.describe(world: world, room: 9)

    // ExitDoor.js: make.sprite(10, 12, key, key + "_door").
    let baseX = 4 * Geometry.blockWidth
    let baseY = 1 * Geometry.blockHeight - RoomRenderer.tileOverhang
    let panel = try #require(description.sprites.first { $0.frameName == "dungeon_door" })
    #expect(panel.x == baseX + 10)
    #expect(panel.y == baseY + 12)
    #expect(panel.clipTop == 0, "closed, so the whole panel shows")
    #expect(description.sprites.contains { $0.frameName == "dungeon_17" })
    #expect(description.sprites.contains { $0.frameName == "dungeon_17_fg" })
    // The front graphic only appears once he starts climbing.
    #expect(!description.sprites.contains { $0.frameName == "dungeon_door_fg" })
}

@Test func anOpenExitDoorClipsItsPanel() throws {
    var world = try worldOne()
    world.pressButton(at: TileRef(room: 9, x: 0, y: 0))
    for _ in 0..<44 { world.update() }

    let description = RoomRenderer.describe(world: world, room: 9)
    let panel = try #require(description.sprites.first { $0.frameName == "dungeon_door" })
    #expect(panel.clipTop == 43, "51 - 8")
}

@Test func aShakingBoardDrawsItsShakeFrame() throws {
    var world = try worldOne()
    world.shakeLooseBoard(at: boardRef())
    world.update()

    let description = RoomRenderer.describe(world: world, room: 1)
    // Loose.frames run "_loose_1" ... "_loose_8", and the reference sets the frame BEFORE
    // incrementing the step — so step 0 is `_loose_1` and one update lands on `_loose_2`.
    #expect(description.sprites.contains { $0.frameName == "dungeon_loose_2" })
    #expect(!description.sprites.contains { $0.frameName == "dungeon_11" })
}

@Test func aFallenBoardDrawsTheFallingGraphic() throws {
    var world = try worldOne()
    world.shakeLooseBoard(at: boardRef())
    for _ in 0..<9 { world.update() }

    let description = RoomRenderer.describe(world: world, room: 1)
    #expect(description.sprites.contains { $0.frameName == "dungeon_falling" })
}
