/// The sword overlay offsets, indexed by `FrameDef.swordFrame`.
///
/// Port source: `reference/PrinceJS/assets/anims/sword.json`, whose only key is
/// `swordtab`. It shares a file extension with the animation tables but not a schema,
/// which is why it is modelled separately.
///
/// **Open:** whether `FrameDef.swordFrame` indexes this array positionally or matches
/// `id` is unresolved — the ids are not contiguous (`1, 6, 2, 3, 7, 8, 4, 5, 31, 9…`).
/// Resolve against `reference/PrinceJS/src/Actor.js` when the sword is implemented
/// (M7). Until then both readings are available and neither is assumed.
public struct SwordOffsetTable: Sendable, Decodable {
    public let offsets: [SwordOffset]

    private enum CodingKeys: String, CodingKey {
        case offsets = "swordtab"
    }

    /// Lookup by the explicit `id` field.
    public func offset(id: Int) -> SwordOffset? {
        offsets.first { $0.id == id }
    }

    /// Lookup by array position.
    public func offset(at index: Int) -> SwordOffset? {
        offsets.indices.contains(index) ? offsets[index] : nil
    }

    public var count: Int { offsets.count }
}

public struct SwordOffset: Sendable, Decodable, Equatable {
    public let id: Int
    public let dx: Int
    public let dy: Int
}
