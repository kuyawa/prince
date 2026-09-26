/// Which animation table and which opcode set an actor runs.
///
/// Port source: the class each actor is constructed as, and the `animKey` argument
/// `Enemy`'s constructor passes to `Fighter`:
///
/// ```js
/// PrinceJS.Fighter.call(this, game, level, location, direction, room, key,
///                        key === "shadow" ? "shadow" : "fighter");
/// ```
///
/// So every guard, fat guard, skeleton and Jaffar reads `fighter.json`, only the shadow reads
/// `shadow.json`, and each has its own *sprite* atlas named for its `charName`.
public enum ActorKind {
    /// The animation table a `charName` reads its sequences from.
    public static func animationTable(for charName: String) -> String {
        switch charName {
        case "kid": "kid"
        case "shadow": "shadow"
        case "princess": "princess"
        case "vizier": "vizier"
        case "mouse": "mouse"
        case "sword": "sword"
        default: "fighter"      // guard, guard-N, fatguard, skeleton
        }
    }

    /// The opcode set the actor registers — see `ActorClass`.
    public static func actorClass(for charName: String) -> ActorClass {
        charName == "kid" ? .kid : .fighter
    }

    /// The sprite atlas a `charName` draws from. Every actor's frames are named
    /// `<charName>-<frame>` inside an atlas of the same name.
    public static func atlasName(for charName: String) -> String { charName }

    /// `Enemy`'s constructor turns a plain `"guard"` into `"guard-<colour>"`.
    public static func enemyCharName(type: GuardType, colour: Int) -> String {
        switch type {
        case .guard: "guard-\(max(1, min(7, colour)))"
        case .skeleton: "skeleton"
        case .shadow: "shadow"
        case .fatguard: "fatguard"
        case .jaffar: "vizier"
        }
    }
}
