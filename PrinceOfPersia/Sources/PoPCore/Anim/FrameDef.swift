/// One animation frame definition.
///
/// Port source: `reference/PrinceJS/src/Actor.js#updateCharFrame` and the `framedef`
/// array in `reference/PrinceJS/assets/anims/*.json`.
///
/// **Every numeric field is optional, because the shipped tables contain entries
/// that carry only a `comment`.** `kid.json` has 19 such entries, `shadow.json` 13 and
/// `fighter.json` 1. In JavaScript they read as `undefined` and are never dereferenced,
/// which is only safe because no sequence ever targets them — a claim the test suite
/// verifies rather than assumes (`referencedFramesAreComplete`). Modelling these as
/// non-optional would have rejected valid data at load time.
public struct FrameDef: Sendable, Equatable, Decodable {
    /// Horizontal draw offset *within* the sequence, before facing is applied. `fdx`.
    public let dx: Int?

    /// Vertical draw offset within the sequence. `fdy`.
    public let dy: Int?

    /// Collision and foot-placement flags. `fcheck`, stored as a hex string like `"0xC4"`.
    public let check: FrameCheck?

    /// Index of the sword overlay offset for this frame. `fsword`. Absent on most
    /// frames — 214 of `kid.json`'s 241.
    public let swordFrame: Int?

    /// Authoring notes in the data. Carries no behaviour.
    public let comment: String?

    private enum CodingKeys: String, CodingKey {
        case dx = "fdx"
        case dy = "fdy"
        case check = "fcheck"
        case swordFrame = "fsword"
        case comment
    }

    /// `true` when the entry carries usable animation data rather than only a note.
    public var isComplete: Bool {
        dx != nil && dy != nil && check != nil
    }
}
