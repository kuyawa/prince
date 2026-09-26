/// The sequence virtual machine — the heart of the game.
///
/// Port source: `reference/PrinceJS/src/Actor.js#processCommand` plus the `CMD_*`
/// handlers in `Actor.js`, `Fighter.js`, `Kid.js`, `Enemy.js` and `Mouse.js`.
///
/// ```js
/// processCommand: function () {
///   this.processing = true;
///   while (this.processing) {
///     let data = this.anims.sequence[this._action][this._seqpointer];
///     this.commands[data.cmd](data);
///     this._seqpointer++;
///   }
/// }
/// ```
///
/// **The loop runs until a `FRAME` opcode clears the flag**, so a single tick consumes
/// every non-frame instruction it meets and stops on exactly one frame. Implementing
/// this as "one opcode per tick" makes the game run at a fraction of its real speed and
/// nothing will feel right.
///
/// The interpreter is a value type with no stored world: it reads the table, folds the
/// state, and appends effects. That is what makes the whole VM testable with no window.
public struct SequenceInterpreter: Sendable {
    public let table: AnimationTable
    public let actorClass: ActorClass

    /// The sword overlay offsets, if this actor can hold a sword.
    ///
    /// `Fighter.updateSwordFrame` indexes it with `swordtab[framedef.fsword - 1]` — a **1-based
    /// positional** index, not a lookup by the table's `id` field. Open question 9, resolved when
    /// this line was found.
    public let swordOffsets: SwordOffsetTable?

    /// Safety stop for a malformed sequence that never emits a frame.
    ///
    /// The reference has no such guard — a bad `GOTO` loop hangs the browser. The
    /// longest shipped sequence is well under a hundred instructions, so this cannot
    /// fire on valid data; it converts a hang into a diagnosable error.
    public static let instructionBudget = 4096

    public init(
        table: AnimationTable,
        actorClass: ActorClass,
        swordOffsets: SwordOffsetTable? = nil
    ) {
        self.table = table
        self.actorClass = actorClass
        self.swordOffsets = swordOffsets
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case unknownSequence(String)
        case cursorOutOfRange(action: String, pointer: Int, count: Int)
        case frameIndexOutOfRange(action: String, index: Int, count: Int)
        case goToWithoutTarget(String)
        case goToWithoutDestination(String)
        case instructionBudgetExceeded(action: String, budget: Int)

        public var description: String {
            switch self {
            case let .unknownSequence(action):
                "No such sequence: \(action)"
            case let .cursorOutOfRange(action, pointer, count):
                "Sequence \(action): cursor \(pointer) is outside 0..<\(count)"
            case let .frameIndexOutOfRange(action, index, count):
                "Sequence \(action) targets frame \(index); the table holds \(count)"
            case let .goToWithoutTarget(action):
                "Sequence \(action): GOTO with no target sequence name"
            case let .goToWithoutDestination(action):
                "Sequence \(action): GOTO with no destination index (p2)"
            case let .instructionBudgetExceeded(action, budget):
                "Sequence \(action) ran \(budget) instructions without emitting a frame"
            }
        }
    }

    /// Runs the sequence until a frame is emitted, exactly as the reference loop does.
    ///
    /// - Parameters:
    ///   - state: folded in place. `state.sequencePointer` is left pointing just past
    ///     the `FRAME` instruction that ended the tick.
    ///   - world: consulted only by `UP` (253). `nil` is faithful — it matches the
    ///     reference's `if (this.level.rooms[this.room])` guard failing.
    ///   - effects: appended to, never cleared. The caller owns the lifetime.
    public func step(
        _ state: inout ActorState,
        world: (any ActorWorldQuery)? = nil,
        effects: inout [ActorEffect]
    ) throws {
        state.isProcessing = true
        var executed = 0

        while state.isProcessing {
            guard executed < Self.instructionBudget else {
                throw Failure.instructionBudgetExceeded(
                    action: state.action, budget: Self.instructionBudget
                )
            }

            guard let program = table.sequences[state.action] else {
                throw Failure.unknownSequence(state.action)
            }
            guard program.indices.contains(state.sequencePointer) else {
                throw Failure.cursorOutOfRange(
                    action: state.action, pointer: state.sequencePointer, count: program.count
                )
            }

            let instruction = program[state.sequencePointer]
            try execute(instruction, &state, world, &effects)
            state.sequencePointer += 1
            executed += 1
        }
    }

