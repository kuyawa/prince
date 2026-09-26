/// The `fcheck` byte, unpacked.
///
/// From `reference/PrinceJS/src/Actor.js#updateCharFrame`:
///
/// ```js
/// let fcheck = parseInt(framedef.fcheck, 16);
/// this.charFfoot  = fcheck & 0x1f;
/// this.charFthin  = (fcheck & 0x20) === 0x20;
/// this.charFcheck = (fcheck & 0x40) === 0x40;
/// this.charFood   = (fcheck & 0x80) === 0x80;
/// ```
///
/// These four values drive foot placement and collision extents. They are not
/// decoration — losing a bit here changes where the Prince can stand.
///
/// 50 distinct values appear across the shipped animation tables, from `0x00` to `0xEF`.
public struct FrameCheck: Sendable, Equatable, Decodable {
    public let rawValue: UInt8

    /// Bits 0–4: which sub-tile pixel column the actor's foot occupies.
    public var foot: UInt8 { rawValue & 0x1f }

    /// Bit 5: thin/edge collision — the actor's footprint is one tile, not two.
    public var isThin: Bool { rawValue & 0x20 != 0 }

    /// Bit 6: whether the engine runs a tile check on this frame.
    public var isCheckActive: Bool { rawValue & 0x40 != 0 }

    /// Bit 7: half-pixel parity correction — `Actor.updateCharPosition` adds 0.5 to the
    /// drawn x depending on facing.
    public var isHalfPixelOffset: Bool { rawValue & 0x80 != 0 }

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Decodes the on-disk spelling, `"0xC4"`. Accepts a lowercase `0x` prefix and
    /// either hex case, because the data is inconsistent about it.
    public init(hexString: String) throws {
        let trimmed = hexString.hasPrefix("0x") || hexString.hasPrefix("0X")
            ? String(hexString.dropFirst(2))
            : hexString
        guard let value = UInt8(trimmed, radix: 16) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Not a hex byte: \(hexString)")
            )
        }
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        try self.init(hexString: text)
    }
}
