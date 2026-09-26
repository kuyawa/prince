import Foundation

/// A command operand.
///
/// `p1` is polymorphic in the data: usually a number, but for `CMD_GOTO` (255) it is
/// the *name* of the target sequence, e.g. `{ "cmd": 255, "p1": "running", "p2": 1 }`.
public enum Operand: Sendable, Equatable, Decodable {
    case number(Int)
    case name(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .name(value)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Operand is neither an integer nor a sequence name")
        )
    }

    public var intValue: Int? {
        if case let .number(value) = self { return value }
        return nil
    }

    public var nameValue: String? {
        if case let .name(value) = self { return value }
        return nil
    }
}

/// One instruction in a sequence program.
///
/// This is the game's bytecode. `command` indexes the 256-entry opcode table; see
/// ARCHITECTURE.md §7.2 for the table and `reference/PrinceJS/src/Actor.js` for the
/// dispatch loop that executes it.
public struct Instruction: Sendable, Equatable, Decodable {
    public let command: UInt8
    public let p1: Operand?
    public let p2: Int?

    private enum CodingKeys: String, CodingKey {
        case command = "cmd"
        case p1, p2
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(Int.self, forKey: .command)
        guard let command = UInt8(exactly: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .command, in: container,
                debugDescription: "Opcode \(raw) does not fit in a byte"
            )
        }
        self.command = command
        self.p1 = try container.decodeIfPresent(Operand.self, forKey: .p1)
        self.p2 = try container.decodeIfPresent(Int.self, forKey: .p2)
    }
}

/// An actor's animation data: named sequence programs plus the frame table they
/// index into.
///
/// Port source: `reference/PrinceJS/assets/anims/*.json`. `kid.json` alone holds 75
/// sequences.
public struct AnimationTable: Sendable, Decodable {
    /// Sequence name to program. Each program is executed by `processCommand`
    /// until it emits a frame.
    public let sequences: [String: [Instruction]]

    /// Indexed by the `p1` of a `CMD_FRAME` (0) instruction.
    public let frameDefs: [FrameDef]

    private enum CodingKeys: String, CodingKey {
        case sequences = "sequence"
        case frameDefs = "framedef"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Not every table declares both keys, and a missing one means "none",
        // not "corrupt". Making these required would reject valid data.
        self.sequences = try container.decodeIfPresent([String: [Instruction]].self,
                                                       forKey: .sequences) ?? [:]
        self.frameDefs = try container.decodeIfPresent([FrameDef].self,
                                                       forKey: .frameDefs) ?? []
    }

    public func sequence(_ name: String) -> [Instruction]? {
        sequences[name]
    }

    public var sequenceNames: [String] {
        sequences.keys.sorted()
    }
}