    // MARK: - Dispatch

    private func execute(
        _ instruction: Instruction,
        _ state: inout ActorState,
        _ world: (any ActorWorldQuery)?,
        _ effects: inout [ActorEffect]
    ) throws {
        // Unregistered bytes are silent no-ops — the reference fills all 256 slots with
        // CMD_NOOP before overriding any of them. Two distinct cases land here: a byte
        // that is not an opcode at all, and a real opcode this actor class never
        // registered (guards running JARD, the shadow running EFFECT, and so on).
        guard let opcode = Opcode(rawValue: instruction.command),
              actorClass.registers(opcode)
        else { return }

        switch opcode {
        case .frame:
            let index = instruction.p1?.intValue ?? state.charFrame
            guard table.frameDefs.indices.contains(index) else {
                throw Failure.frameIndexOutOfRange(
                    action: state.action, index: index, count: table.frameDefs.count
                )
            }
            state.charFrame = index
            state.applyFrameDefinition(table.frameDefs[index], swordOffsets: swordOffsets)
            // Room transitions happen here, inside the sequence, exactly as in the reference:
            // `CMD_FRAME` is the only caller of `updateBlockXY`.
            state.updateBlockPosition(world: world)
            state.isProcessing = false

        case .goTo:
            // Assigns _action and _seqpointer DIRECTLY, bypassing the setter. The loop
            // then increments, so execution resumes at index p2.
            guard let target = instruction.p1?.nameValue else {
                throw Failure.goToWithoutTarget(state.action)
            }
            guard let destination = instruction.p2 else {
                throw Failure.goToWithoutDestination(state.action)
            }
            state.action = target
            state.sequencePointer = destination - 1

        case .changeX:
            state.charX += (instruction.p1?.intValue ?? 0) * state.charFace

        case .changeY:
            state.charY += instruction.p1?.intValue ?? 0

        case .aboutFace:
            state.charFace = -state.charFace

        case .act:
            let code = instruction.p1?.intValue ?? 0
            state.actionCode = code
            if code == 1 {
                state.charXVel = 0
                state.charYVel = 0
            }

        case .setFall:
            state.charXVel = (instruction.p1?.intValue ?? 0) * state.charFace
            state.charYVel = instruction.p2 ?? 0

        case .die:
            state.isAlive = false
            state.swordDrawn = false
            effects.append(.died)

        case .ifWithLess:
            // Despite the name and its p1 operand, the reference reads neither — it
            // simply swaps the current fall for its floating variant. That is why
            // shadow.json's reference to a sequence it never defines is inert.
            guard state.isInFloat else { break }
            switch state.action {
            case "stepfall": state.beginAction("stepfloat")
            case "bumpfall": state.beginAction("bumpfloat")
            case "highjump": state.beginAction("superhighjump")
            default: break
            }

        case .tap:
            effects.append(.tap(instruction.p1?.intValue ?? 0))

        case .effect:
            break

        case .up:
            guard state.charBlockY == 0 else { break }
            state.charY += Geometry.roomHeight
            state.baseY -= Geometry.roomHeight
            state.charBlockY = 2
            if let links = world?.roomLinks(state.room) {
                state.room = links.up
                effects.append(.enteredRoom(state.room))
            }

        case .down:
            guard state.charBlockY == 2, state.charY > Geometry.roomHeight else { break }
            state.charY -= Geometry.roomHeight
            state.baseY += Geometry.roomHeight
            state.charBlockY = 0
            effects.append(.exitedRoomDown)

        case .jard:
            effects.append(.shakeFloor(room: state.room, row: state.charBlockY))

        case .jaru:
            effects.append(.shakeFloorAbove(
                room: state.room, column: state.charBlockX, row: state.charBlockY - 1
            ))

        case .nextLevel:
            effects.append(.advanceToNextLevel)
        }
    }
}
